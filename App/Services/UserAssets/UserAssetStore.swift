import Darwin
import Foundation

/// Content a `file` or `directory` wallpaper property accepts.
enum UserAssetFilter: String, Sendable, CaseIterable {
    case image
    case video
    /// The author declared no file-type option. Everything either list allows is
    /// accepted; screening still happens, so a document or executable is refused.
    case any

    /// Lower-cased extensions, matching the sets the official property editor offers.
    var allowedExtensions: Set<String> {
        switch self {
        case .image:
            return Self.imageExtensions
        case .video:
            return Self.videoExtensions
        case .any:
            return Self.imageExtensions.union(Self.videoExtensions)
        }
    }

    private static let imageExtensions: Set<String> = ["jpeg", "jpg", "png", "pnga", "bmp", "gif", "svg", "webp"]
    private static let videoExtensions: Set<String> = ["webm", "ogg", "ogv"]
}

/// One staged asset: where it lives, and the value the page turns into a `file:///` URL.
struct UserAssetImport: Sendable, Equatable {
    var stagedPath: String
    var pageValue: String

    init(stagedPath: String, pageValue: String) {
        self.stagedPath = stagedPath
        self.pageValue = pageValue
    }

    init(stagedPath: String) {
        self.stagedPath = stagedPath
        self.pageValue = Self.pageValue(forPath: stagedPath)
    }

    /// Wallpaper pages build `'file:///' + value`, so an absolute POSIX path arrives
    /// without its leading separator. Only the three characters that would otherwise
    /// terminate or re-scope the URL are escaped: a page that treats the value as a
    /// plain path still receives the literal spaces, `+`, `&` and non-ASCII it expects.
    static func pageValue(forPath path: String) -> String {
        var value = path
        if value.hasPrefix("/") { value.removeFirst() }
        return value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "#", with: "%23")
            .replacingOccurrences(of: "?", with: "%3F")
    }
}

/// Why an import could not be staged. The reason is user-readable and always surfaced.
struct UserAssetError: LocalizedError, Equatable {
    enum Code: String, Sendable {
        case projectMissing
        case projectNotWritable
        case invalidPropertyID
        case invalidWallpaperID
        case sourceUnreadable
        case sourceInsideStaging
        case sourceNotAFile
        case sourceNotADirectory
        case unsupportedType
        case stagingFailed
        case manifestUnreadable
    }

    let code: Code
    let reason: String

    var errorDescription: String? { reason }
}

/// Puts a `file` or `directory` property's imported assets where a wallpaper page can
/// read them. Two locations are involved, and the difference between them is the whole
/// point of this type.
///
/// * The **managed store** — `ManagedUserAssetStore`, under application support — is
///   canonical. It holds the app's own copy of the user's file, keyed by the stable
///   wallpaper id, and it survives deleting the project, re-downloading it from the
///   Workshop, and every pass of `scripts/clean.py` that does not name it explicitly.
/// * The **bridge** — `<project>/.mwe-user-assets/<propertyId>/` — is derived and
///   regenerable. It exists only because WebKit's `loadFileURL(_:allowingReadAccessTo:)`
///   grants a page read access strictly below a root that is an ancestor of the entry
///   file. A page therefore cannot read the managed store at all; a symlink out of the
///   project is resolved and refused; and widening the read root would hand every
///   wallpaper the whole application-support tree. Entries are hard links onto the
///   store's files, and byte copies when the project sits on another volume. Deleting
///   the entire bridge loses nothing: the next import rebuilds it from the manifest.
///
/// Data flows store → bridge only. The one exception is the one-shot migration of a
/// round-6 staging directory, which runs only when the property's original source no
/// longer resolves and the store has never seen the property. The user's original is
/// never moved, renamed or written to, and no authored wallpaper file is touched.
@MainActor final class UserAssetStore {
    typealias WatcherFactory = @MainActor (URL, @escaping @MainActor () -> Void) -> DirectoryWatching
    nonisolated static let defaultDirectoryFileLimit = 4096
    nonisolated static let stagingDirectoryName = ".mwe-user-assets"
    nonisolated static let ownerMarkerName = ".managed-by"
    nonisolated static func stagingRoot(projectURL: URL) -> URL {
        projectURL.standardizedFileURL.appendingPathComponent(stagingDirectoryName, isDirectory: true)
    }

    var onDirectoryChanged: ((String, [UserAssetImport], [UserAssetImport]) -> Void)?
    private let worker: UserAssetWorker
    private let makeWatcher: WatcherFactory
    private var snapshots: [String: UserAssetPropertySnapshot] = [:]
    private var watchers: [String: DirectoryWatching] = [:]
    private var requests: [String: (id: UUID, task: Task<UserAssetPropertySnapshot, Error>)] = [:]
    private var refreshes: [String: Task<Void, Never>] = [:]
    private var refreshAgain = Set<String>()

    init(projectURL: URL, wallpaperId: String,
         managed: ManagedUserAssetStore = ManagedUserAssetStore(), fileManager: FileManager = .default,
         watcherFactory: @escaping WatcherFactory = { DirectoryWatcher(url: $0, onChange: $1) },
         beforePreparation: @escaping @Sendable () throws -> Void = {}) {
        worker = UserAssetWorker(projectURL: projectURL, wallpaperId: wallpaperId,
            managed: managed, fileManager: fileManager, beforePreparation: beforePreparation)
        makeWatcher = watcherFactory
    }

