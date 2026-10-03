import CryptoKit
import Darwin
import Foundation

/// One file the app owns a copy of, on behalf of a `file` or `directory` property.
///
/// `assetId` is derived from the content digest, so re-picking a byte-identical
/// file lands on the entry that is already stored instead of making a second copy.
struct ManagedUserAsset: Codable, Equatable, Sendable {
    var assetId: String
    var fileName: String
    /// The user's own path, kept for display and for re-scanning a watched folder.
    /// Never used to serve bytes: the store's copy is the one that is read.
    var sourcePath: String
    var size: Int64
    var modified: Date
    /// Older manifests encode `modified` to whole seconds. Retain its exact value
    /// separately so an unchanged source can use the metadata-only fast path.
    var modifiedReferenceTime: Double? = nil
    /// SHA-256 of the file's bytes, lower-case hex.
    var digest: String

    var sourceModificationDate: Date {
        modifiedReferenceTime.map(Date.init(timeIntervalSinceReferenceDate:)) ?? modified
    }
}

/// What one property imported, and where it came from.
struct ManagedUserAssetProperty: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case file
        case directory
    }

    var kind: Kind
    /// The file or folder the user picked.
    var sourcePath: String
    /// Backup provenance is not permission to access the original. Missing in older
    /// locally-created manifests means the original selection remains authorized.
    var originalSourceUnauthorized: Bool?
    /// Explicit reselection scope prevents late callbacks for a departed source
    /// from granting access to that original again. Never trusted from a backup.
    var authorizedSourcePath: String?
    /// Stored files, ordered by file name.
    var assets: [ManagedUserAsset]
    /// True when the source folder held more matching files than the limit allowed.
    var truncated: Bool
    /// Legacy in-project staging directories already absorbed, so migration runs once.
    var migratedLegacyPaths: [String]

    init(
        kind: Kind, sourcePath: String, assets: [ManagedUserAsset] = [], truncated: Bool = false,
        migratedLegacyPaths: [String] = []
    ) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.assets = assets
        self.truncated = truncated
        self.migratedLegacyPaths = migratedLegacyPaths
    }
}

/// The system of record for one wallpaper's imported assets.
///
/// Written next to the stored bytes rather than into the wallpaper package: a
/// Workshop update replaces the package, and the manifest has to survive that.
struct UserAssetManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let fileName = "manifest.json"

    var version: Int = currentVersion
    var wallpaperId: String
    var properties: [String: ManagedUserAssetProperty] = [:]
}

/// Keeps the user's imported `file`/`directory` property assets in application
/// support, keyed by the stable wallpaper id rather than by display name or by
/// entry file name, so a Workshop update or a delete-and-re-download does not
/// lose them.
///
/// Layout: `UserAssets/<wallpaperId>/<propertyId>/<assetId>/<fileName>`, with
/// `UserAssets/<wallpaperId>/manifest.json` recording what each property holds.
///
/// Importing copies the user's file in — cloned with `clonefile` where the
/// filesystem supports it, so an APFS import costs no space until one side is
/// written. The user's original is never moved, renamed or written to.
final class ManagedUserAssetStore: @unchecked Sendable {
    private static let manifestLock = NSRecursiveLock()
    private static let preparationTurns = UserAssetPreparationTurns()
    let root: URL
    private let fileManager: FileManager
    private let beforePublication: @Sendable () throws -> Void
    private let beforePropertyCommit: @Sendable () throws -> Void
    private let onPreparationQueued: @Sendable () -> Void

