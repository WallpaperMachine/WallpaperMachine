import Foundation

/// An exact-source permission change participates in the caller's existing engine
/// transaction. Grant and rollback join background preparation's per-wallpaper
/// turn queue and short metadata lock; neither remains held over the engine await.
enum UserAssetSelectionAuthorization {
  private static let maximumManifestBytes = 48 * 1024 * 1024
  // Accessed only inside ManagedUserAssetStore.withManifestTransaction. A scope
  // string alone cannot distinguish two explicit selections of the same path.
  private struct PermissionEdit {
    let identity: UUID
    let before: ManagedUserAssetProperty
    let scope: String
    var failed = false
  }
  private struct RollbackPlan {
    let propertyID: String
    let before: ManagedUserAssetProperty
    let expectedScope: String
    let firstFailed: Int
  }
  nonisolated(unsafe) private static var permissionEdits: [String: [String: [PermissionEdit]]] = [:]

  @MainActor
  static func perform(managed: ManagedUserAssetStore, wallpaperID: String,
                      selections: [String: String], commit: @MainActor () async throws -> Void) async throws {
    guard !selections.isEmpty else { try await commit(); return }
    let url = try managed.wallpaperRoot(wallpaperID).appendingPathComponent(UserAssetManifest.fileName)
    let grant = try await managed.withPreparation(wallpaperId: wallpaperID) {
      try managed.withManifestTransaction {
        try prepareGrant(url: url, wallpaperID: wallpaperID, selections: selections)
      }
    }
    guard let grant else { try await commit(); return }
    do {
      try Task.checkCancellation()
      try await commit()
      managed.withManifestTransaction { finishSuccessfulGrant(url: url, grant: grant) }
    } catch {
      let cause = error
      // Rollback is cleanup and must complete even when the caller is cancelled.
      let rollback = Task.detached {
        try await managed.withPreparation(wallpaperId: wallpaperID) {
          try managed.withManifestTransaction {
            try Self.rollback(url: url, originalData: grant.originalData, original: grant.original,
              grantedData: grant.grantedData, scopes: grant.scopes, identity: grant.identity)
          }
        }
      }
      do { try await rollback.value }
      catch {
        throw UserAssetSelectionAuthorizationError(message: String(localized: "The asset selection failed: \(cause.localizedDescription). Its permissions could not be restored: \(error.localizedDescription). Refresh before continuing."))
      }
      throw cause
    }
  }

  private struct Grant: Sendable {
    let identity: UUID
    let originalData: Data
    let original: UserAssetManifest
    let grantedData: Data
    let scopes: [String: String]
  }

  private static func prepareGrant(url: URL, wallpaperID: String, selections: [String: String]) throws -> Grant? {
    // No existing property record means there is no retained-only restriction to lift.
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let (data, original) = try read(url)
    guard original.wallpaperId == wallpaperID else { throw invalidManifest() }
    var granted = original
    var scopes = [String: String]()
    for (propertyID, path) in selections {
      guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4096 else { throw invalidManifest() }
      guard var record = granted.properties[propertyID] else { continue }
      let scope = URL(fileURLWithPath: path).standardizedFileURL.path
      record.originalSourceUnauthorized = nil
      record.authorizedSourcePath = scope
      granted.properties[propertyID] = record
      scopes[propertyID] = scope
    }
    guard !scopes.isEmpty else { return nil }
    let grantedData = try encode(granted)
    try grantedData.write(to: url, options: .atomic)
    let identity = UUID()
    let key = url.resolvingSymlinksInPath().standardizedFileURL.path
    for (propertyID, scope) in scopes {
      guard let before = original.properties[propertyID] else { continue }
      permissionEdits[key, default: [:]][propertyID, default: []].append(
        PermissionEdit(identity: identity, before: before, scope: scope))
    }
    return Grant(identity: identity, originalData: data, original: original, grantedData: grantedData, scopes: scopes)
  }