    deinit {
        for watcher in watchers.values { watcher.stop() }
        for request in requests.values { request.task.cancel() }
        for refresh in refreshes.values { refresh.cancel() }
    }

    @discardableResult
    func importFile(at url: URL, propertyId: String, filter: UserAssetFilter) async throws -> UserAssetImport {
        let snapshot = try await prepare(propertyId: propertyId) { [worker] in
            try await worker.file(at: url, propertyId: propertyId, filter: filter)
        }
        guard let file = snapshot.files.first else { throw CancellationError() }
        return file
    }

    @discardableResult
    func importDirectory(at url: URL, propertyId: String, filter: UserAssetFilter, limit: Int) async throws -> [UserAssetImport] {
        try await prepare(propertyId: propertyId) { [worker] in
            try await worker.directory(at: url, propertyId: propertyId, filter: filter, limit: limit)
        }.files
    }

    private func prepare(propertyId: String,
                         operation: @escaping @Sendable () async throws -> UserAssetPropertySnapshot) async throws -> UserAssetPropertySnapshot {
        requests[propertyId]?.task.cancel()
        refreshes.removeValue(forKey: propertyId)?.cancel()
        refreshAgain.remove(propertyId)
        let id = UUID()
        let task = Task { try await operation() }
        requests[propertyId] = (id, task)
        defer { if requests[propertyId]?.id == id { requests.removeValue(forKey: propertyId) } }
        let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard requests[propertyId]?.id == id else { throw CancellationError() }
        watchers.removeValue(forKey: propertyId)?.stop()
        snapshots[propertyId] = value
        if let directory = value.sourceDirectory {
            watchers[propertyId] = makeWatcher(directory) { [weak self] in
                self?.directoryDidChange(propertyId: propertyId, generation: value.generation)
            }
        }
        return value
    }

    func randomFile(propertyId: String) -> UserAssetImport? { snapshots[propertyId]?.files.randomElement() }
    func stagedFiles(propertyId: String) -> [UserAssetImport] { snapshots[propertyId]?.files ?? [] }
    func isTruncated(propertyId: String) -> Bool { snapshots[propertyId]?.truncated ?? false }
    func isManaged(propertyId: String) -> Bool { !(snapshots[propertyId]?.files.isEmpty ?? true) }
    func isSourceMissing(propertyId: String) -> Bool { snapshots[propertyId]?.sourceMissing ?? false }

    func cancelImport(propertyId: String) {
        requests.removeValue(forKey: propertyId)?.task.cancel()
        refreshes.removeValue(forKey: propertyId)?.cancel()
        refreshAgain.remove(propertyId)
    }

    func cancelImports() {
        for propertyId in Set(requests.keys).union(refreshes.keys) { cancelImport(propertyId: propertyId) }
        for watcher in watchers.values { watcher.stop() }
        watchers.removeAll()
    }

    func clear(propertyId: String) async throws {
        _ = try await prepare(propertyId: propertyId) { [worker] in
            try await worker.clear(propertyId: propertyId)
            return .init()
        }
        snapshots.removeValue(forKey: propertyId)
    }

    func clearAll() async {
        for request in requests.values { request.task.cancel() }
        requests.removeAll()
        for refresh in refreshes.values { refresh.cancel() }
        refreshes.removeAll()
        refreshAgain.removeAll()
        for watcher in watchers.values { watcher.stop() }
        watchers.removeAll()
        snapshots.removeAll()
        await worker.clearAll()
    }

    private func directoryDidChange(propertyId: String, generation: UUID) {
        guard requests[propertyId] == nil, snapshots[propertyId]?.generation == generation else { return }
        guard refreshes[propertyId] == nil else { refreshAgain.insert(propertyId); return }
        refreshes[propertyId] = Task { @MainActor [weak self, worker] in
            let value = await worker.refresh(propertyId: propertyId, generation: generation)
            guard let self, !Task.isCancelled, self.requests[propertyId] == nil,
                  self.snapshots[propertyId]?.generation == generation else { return }
            let before = self.snapshots[propertyId]?.files ?? []
            let previousDigests = self.snapshots[propertyId]?.digests ?? [:]
            self.snapshots[propertyId] = value
            if value.sourceDirectory == nil { self.watchers.removeValue(forKey: propertyId)?.stop() }
            self.refreshes.removeValue(forKey: propertyId)
            let added = value.files.filter { !before.contains($0) || previousDigests[$0.stagedPath] != value.digests[$0.stagedPath] }
            let removed = before.filter { !value.files.contains($0) }
            if !added.isEmpty || !removed.isEmpty { self.onDirectoryChanged?(propertyId, added, removed) }
            if self.refreshAgain.remove(propertyId) != nil {
                self.directoryDidChange(propertyId: propertyId, generation: generation)
            }
        }
    }

    /// Waits for a delivered watcher event to settle; also used during orderly teardown.
    func waitForPendingChanges() async {
        while let refresh = refreshes.values.first { await refresh.value }
    }
}

struct UserAssetPropertySnapshot: Sendable {
    var generation = UUID()
    var files: [UserAssetImport] = []
    var sourceDirectory: URL?
    var truncated = false
    var sourceMissing = false
    var digests: [String: String] = [:]
}
