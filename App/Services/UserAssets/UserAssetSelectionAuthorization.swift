import Foundation

/// An exact-source permission change participates in the caller's existing engine
/// transaction. Metadata mutation remains MainActor-confined like UserAssetStore's
/// manifest/watcher writes: no callback can overwrite a read-modify-write phase.
/// Large attachment/document IO belongs to the caller's off-main preparation.
enum UserAssetSelectionAuthorization {
  private static let maximumManifestBytes = 48 * 1024 * 1024

  @MainActor
  static func perform(managed: ManagedUserAssetStore, wallpaperID: String,
                      selections: [String: String], commit: @MainActor () async throws -> Void) async throws {
    guard !selections.isEmpty else { try await commit(); return }
    let url = try managed.wallpaperRoot(wallpaperID).appendingPathComponent(UserAssetManifest.fileName)
    // No existing property record means there is no retained-only restriction to lift.
    guard FileManager.default.fileExists(atPath: url.path) else { try await commit(); return }
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
    guard !scopes.isEmpty else { try await commit(); return }
    let grantedData = try encode(granted)
    do {
      try grantedData.write(to: url, options: .atomic)
      try await commit()
    } catch {
      let cause = error
      do { try rollback(url: url, originalData: data, original: original, grantedData: grantedData, scopes: scopes) }
      catch {
        throw UserAssetSelectionAuthorizationError(message: String(localized: "The asset selection failed: \(cause.localizedDescription). Its permissions could not be restored: \(error.localizedDescription). Refresh before continuing."))
      }
      throw cause
    }
  }

  @MainActor
  private static func rollback(url: URL, originalData: Data, original: UserAssetManifest,
                               grantedData: Data, scopes: [String: String]) throws {
    let (data, latest) = try read(url)
    guard latest.wallpaperId == original.wallpaperId else { throw invalidManifest() }
    // No concurrent manifest update: restore exact original bytes/serialization.
    if data == grantedData {
      try originalData.write(to: url, options: .atomic)
      return
    }
    var current = latest
    var changed = false
    for (propertyID, scope) in scopes {
      guard var record = current.properties[propertyID], let previous = original.properties[propertyID],
            record.originalSourceUnauthorized != true, record.authorizedSourcePath == scope else { continue }
      // A newer selection wins. Restore only the two fields this transaction owns;
      // keep watcher-produced assets, source metadata, and unrelated records intact.
      record.originalSourceUnauthorized = previous.originalSourceUnauthorized
      record.authorizedSourcePath = previous.authorizedSourcePath
      current.properties[propertyID] = record
      changed = true
    }
    if changed { try encode(current).write(to: url, options: .atomic) }
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