  private static func rollback(url: URL, originalData: Data, original: UserAssetManifest,
                               grantedData: Data, scopes: [String: String], identity: UUID) throws {
    let key = url.resolvingSymlinksInPath().standardizedFileURL.path
    var plans: [RollbackPlan] = []
    for propertyID in scopes.keys {
      guard var edits = permissionEdits[key]?[propertyID],
            let index = edits.firstIndex(where: { $0.identity == identity }) else { continue }
      edits[index].failed = true
      permissionEdits[key]?[propertyID] = edits
      // A newer pending grant still owns the visible permission. Keep the failed
      // ancestor so a later failure can unwind both edits, in either completion order.
      guard index == edits.count - 1 else { continue }
      var firstFailed = index
      while firstFailed > 0 && edits[firstFailed - 1].failed { firstFailed -= 1 }
      plans.append(RollbackPlan(propertyID: propertyID, before: edits[firstFailed].before,
        expectedScope: edits[index].scope, firstFailed: firstFailed))
    }
    guard !plans.isEmpty else { return }
    let (data, latest) = try read(url)
    guard latest.wallpaperId == original.wallpaperId else { throw invalidManifest() }
    var current = latest
    var changed = false
    for plan in plans {
      guard var record = current.properties[plan.propertyID],
            record.originalSourceUnauthorized != true, record.authorizedSourcePath == plan.expectedScope else { continue }
      // Only permission fields belong to the grant: preserve new retained bytes,
      // source metadata and unrelated properties produced by background workers.
      record.originalSourceUnauthorized = plan.before.originalSourceUnauthorized
      record.authorizedSourcePath = plan.before.authorizedSourcePath
      current.properties[plan.propertyID] = record
      changed = true
    }
    if changed {
      if data == grantedData, current == original {
        try originalData.write(to: url, options: .atomic)
      } else {
        try encode(current).write(to: url, options: .atomic)
      }
    }
    for plan in plans {
      permissionEdits[key]?[plan.propertyID]?.removeSubrange(plan.firstFailed...)
      removeEmptyEdits(key: key, propertyID: plan.propertyID)
    }
  }

  private static func finishSuccessfulGrant(url: URL, grant: Grant) {
    let key = url.resolvingSymlinksInPath().standardizedFileURL.path
    for propertyID in grant.scopes.keys {
      guard let edits = permissionEdits[key]?[propertyID],
            let index = edits.firstIndex(where: { $0.identity == grant.identity }) else { continue }
      // A successful newer selection is now the durable baseline. Older failures
      // must not revoke it; newer pending edits still retain their own rollback state.
      permissionEdits[key]?[propertyID]?.removeFirst(index + 1)
      removeEmptyEdits(key: key, propertyID: propertyID)
    }
  }

  private static func removeEmptyEdits(key: String, propertyID: String) {
    if permissionEdits[key]?[propertyID]?.isEmpty == true { permissionEdits[key]?.removeValue(forKey: propertyID) }
    if permissionEdits[key]?.isEmpty == true { permissionEdits.removeValue(forKey: key) }
  }

  private static func read(_ url: URL) throws -> (Data, UserAssetManifest) {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
          size >= 0, size <= maximumManifestBytes else { throw invalidManifest() }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count <= maximumManifestBytes else { throw invalidManifest() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(UserAssetManifest.self, from: data)
    guard manifest.version == UserAssetManifest.currentVersion else { throw invalidManifest() }
    return (data, manifest)
  }

  private static func encode(_ manifest: UserAssetManifest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(manifest)
    guard data.count <= maximumManifestBytes else { throw invalidManifest() }
    return data
  }

  private static func invalidManifest() -> UserAssetSelectionAuthorizationError {
    UserAssetSelectionAuthorizationError(message: String(localized: "Retained asset permissions could not be read safely. Refresh before continuing."))
  }
}

struct UserAssetSelectionAuthorizationError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
