import Darwin
import Foundation

/// Serial filesystem work for one wallpaper, outside the UI executor.
actor UserAssetWorker {
    /// Upper bound callers should pass to `importDirectory`. Large enough for a real
    /// wallpaper slideshow folder, small enough that a mistaken pick at `/` cannot
    /// stage an unbounded number of links.
    static let defaultDirectoryFileLimit = 4096

    static let stagingDirectoryName = ".mwe-user-assets"

    /// Names the wallpaper a bridge was written for, so a different wallpaper cannot
    /// mistake it for a round-6 staging directory to absorb. Hidden, so the directory
    /// scans that list staged files never see it.
    static let ownerMarkerName = ".managed-by"

    /// The derived, regenerable bridge directory inside the project.
    static func stagingRoot(projectURL: URL) -> URL {
        projectURL.standardizedFileURL.appendingPathComponent(stagingDirectoryName, isDirectory: true)
    }

    private let projectURL: URL
    private let wallpaperId: String
    private let managed: ManagedUserAssetStore
    private let fileManager: FileManager
    private let beforePreparation: @Sendable () throws -> Void
    private var properties: [String: PropertyState] = [:]

    init(
        projectURL: URL,
        wallpaperId: String,
        managed: ManagedUserAssetStore = ManagedUserAssetStore(),
        fileManager: FileManager = .default,
        beforePreparation: @escaping @Sendable () throws -> Void = {}
    ) {
        self.projectURL = projectURL
        self.wallpaperId = wallpaperId
        self.managed = managed
        self.fileManager = fileManager
        self.beforePreparation = beforePreparation
    }


    func file(at url: URL, propertyId: String, filter: UserAssetFilter) async throws -> UserAssetPropertySnapshot {
        try await managed.withPreparation(wallpaperId: wallpaperId) { [self] in
            try await prepareFile(at: url, propertyId: propertyId, filter: filter)
        }
    }

    private func prepareFile(at url: URL, propertyId: String, filter: UserAssetFilter) throws -> UserAssetPropertySnapshot {
        try beforePreparation()
        _ = try importFile(at: url, propertyId: propertyId, filter: filter)
        return snapshot(propertyId)
    }

    func directory(at url: URL, propertyId: String, filter: UserAssetFilter, limit: Int) async throws -> UserAssetPropertySnapshot {
        try await managed.withPreparation(wallpaperId: wallpaperId) { [self] in
            try await prepareDirectory(at: url, propertyId: propertyId, filter: filter, limit: limit)
        }
    }

    private func prepareDirectory(at url: URL, propertyId: String, filter: UserAssetFilter, limit: Int) throws -> UserAssetPropertySnapshot {
        try beforePreparation()
        _ = try importDirectory(at: url, propertyId: propertyId, filter: filter, limit: limit)
        return snapshot(propertyId)
    }

    func refresh(propertyId: String, generation: UUID) async -> UserAssetPropertySnapshot {
        do {
            return try await managed.withPreparation(wallpaperId: wallpaperId) { [self] in
                await refreshPrepared(propertyId: propertyId, generation: generation)
            }
        } catch { return snapshot(propertyId) }
    }

    private func refreshPrepared(propertyId: String, generation: UUID) -> UserAssetPropertySnapshot {
        directoryDidChange(propertyId: propertyId, generation: generation)
        return snapshot(propertyId)
    }

    private func snapshot(_ propertyId: String) -> UserAssetPropertySnapshot {
        guard let state = properties[propertyId] else { return .init() }
        return .init(generation: state.generation, files: orderedAssets(state),
            sourceDirectory: state.sourceDirectory, truncated: state.truncated,
            sourceMissing: state.sourceMissing,
            digests: Dictionary(uniqueKeysWithValues: state.entries.values.map { ($0.asset.stagedPath, $0.managed.digest) }))
    }

    // MARK: - Import

    /// Imports a single file: into the store first, then onto the bridge.
    ///
    /// When the user's own file no longer resolves but the store still holds the
    /// property's asset, the asset stays usable and the property reports a missing
    /// source rather than being silently cleared.
    @discardableResult
    private func importFile(at url: URL, propertyId: String, filter: UserAssetFilter) throws -> UserAssetImport {
        _ = try bridgeDirectoryURL(propertyId)
        try Task.checkCancellation()
        var manifest = try managed.manifest(wallpaperId: wallpaperId)
        let record = manifest.properties[propertyId]
        if record?.originalSourceUnauthorized == true || (record?.authorizedSourcePath != nil && record?.authorizedSourcePath != url.standardizedFileURL.path) {
            let restored = try restoreFromStore(
                propertyId: propertyId, declaredSource: url.path, kind: .file,
                filter: filter, limit: 1, manifest: &manifest)
            guard let first = restored.first else {
                throw UserAssetError(code: .sourceUnreadable, reason: String(localized: "The retained resource is unavailable. Select the original resource again."))
            }
            return first
        }
        let source: URL
        do {
            source = try canonicalSource(url)
            guard try !isDirectory(source) else {
                throw UserAssetError(code: .sourceNotAFile, reason: String(
                    localized: "Choose a file, not a folder."))
            }
        } catch let error as UserAssetError where error.code == .sourceUnreadable {
            let restored = try restoreFromStore(
                propertyId: propertyId, declaredSource: url.path, kind: .file,
                filter: filter, limit: 1, manifest: &manifest)
            guard let first = restored.first else { throw error }
            return first
        }
        guard filter.allowedExtensions.contains(source.pathExtension.lowercased()) else {
            throw UserAssetError(code: .unsupportedType, reason: unsupportedReason(filter))
        }
        try requireWritableProject()

        let name = source.lastPathComponent
        let previous = manifest.properties[propertyId]
        // Store first, reference second: a crash between the two leaves an unreferenced
        // copy, which purging reclaims, rather than a reference to nothing.
        let asset = try managed.adopt(
            readingFrom: source, fileName: name, sourcePath: source.path,
            wallpaperId: wallpaperId, propertyId: propertyId,
            known: previous?.assets.first { $0.fileName == name })
        manifest.properties[propertyId] = ManagedUserAssetProperty(
            kind: .file, sourcePath: source.path, assets: [asset],
            migratedLegacyPaths: previous?.migratedLegacyPaths ?? [])
        manifest.properties[propertyId]?.authorizedSourcePath = previous?.authorizedSourcePath
        try Task.checkCancellation()
        try managed.updateProperty(wallpaperId: wallpaperId, propertyId: propertyId,
            expected: previous, replacement: manifest.properties[propertyId])
        managed.pruneUnlisted(wallpaperId: wallpaperId, propertyId: propertyId)

        let staged = try publishBridge(propertyId: propertyId, assets: [asset])
        guard let entry = staged[name] else {
            throw UserAssetError(code: .stagingFailed, reason: String(
                localized: "\(name) could not be prepared for this wallpaper."))
        }
        var state = PropertyState(filter: filter, limit: 1)
        state.entries[name] = entry
        properties[propertyId] = state
        return entry.asset
    }

    /// Imports up to `limit` matching files from the first level of `url` and watches it
    /// for changes. Returns the imported assets ordered by file name.
    @discardableResult
    private func importDirectory(
        at url: URL, propertyId: String, filter: UserAssetFilter, limit: Int
    ) throws -> [UserAssetImport] {
        _ = try bridgeDirectoryURL(propertyId)
        try Task.checkCancellation()
        var manifest = try managed.manifest(wallpaperId: wallpaperId)
        let record = manifest.properties[propertyId]
        if record?.originalSourceUnauthorized == true || (record?.authorizedSourcePath != nil && record?.authorizedSourcePath != url.standardizedFileURL.path) {
            let restored = try restoreFromStore(
                propertyId: propertyId, declaredSource: url.path, kind: .directory,
                filter: filter, limit: limit, manifest: &manifest)
            guard !restored.isEmpty else {
                throw UserAssetError(code: .sourceUnreadable, reason: String(localized: "The retained resource is unavailable. Select the original resource again."))
            }
            return restored
        }
        let source: URL
        do {
            source = try canonicalSource(url)
            guard try isDirectory(source) else {
                throw UserAssetError(code: .sourceNotADirectory, reason: String(
                    localized: "Choose a folder, not a file."))
            }
        } catch let error as UserAssetError where error.code == .sourceUnreadable {
            let restored = try restoreFromStore(
                propertyId: propertyId, declaredSource: url.path, kind: .directory,
                filter: filter, limit: limit, manifest: &manifest)
            guard !restored.isEmpty else { throw error }
            return restored
        }
        try requireWritableProject()

        let previous = manifest.properties[propertyId]
        let scan = try scanSource(source, filter: filter, limit: limit)
        var assets: [ManagedUserAsset] = []
        for candidate in scan.files {
            try Task.checkCancellation()
            do {
                assets.append(try managed.adopt(
                    readingFrom: candidate.url, fileName: candidate.name, sourcePath: candidate.url.path,
                    wallpaperId: wallpaperId, propertyId: propertyId,
                    known: previous?.assets.first { $0.fileName == candidate.name }))
            } catch {
                // One unreadable entry must not cost the user the rest of the folder.
                AppLog.warn("user assets \(propertyId): skipped \(candidate.name): \(error.localizedDescription)")
                if let known = previous?.assets.first(where: { $0.fileName == candidate.name }) {
                    assets.append(known)
                }
            }
        }
        manifest.properties[propertyId] = ManagedUserAssetProperty(
            kind: .directory, sourcePath: source.path, assets: assets, truncated: scan.truncated,
            migratedLegacyPaths: previous?.migratedLegacyPaths ?? [])
        manifest.properties[propertyId]?.authorizedSourcePath = previous?.authorizedSourcePath
        try Task.checkCancellation()
        try managed.updateProperty(wallpaperId: wallpaperId, propertyId: propertyId,
            expected: previous, replacement: manifest.properties[propertyId])
        managed.pruneUnlisted(wallpaperId: wallpaperId, propertyId: propertyId)

        if scan.truncated {
            AppLog.warn("user assets \(propertyId): folder exceeds \(limit) files; staged the first \(assets.count)")
        }
        var state = PropertyState(filter: filter, limit: limit)
        state.sourceDirectory = source
        state.truncated = scan.truncated
        state.entries = try publishBridge(propertyId: propertyId, assets: assets)
        properties[propertyId] = state
        return orderedAssets(state)
    }

    // MARK: - Query

    /// A uniformly chosen staged file, or nil when nothing is staged for the property.
    /// Reads the in-memory index; it never walks the source folder.
    func randomFile(propertyId: String) -> UserAssetImport? {
        properties[propertyId]?.entries.values.randomElement()?.asset
    }

    /// Staged assets for a property, ordered by file name.
    func stagedFiles(propertyId: String) -> [UserAssetImport] {
        guard let state = properties[propertyId] else { return [] }
        return orderedAssets(state)
    }

    /// True when the property's source folder held more matching files than the limit
    /// allowed, so only a prefix of it is staged.
    func isTruncated(propertyId: String) -> Bool {
        properties[propertyId]?.truncated ?? false
    }

    /// True when the app owns a copy of this property's assets in managed storage.
    func isManaged(propertyId: String) -> Bool {
        !((try? managed.manifest(wallpaperId: wallpaperId))?.properties[propertyId]?.assets.isEmpty ?? true)
    }

    /// True when the user's own file or folder no longer resolves and the property is
    /// being served from the store alone.
    func isSourceMissing(propertyId: String) -> Bool {
        properties[propertyId]?.sourceMissing ?? false
    }

    // MARK: - Removal

    /// Forgets a property entirely: the user cleared it, so the app stops holding a copy.
    func clear(propertyId: String) async throws {
        try await managed.withPreparation(wallpaperId: wallpaperId) { [self] in
            try await clearPrepared(propertyId: propertyId)
        }
    }

    private func clearPrepared(propertyId: String) throws {
        try Task.checkCancellation()
        var manifest = try managed.manifest(wallpaperId: wallpaperId)
        if let previous = manifest.properties.removeValue(forKey: propertyId) {
            try managed.updateProperty(wallpaperId: wallpaperId, propertyId: propertyId,
                expected: previous, replacement: nil)
        }
        properties.removeValue(forKey: propertyId)
        managed.removeProperty(wallpaperId: wallpaperId, propertyId: propertyId)
        guard let directory = try? bridgeDirectoryURL(propertyId) else { return }
        try? fileManager.removeItem(at: directory)
    }

    /// Drops the whole derived bridge for this project. The store is untouched, so the
    /// next import rebuilds every file this removes.
    func clearAll() async {
        try? await managed.withPreparation(wallpaperId: wallpaperId) { [self] in
            await clearAllPrepared()
        }
    }

    private func clearAllPrepared() {
        properties.removeAll()
        try? fileManager.removeItem(at: Self.stagingRoot(projectURL: projectURL))
    }

    // MARK: - Directory changes

    func directoryDidChange(propertyId: String, generation: UUID) {
        guard var state = properties[propertyId], state.generation == generation,
              let source = state.sourceDirectory else { return }
        do {
            try synchronizeDirectory(propertyId: propertyId, state: &state, source: source)
        } catch {
            // A failed scan or commit cannot authorize deletion. Keep serving the
            // last committed entries and let a later notification retry.
            state.sourceMissing = !fileManager.isReadableFile(atPath: source.path)
            properties[propertyId] = state
            AppLog.warn("user assets \(propertyId): keeping retained files: \(error.localizedDescription)")
        }
    }

    private func synchronizeDirectory(propertyId: String, state: inout PropertyState, source: URL) throws {
        try Task.checkCancellation()
        var manifest = try managed.manifest(wallpaperId: wallpaperId)
        let previous = manifest.properties[propertyId]
        guard var record = previous, record.kind == .directory,
              record.sourcePath == source.path else {
            state.sourceDirectory = nil
            properties[propertyId] = state
            return
        }
        guard record.originalSourceUnauthorized != true,
              record.authorizedSourcePath == nil || URL(fileURLWithPath: record.authorizedSourcePath!).resolvingSymlinksInPath().path == source.path else {
            state.sourceDirectory = nil
            properties[propertyId] = state
            return
        }
        let scan = try scanSource(source, filter: state.filter, limit: state.limit)
        if scan.truncated != state.truncated {
            AppLog.warn("user assets \(propertyId): folder \(scan.truncated ? "now exceeds" : "no longer exceeds") \(state.limit) files")
        }
        state.truncated = scan.truncated

        var assets: [ManagedUserAsset] = []
        var rewritten = Set<String>()
        for candidate in scan.files {
            try Task.checkCancellation()
            let known = record.assets.first { $0.fileName == candidate.name }
            do {
                let asset = try managed.adopt(
                    readingFrom: candidate.url, fileName: candidate.name, sourcePath: candidate.url.path,
                    wallpaperId: wallpaperId, propertyId: propertyId, known: known)
                if asset != known { rewritten.insert(candidate.name) }
                assets.append(asset)
            } catch {
                AppLog.warn("user assets \(propertyId): skipped \(candidate.name): \(error.localizedDescription)")
                if let known { assets.append(known) }
            }
        }
        record.assets = assets
        record.truncated = scan.truncated
        manifest.properties[propertyId] = record
        try Task.checkCancellation()
        try managed.updateProperty(wallpaperId: wallpaperId, propertyId: propertyId,
            expected: previous, replacement: record)
        managed.pruneUnlisted(wallpaperId: wallpaperId, propertyId: propertyId)
        state.sourceMissing = false

        let surviving = Set(assets.map(\.fileName))
        var removed: [UserAssetImport] = []
        for (name, entry) in state.entries where !surviving.contains(name) {
            try? fileManager.removeItem(atPath: entry.asset.stagedPath)
            state.entries[name] = nil
            removed.append(entry.asset)
        }
        var added: [UserAssetImport] = []
        let republished = (try? publishBridge(
            propertyId: propertyId, assets: assets, rewriting: rewritten)) ?? [:]
        for (name, entry) in republished {
            let isNew = state.entries[name] == nil
            state.entries[name] = entry
            if isNew { added.append(entry.asset) }
        }

        properties[propertyId] = state

    }

    // MARK: - Store to bridge

    /// Restores a property from managed storage when the user's own file or folder can no
    /// longer be resolved, migrating a round-6 staging directory into the store first if
    /// this property has never been recorded there.
    ///
    /// Returns an empty array when nothing is recoverable, which the caller turns back
    /// into the original "cannot be read" error.
    private func restoreFromStore(
        propertyId: String, declaredSource: String, kind: ManagedUserAssetProperty.Kind,
        filter: UserAssetFilter, limit: Int, manifest: inout UserAssetManifest
    ) throws -> [UserAssetImport] {
        if manifest.properties[propertyId] == nil {
            migrateLegacyBridge(
                propertyId: propertyId, declaredSource: declaredSource, kind: kind,
                filter: filter, limit: limit, manifest: &manifest)
        }
        guard let record = manifest.properties[propertyId], !record.assets.isEmpty else { return [] }
        guard record.kind == kind else { return [] }
        let present = record.assets.filter { asset in
            guard let url = try? managed.storedURL(
                wallpaperId: wallpaperId, propertyId: propertyId, asset: asset) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
        guard !present.isEmpty else { return [] }
        AppLog.warn("user assets \(propertyId): serving \(present.count) file(s) from managed storage without accessing the original")

        var state = PropertyState(filter: filter, limit: limit)
        state.truncated = record.truncated
        state.sourceMissing = true
        state.entries = try publishBridge(propertyId: propertyId, assets: present, pruning: false)
        properties[propertyId] = state
        return orderedAssets(state)
    }

    /// One-shot, non-destructive absorption of a round-6 `.mwe-user-assets` directory.
    ///
    /// The staged files are hard links onto the user's original, so reading them here
    /// reads the user's own bytes. Nothing in the old location is deleted, and the
    /// manifest is written before anything else changes: if the copy or the write fails
    /// the old staged entry is still exactly where it was and still loads.
    ///
    /// Refused when the bridge already belongs to a different wallpaper. A round-6
    /// bridge carries no owner marker and is therefore migratable by the wallpaper whose
    /// project it sits in; a bridge this build wrote names its owner, and a wallpaper id
    /// that does not match must not adopt another wallpaper's files.
    private func migrateLegacyBridge(
        propertyId: String, declaredSource: String, kind: ManagedUserAssetProperty.Kind,
        filter: UserAssetFilter, limit: Int, manifest: inout UserAssetManifest
    ) {
        if let owner = bridgeOwner(), owner != wallpaperId { return }
        guard let directory = try? bridgeDirectoryURL(propertyId),
              let contents = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]),
              !contents.isEmpty else { return }
        let declaredName = URL(fileURLWithPath: declaredSource).lastPathComponent
        let allowed = filter.allowedExtensions
        var assets: [ManagedUserAsset] = []
        for entry in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            guard allowed.contains(entry.pathExtension.lowercased()),
                  (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            if kind == .file, name != declaredName { continue }
            guard assets.count < max(0, limit) else { break }
            // A directory member's original sat inside the folder the user picked.
            let recorded = kind == .file
                ? declaredSource
                : URL(fileURLWithPath: declaredSource, isDirectory: true)
                    .appendingPathComponent(name).path
            do {
                assets.append(try managed.adopt(
                    readingFrom: entry, fileName: name, sourcePath: recorded,
                    wallpaperId: wallpaperId, propertyId: propertyId, known: nil))
            } catch {
                AppLog.warn("user assets \(propertyId): could not migrate \(name): \(error.localizedDescription)")
            }
        }
        guard !assets.isEmpty else { return }
        manifest.properties[propertyId] = ManagedUserAssetProperty(
            kind: kind, sourcePath: declaredSource, assets: assets,
            migratedLegacyPaths: [directory.path])
        do {
            try Task.checkCancellation()
            try managed.updateProperty(wallpaperId: wallpaperId, propertyId: propertyId,
                expected: nil, replacement: manifest.properties[propertyId])
            AppLog.warn("user assets \(propertyId): migrated \(assets.count) file(s) from \(directory.path) into managed storage")
        } catch {
            // References are unchanged, so the old location still serves the page.
            manifest.properties[propertyId] = nil
            AppLog.error("user assets \(propertyId): migration could not be recorded: \(error.localizedDescription)")
        }
    }

    /// Reconciles the bridge directory against `assets`. Only missing, stale or
    /// explicitly named entries are re-linked, so a reconcile that changed nothing
    /// copies nothing — which matters on the cross-volume path, where a bridge entry
    /// is a real byte copy rather than a link.
    @discardableResult
    private func publishBridge(
        propertyId: String, assets: [ManagedUserAsset], rewriting: Set<String> = [],
        pruning: Bool = true
    ) throws -> [String: StagedEntry] {
        let directory = try bridgeDirectoryURL(propertyId)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw UserAssetError(code: .projectNotWritable, reason: notWritableReason(error))
        }
        markBridgeOwner()
        var published: [String: StagedEntry] = [:]
        for asset in assets {
            try Task.checkCancellation()
            let stored = try managed.storedURL(
                wallpaperId: wallpaperId, propertyId: propertyId, asset: asset)
            guard fileManager.fileExists(atPath: stored.path) else {
                AppLog.warn("user assets \(propertyId): \(asset.fileName) is recorded but missing from managed storage")
                continue
            }
            let destination = directory.appendingPathComponent(asset.fileName)
            if rewriting.contains(asset.fileName) || !bridgeEntryMatches(destination, stored: stored) {
                do {
                    try link(stored, to: destination)
                } catch {
                    AppLog.warn("user assets \(propertyId): \(asset.fileName) could not be linked into the project: \(error.localizedDescription)")
                    continue
                }
            }
            published[asset.fileName] = StagedEntry(
                asset: UserAssetImport(stagedPath: destination.path), managed: asset)
        }
        // A pick the property has replaced must stop being readable from the project,
        // even though the bridge is otherwise left alone between reconciles. Skipped
        // while restoring from the store, where an entry this run could not adopt is
        // still the user's only copy.
        guard pruning else { return published }
        let live = Set(assets.map(\.fileName))
        for entry in (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [])) ?? []
        where !live.contains(entry.lastPathComponent) {
            try? fileManager.removeItem(at: entry)
        }
        return published
    }

    /// Which wallpaper this project's bridge was last written for, or nil when the
    /// bridge predates the marker — which is exactly the round-6 case migration exists
    /// to handle.
    private func bridgeOwner() -> String? {
        let marker = Self.stagingRoot(projectURL: projectURL)
            .appendingPathComponent(Self.ownerMarkerName)
        guard let data = try? Data(contentsOf: marker),
              let owner = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !owner.isEmpty else { return nil }
        return owner
    }

    private func markBridgeOwner() {
        guard bridgeOwner() != wallpaperId else { return }
        let marker = Self.stagingRoot(projectURL: projectURL)
            .appendingPathComponent(Self.ownerMarkerName)
        try? Data(wallpaperId.utf8).write(to: marker, options: .atomic)
    }

    /// A bridge entry is current when it is the same size and modification time as the
    /// stored file it derives from. A hard link is trivially both; a cross-volume copy
    /// preserves both, so an unchanged asset is never copied twice.
    private func bridgeEntryMatches(_ destination: URL, stored: URL) -> Bool {
        guard let values = try? destination.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let original = try? stored.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return false }
        return values.fileSize == original.fileSize && values.contentModificationDate == original.contentModificationDate
    }

    private func link(_ source: URL, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".asset-\(UUID().uuidString)")
        defer { unlink(temporary.path) }
        // Prepare the replacement without unpublishing the current file. WebKit
        // needs a real project-local file, not a symlink outside its read root.
        if Darwin.link(source.path, temporary.path) != 0 {
            let code = errno
            guard code == EXDEV else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
            // Only a cross-volume project needs a byte copy instead of a hard link.
            try fileManager.copyItem(at: source, to: temporary)
        }
        guard rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    // MARK: - Bridge paths

    private func bridgeDirectoryURL(_ propertyId: String) throws -> URL {
        guard !propertyId.isEmpty, propertyId != ".", propertyId != "..",
              !propertyId.contains("/"), !propertyId.contains(":"), !propertyId.contains("\0") else {
            throw UserAssetError(code: .invalidPropertyID, reason: String(
                localized: "This wallpaper property has a name that cannot be used as a folder."))
        }
        return Self.stagingRoot(projectURL: projectURL)
            .appendingPathComponent(propertyId, isDirectory: true)
    }

    private func requireWritableProject() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UserAssetError(code: .projectMissing, reason: String(
                localized: "The wallpaper folder is missing, so the chosen file cannot be prepared."))
        }
        let root = Self.stagingRoot(projectURL: projectURL)
        let parent = fileManager.fileExists(atPath: root.path) ? root : projectURL
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw UserAssetError(code: .projectNotWritable, reason: notWritableReason(nil))
        }
    }

    // MARK: - Source inspection

    private func canonicalSource(_ url: URL) throws -> URL {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let staging = Self.stagingRoot(projectURL: projectURL).resolvingSymlinksInPath().standardizedFileURL
        guard !Self.isWithin(resolved, staging), resolved != staging else {
            throw UserAssetError(code: .sourceInsideStaging, reason: String(
                localized: "Choose a file outside the wallpaper’s own prepared assets."))
        }
        guard fileManager.isReadableFile(atPath: resolved.path) else {
            throw UserAssetError(code: .sourceUnreadable, reason: String(
                localized: "\(url.lastPathComponent) cannot be read."))
        }
        return resolved
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        var flag: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &flag) else {
            throw UserAssetError(code: .sourceUnreadable, reason: String(
                localized: "\(url.lastPathComponent) cannot be read."))
        }
        return flag.boolValue
    }

    /// One level of `directory`, filtered and capped. Only metadata is read; file contents
    /// are never loaded, however many entries the folder holds.
    private func scanSource(
        _ directory: URL, filter: UserAssetFilter, limit: Int
    ) throws -> (files: [Candidate], truncated: Bool) {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let contents = try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        let allowed = filter.allowedExtensions
        var candidates: [Candidate] = []
        var truncated = false
        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            let name = url.lastPathComponent
            guard allowed.contains(url.pathExtension.lowercased()) else { continue }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            guard fileManager.isReadableFile(atPath: url.path) else {
                throw UserAssetError(code: .sourceUnreadable, reason: String(localized: "\(name) cannot be read."))
            }
            guard candidates.count < max(0, limit) else {
                truncated = true
                break
            }
            candidates.append(Candidate(url: url, name: name))
        }
        return (candidates, truncated)
    }

    private func orderedAssets(_ state: PropertyState) -> [UserAssetImport] {
        state.entries.keys.sorted().compactMap { state.entries[$0]?.asset }
    }

    private func unsupportedReason(_ filter: UserAssetFilter) -> String {
        let extensions = filter.allowedExtensions.sorted().joined(separator: ", ")
        switch filter {
        case .image:
            return String(localized: "This wallpaper property takes an image: \(extensions).")
        case .video:
            return String(localized: "This wallpaper property takes a video: \(extensions).")
        case .any:
            return String(localized: "This wallpaper property takes one of: \(extensions).")
        }
    }

    private func notWritableReason(_ error: Error?) -> String {
        if let error {
            return String(localized: "The wallpaper folder cannot be written to: \(error.localizedDescription)")
        }
        return String(localized: "The wallpaper folder is read-only, so the chosen file cannot be prepared.")
    }

    private static func isWithin(_ url: URL, _ root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let components = url.pathComponents
        guard components.count > rootComponents.count else { return false }
        return Array(components.prefix(rootComponents.count)) == rootComponents
    }

    // MARK: - State

    private struct Candidate {
        var url: URL
        var name: String
    }

    private struct StagedEntry {
        var asset: UserAssetImport
        var managed: ManagedUserAsset
    }

    private struct PropertyState {
        let generation = UUID()
        var filter: UserAssetFilter
        var limit: Int
        var sourceDirectory: URL?
        var entries: [String: StagedEntry] = [:]
        var truncated = false
        /// The user's own file or folder could not be resolved; the store is serving it.
        var sourceMissing = false
    }
}