    init(root: URL = ClientPaths.userAssetsURL, fileManager: FileManager = .default,
         beforePublication: @escaping @Sendable () throws -> Void = {},
         beforePropertyCommit: @escaping @Sendable () throws -> Void = {},
         onPreparationQueued: @escaping @Sendable () -> Void = {}) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        self.beforePublication = beforePublication
        self.beforePropertyCommit = beforePropertyCommit
        self.onPreparationQueued = onPreparationQueued
    }

    /// One complete preparation/commit/bridge publication per wallpaper, across
    /// store instances. Waiting suspends callers; hashing/copying never holds the
    /// metadata lock or blocks the main actor. Purge uses this same turn boundary,
    /// so adopted but not-yet-committed bytes cannot become cleanup candidates.
    func withPreparation<T: Sendable>(wallpaperId: String,
        operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let key = try wallpaperRoot(wallpaperId).resolvingSymlinksInPath().standardizedFileURL.path
        return try await Self.preparationTurns.perform(key: key, queued: onPreparationQueued, operation: operation)
    }

    /// Short read-modify-write phases only; never await or hash/copy file bytes here.
    func withManifestTransaction<T>(_ operation: () throws -> T) rethrows -> T {
        Self.manifestLock.lock()
        defer { Self.manifestLock.unlock() }
        return try operation()
    }

    // MARK: - Locations
    func wallpaperRoot(_ wallpaperId: String) throws -> URL {
        guard let component = Self.safeComponent(wallpaperId) else {
            throw UserAssetError(code: .invalidWallpaperID, reason: String(
                localized: "This wallpaper has an identifier that cannot be used as a folder."))
        }
        return root.appendingPathComponent(component, isDirectory: true)
    }

    func propertyRoot(wallpaperId: String, propertyId: String) throws -> URL {
        guard let component = Self.safeComponent(propertyId) else {
            throw UserAssetError(code: .invalidPropertyID, reason: String(
                localized: "This wallpaper property has a name that cannot be used as a folder."))
        }
        return try wallpaperRoot(wallpaperId).appendingPathComponent(component, isDirectory: true)
    }

    func storedURL(wallpaperId: String, propertyId: String, asset: ManagedUserAsset) throws -> URL {
        try propertyRoot(wallpaperId: wallpaperId, propertyId: propertyId)
            .appendingPathComponent(asset.assetId, isDirectory: true)
            .appendingPathComponent(asset.fileName)
    }

    /// A path component that cannot escape the store or collide with `.` / `..`.
    /// Wallpaper ids are numeric in practice; anything else is refused rather
    /// than sanitised into a different wallpaper's folder.
    private static func safeComponent(_ raw: String) -> String? {
        guard !raw.isEmpty, raw != ".", raw != "..",
              !raw.contains("/"), !raw.contains(":"), !raw.contains("\0"),
              !raw.hasPrefix(".") else { return nil }
        return raw
    }

    // MARK: - Manifest

    func manifest(wallpaperId: String) throws -> UserAssetManifest {
        Self.manifestLock.lock()
        defer { Self.manifestLock.unlock() }
        let url = try wallpaperRoot(wallpaperId).appendingPathComponent(UserAssetManifest.fileName)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            return UserAssetManifest(wallpaperId: wallpaperId)
        } catch {
            throw Self.unreadableManifest()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(UserAssetManifest.self, from: data),
              decoded.version == UserAssetManifest.currentVersion,
              decoded.wallpaperId == wallpaperId else {
            throw Self.unreadableManifest()
        }
        return decoded
    }

    private static func unreadableManifest() -> UserAssetError {
        UserAssetError(code: .manifestUnreadable, reason: String(
            localized: "The saved wallpaper file list could not be read. Your files have been kept."))
    }

    /// Written whole and atomically: a crash mid-write must not leave a manifest
    /// that lists half a property's files.
    func write(_ manifest: UserAssetManifest) throws {
        Self.manifestLock.lock()
        defer { Self.manifestLock.unlock() }
        let directory = try wallpaperRoot(manifest.wallpaperId)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appendingPathComponent(UserAssetManifest.fileName), options: .atomic)
    }

    /// Called only after an explicit user selection, including selecting the same
    /// original again. Runtime reconstruction must never grant this authority.
    func authorizeSelection(wallpaperId: String, propertyId: String, selectedSourcePath: String) throws {
        Self.manifestLock.lock()
        defer { Self.manifestLock.unlock() }
        var value = try manifest(wallpaperId: wallpaperId)
        guard var property = value.properties[propertyId] else { return }
        property.originalSourceUnauthorized = nil
        property.authorizedSourcePath = URL(fileURLWithPath: selectedSourcePath).standardizedFileURL.path
        value.properties[propertyId] = property
        try write(value)
    }

    /// A background preparation may only replace the property version it read.
    /// Merge against the newest manifest so a concurrent edit of another property survives.
    func updateProperty(wallpaperId: String, propertyId: String,
                        expected: ManagedUserAssetProperty?, replacement: ManagedUserAssetProperty?) throws {
        try beforePropertyCommit()
        Self.manifestLock.lock()
        defer { Self.manifestLock.unlock() }
        try Task.checkCancellation()
        var current = try manifest(wallpaperId: wallpaperId)
        guard current.properties[propertyId] == expected else { throw CancellationError() }
        current.properties[propertyId] = replacement
        try write(current)
    }
    // MARK: - Import

    /// Copies the bytes at `readingFrom` into the store unless an entry with the
    /// same content is already there, and records `sourcePath` as where the user's
    /// own copy lives.
    ///
    /// The two are the same for an ordinary import. They differ when a round-6
    /// in-project staging directory is migrated: the bytes are read from the staged
    /// link, while the path recorded is the original the property still names.
    ///
    /// `known` is the property's current manifest entry for this file name, which
    /// lets an unchanged file skip both the digest and the copy.
    func adopt(
        readingFrom source: URL, fileName: String, sourcePath: String,
        wallpaperId: String, propertyId: String, known: ManagedUserAsset?
    ) throws -> ManagedUserAsset {
        let values = try? source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values?.fileSize ?? 0)
        let modified = values?.contentModificationDate ?? .distantPast

        if let known, known.fileName == fileName, known.size == size,
           known.sourceModificationDate == modified, known.sourcePath == sourcePath,
           fileManager.fileExists(atPath: (try? storedURL(
               wallpaperId: wallpaperId, propertyId: propertyId, asset: known))?.path ?? "") {
            // Same bytes by every cheap measure, already stored: no digest, no copy.
            return known
        }

        // Only this temporary path belongs to this operation. A failed/cancelled
        // copy must never remove a winner another instance already published.
        let directory = try propertyRoot(wallpaperId: wallpaperId, propertyId: propertyId)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = directory.appendingPathComponent(".prepare-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: pending) }
        do {
            try Task.checkCancellation()
            try Self.copy(source, to: pending, fileManager: fileManager)
            try Task.checkCancellation()
        } catch is CancellationError { throw CancellationError() }
        catch {
            throw UserAssetError(code: .stagingFailed, reason: String(
                localized: "\(fileName) could not be copied into the app's asset folder."))
        }
        let digest = try Self.digest(of: pending)
        let retained = try pending.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let retainedModified = retained.contentModificationDate ?? .distantPast
        let asset = ManagedUserAsset(
            assetId: String(digest.prefix(32)), fileName: fileName, sourcePath: sourcePath,
            size: Int64(retained.fileSize ?? 0), modified: retainedModified,
            modifiedReferenceTime: retainedModified.timeIntervalSinceReferenceDate,
            digest: digest)
        let destination = try storedURL(wallpaperId: wallpaperId, propertyId: propertyId, asset: asset)
        try beforePublication()
        return try withManifestTransaction {
            try Task.checkCancellation()
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: pending, to: destination)
            }
            return asset
        }
    }

    /// Drops the stored directories a property no longer lists. Called after the
    /// manifest has been rewritten, so a failure here costs disk space and never
    /// a reference.
    func pruneUnlisted(wallpaperId: String, propertyId: String) {
        let retired: [URL] = withManifestTransaction {
            guard let current = try? manifest(wallpaperId: wallpaperId),
                  let directory = try? propertyRoot(wallpaperId: wallpaperId, propertyId: propertyId),
                  let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            else { return [] }
            // The caller's list may have been superseded since its commit.
            let live = Set((current.properties[propertyId]?.assets ?? []).map(\.assetId))
            return entries.filter { !live.contains($0.lastPathComponent) }
                .compactMap { retire($0, wallpaperId: wallpaperId) }
        }
        // Removing large directory trees does not hold the metadata lock.
        for entry in retired { try? fileManager.removeItem(at: entry) }
    }

    func removeProperty(wallpaperId: String, propertyId: String) {
        let retired: URL? = withManifestTransaction {
            guard let current = try? manifest(wallpaperId: wallpaperId), current.properties[propertyId] == nil,
                  let directory = try? propertyRoot(wallpaperId: wallpaperId, propertyId: propertyId) else { return nil }
            return retire(directory, wallpaperId: wallpaperId)
        }
        if let retired { try? fileManager.removeItem(at: retired) }
    }

    private func retire(_ url: URL, wallpaperId: String) -> URL? {
        guard let root = try? wallpaperRoot(wallpaperId) else { return nil }
        let retired = root.appendingPathComponent(".cleanup-\(UUID().uuidString)")
        do { try fileManager.moveItem(at: url, to: retired); return retired }
        catch { return nil }
    }

    // MARK: - Bytes

    /// Streams the file so a large video is never held in memory.
    static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `clonefile` first: on APFS an import costs metadata rather than the file's
    /// bytes, and the clone is a real independent file, so deleting the user's
    /// original still leaves the store's copy readable.
    static func copy(_ source: URL, to destination: URL, fileManager: FileManager = .default) throws {
        if clonefile(source.path, destination.path, 0) == 0 { return }
        try fileManager.copyItem(at: source, to: destination)
    }
}

private actor UserAssetPreparationTurns {
    private struct Turn { let id: UUID; let completion: Task<Void, Never> }
    private var tails: [String: Turn] = [:]

    func perform<T: Sendable>(key: String, queued: @Sendable () -> Void,
        operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tails[key]?.completion
        let id = UUID()
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tails[key] = Turn(id: id, completion: Task { _ = try? await task.value })
        queued()
        defer { if tails[key]?.id == id { tails.removeValue(forKey: key) } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
