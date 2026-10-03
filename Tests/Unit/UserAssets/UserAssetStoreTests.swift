import Darwin
import XCTest
@testable import WallpaperMachine

/// Staging for `file` and `directory` wallpaper properties.
///
/// The contract under test is what a wallpaper page and the control panel observe: the
/// bytes reachable through `pageValue`, the entries `randomFile` may return, the folder
/// left on disk, and the error raised when the project cannot be written to.
@MainActor
final class UserAssetStoreTests: XCTestCase {
    private var root: URL!
    private var project: URL!
    private var previousHome: String?

    private var managedRoot: URL { ClientPaths.userAssetsURL }
    private var staging: URL { UserAssetStore.stagingRoot(projectURL: project) }

    override func setUpWithError() throws {
        previousHome = ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_HOME"]
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-assets-tests-\(UUID().uuidString)", isDirectory: true)
        project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        setenv("WALLPAPER_MACHINE_HOME", root.appendingPathComponent("home").path, 1)
    }

    override func tearDownWithError() throws {
        if let previousHome {
            setenv("WALLPAPER_MACHINE_HOME", previousHome, 1)
        } else {
            unsetenv("WALLPAPER_MACHINE_HOME")
        }
        // A read-only project directory would otherwise survive the run.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: project.path)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private func makeStore(
        wallpaperId: String = "2001", watcher: UserAssetStore.WatcherFactory? = nil
    ) -> UserAssetStore {
        UserAssetStore(
            projectURL: project, wallpaperId: wallpaperId,
            watcherFactory: watcher ?? { url, onChange in
                ManualDirectoryWatcher(url: url, trigger: onChange)
            })
    }

    @discardableResult
    private func writeSource(_ name: String, bytes: String = "asset-bytes", in directory: URL? = nil) throws -> URL {
        let parent = directory ?? root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let url = parent.appendingPathComponent(name)
        try Data(bytes.utf8).write(to: url)
        return url
    }

    /// The page does `'file:///' + value`; this is the inverse of that plus the three
    /// escapes the store applies, so a match proves the value names the staged file.
    private func path(fromPageValue value: String) -> String {
        "/" + value
            .replacingOccurrences(of: "%3F", with: "?")
            .replacingOccurrences(of: "%23", with: "#")
            .replacingOccurrences(of: "%25", with: "%")
    }

    private func inode(_ path: String) throws -> UInt64 {
        var status = stat()
        guard stat(path, &status) == 0 else {
            throw XCTSkip("stat failed for \(path)")
        }
        return UInt64(status.st_ino)
    }

    /// Every regular file the managed store holds for a property, ordered by name.
    /// Read straight off disk rather than through the store, so a test cannot pass by
    /// agreeing with the implementation about where the bytes went.
    private func storedFiles(wallpaperId: String, propertyId: String) -> [URL] {
        let directory = managedRoot
            .appendingPathComponent(wallpaperId, isDirectory: true)
            .appendingPathComponent(propertyId, isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func manifest(wallpaperId: String = "2001") throws -> UserAssetManifest {
        try ManagedUserAssetStore().manifest(wallpaperId: wallpaperId)
    }

    private func assertFails(
        _ expected: UserAssetError.Code, _ body: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected.rawValue)", file: file, line: line)
        } catch let error as UserAssetError {
            XCTAssertEqual(error.code, expected, file: file, line: line)
            XCTAssertFalse(
                error.localizedDescription.isEmpty, "the failure must carry a reason",
                file: file, line: line)
        } catch {
            XCTFail("expected UserAssetError, got \(error)", file: file, line: line)
        }
    }

    func testLegacyManifestDecodesWithoutRetainedOnlyState() async throws {
        let source = try writeSource("legacy.png")
        _ = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        let managed = ManagedUserAssetStore()
        var saved = try managed.manifest(wallpaperId: "2001")
        saved.properties["background"]?.originalSourceUnauthorized = true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(saved)) as? [String: Any])
        var properties = try XCTUnwrap(object["properties"] as? [String: [String: Any]])
        properties["background"]?.removeValue(forKey: "originalSourceUnauthorized")
        object["properties"] = properties
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(UserAssetManifest.self, from: JSONSerialization.data(withJSONObject: object))
        try managed.write(legacy)
        try Data("changed legacy bytes".utf8).write(to: source)
        let asset = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: asset.stagedPath)), Data("changed legacy bytes".utf8))
    }

    func testRetainedOnlyDirectoryDoesNotScanOrWatchExistingOriginalUntilReselected() async throws {
        let folder = root.appendingPathComponent("original", isDirectory: true)
        let original = try writeSource("selected #%.png", bytes: "retained", in: folder)
        let importing = makeStore()
        _ = try await importing.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        await importing.clearAll()
        let managed = ManagedUserAssetStore()
        var saved = try managed.manifest(wallpaperId: "2001")
        saved.properties["gallery"]?.originalSourceUnauthorized = true
        try managed.write(saved)
        try Data("changed original".utf8).write(to: original)
        try writeSource("new.png", bytes: "new", in: folder)
        var watches = 0
        var watcher: ManualDirectoryWatcher?
        let store = makeStore(watcher: { url, callback in
            watches += 1
            let made = ManualDirectoryWatcher(url: url, trigger: callback)
            watcher = made
            return made
        })
        let retained = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        XCTAssertEqual(retained.map { URL(fileURLWithPath: $0.stagedPath).lastPathComponent }, ["selected #%.png"])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path(fromPageValue: try XCTUnwrap(retained.first).pageValue))), Data("retained".utf8))
        XCTAssertEqual(watches, 0)
        let replacement = try writeSource("replacement.png", bytes: "new selection")
        try managed.authorizeSelection(wallpaperId: "2001", propertyId: "gallery", selectedSourcePath: replacement.path)
        let stale = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        XCTAssertEqual(stale.map { URL(fileURLWithPath: $0.stagedPath).lastPathComponent }, ["selected #%.png"])
        XCTAssertEqual(watches, 0)
        try managed.authorizeSelection(wallpaperId: "2001", propertyId: "gallery", selectedSourcePath: folder.path)
        let selected = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        XCTAssertEqual(Set(selected.map { URL(fileURLWithPath: $0.stagedPath).lastPathComponent }), ["new.png", "selected #%.png"])
        XCTAssertEqual(watches, 1)
        try writeSource("later.png", in: folder)
        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()
        XCTAssertEqual(storedFiles(wallpaperId: "2001", propertyId: "gallery").map(\.lastPathComponent), ["later.png", "new.png", "selected #%.png"])
        XCTAssertNil(try managed.manifest(wallpaperId: "2001").properties["gallery"]?.originalSourceUnauthorized)
    }

    // MARK: - Single file

    func testImportedFileIsReadableThroughItsPageValueWithoutASecondCopyOfTheBytes() async throws {
        let source = try writeSource("clouds.png", bytes: "original-bytes")
        let store = makeStore()
        let asset = try await store.importFile(at: source, propertyId: "background", filter: .image)

        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: path(fromPageValue: asset.pageValue))),
            Data("original-bytes".utf8))
        XCTAssertTrue(asset.stagedPath.hasPrefix(staging.path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "the user's own file is copied from, never moved")

        // The bridge entry is a hard link onto the app's managed copy, not onto the
        // user's file and not a second set of bytes: importing costs one copy, and the
        // user deleting their original cannot take the staged bytes with it.
        let stored = try XCTUnwrap(storedFiles(wallpaperId: "2001", propertyId: "background").first)
        XCTAssertEqual(try inode(stored.path), try inode(asset.stagedPath))
        XCTAssertNotEqual(try inode(source.path), try inode(stored.path))
        XCTAssertTrue(store.isManaged(propertyId: "background"))
    }

    func testPageValueSurvivesSpacesCJKAndURLPunctuation() async throws {
        let name = "a b#c?d%e 壁纸+x&y'z.png"
        let source = try writeSource(name, bytes: "punctuated")
        let asset = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)

        XCTAssertEqual(path(fromPageValue: asset.pageValue), asset.stagedPath)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: path(fromPageValue: asset.pageValue))),
            Data("punctuated".utf8))
        // Only the three URL-significant characters are escaped: a page that uses the
        // value as a plain path must still see the rest literally.
        XCTAssertTrue(asset.pageValue.contains("a b%23c%3Fd%25e 壁纸+x&y'z.png"))
        XCTAssertFalse(asset.pageValue.hasPrefix("/"))
    }

    func testExtensionOutsideTheFilterIsNotStaged() async throws {
        let store = makeStore()
        let video = try writeSource("clip.webm")
        await assertFails(.unsupportedType) { try await store.importFile(at: video, propertyId: "background", filter: .image) }
        XCTAssertNil(store.randomFile(propertyId: "background"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("background/clip.webm").path))
    }

    func testFilterMatchingIgnoresExtensionCase() async throws {
        let source = try writeSource("Clouds.PNG")
        let asset = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.stagedPath))
    }

    func testUnrestrictedPropertyTakesImagesAndVideosButNothingElse() async throws {
        let folder = root.appendingPathComponent("mixed", isDirectory: true)
        try writeSource("still.png", in: folder)
        try writeSource("clip.webm", in: folder)
        try writeSource("notes.txt", in: folder)
        try writeSource("tool.sh", in: folder)

        let assets = try await makeStore().importDirectory(
            at: folder, propertyId: "asset", filter: .any, limit: 100)

        XCTAssertEqual(assets.map { URL(fileURLWithPath: $0.stagedPath).lastPathComponent },
                       ["clip.webm", "still.png"])
    }

    func testReadOnlyProjectDirectoryFailsWithAReason() async throws {
        let source = try writeSource("clouds.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: project.path)
        let store = makeStore()
        await assertFails(.projectNotWritable) { try await store.importFile(at: source, propertyId: "background", filter: .image) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testSourceInsideTheStagingRootIsRefused() async throws {
        let store = makeStore()
        let first = try writeSource("clouds.png")
        let staged = try await store.importFile(at: first, propertyId: "background", filter: .image)
        await assertFails(.sourceInsideStaging) {
            try await store.importFile(at: URL(fileURLWithPath: staged.stagedPath), propertyId: "second", filter: .image)
        }
    }

    func testReimportingAPropertyDropsTheAssetItReplaces() async throws {
        let store = makeStore()
        let first = try await store.importFile(at: try writeSource("first.png"), propertyId: "background", filter: .image)
        let second = try await store.importFile(at: try writeSource("second.png"), propertyId: "background", filter: .image)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.stagedPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.stagedPath))
        XCTAssertEqual(store.stagedFiles(propertyId: "background"), [second])
    }

    // MARK: - Directory

    func testDirectoryImportStagesOnlyMatchingFilesAtOneLevel() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        try writeSource("a.png", in: folder)
        try writeSource("b.jpg", in: folder)
        try writeSource("notes.txt", in: folder)
        try writeSource("nested.png", in: folder.appendingPathComponent("inner", isDirectory: true))

        let assets = try await makeStore().importDirectory(
            at: folder, propertyId: "gallery", filter: .image, limit: 100)

        XCTAssertEqual(assets.map { URL(fileURLWithPath: $0.stagedPath).lastPathComponent }, ["a.png", "b.jpg"])
    }

    func testFileCountLimitTruncatesAndSaysSo() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        for index in 0..<5 { try writeSource("image-\(index).png", in: folder) }
        let store = makeStore()

        let capped = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 3)
        XCTAssertEqual(capped.count, 3)
        XCTAssertTrue(store.isTruncated(propertyId: "gallery"))

        let complete = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 10)
        XCTAssertEqual(complete.count, 5)
        XCTAssertFalse(store.isTruncated(propertyId: "gallery"))
    }

    func testDirectoryChangeBurstProducesOneCoalescedDiff() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        try writeSource("keep.png", in: folder)
        let removedSource = try writeSource("gone.png", in: folder)
        var watcher: ManualDirectoryWatcher?
        let store = makeStore(watcher: { url, onChange in
            let made = ManualDirectoryWatcher(url: url, trigger: onChange)
            watcher = made
            return made
        })
        var diffs: [(added: [UserAssetImport], removed: [UserAssetImport])] = []
        store.onDirectoryChanged = { _, added, removed in diffs.append((added, removed)) }
        try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)

        try writeSource("added-1.png", in: folder)
        try writeSource("added-2.png", in: folder)
        try FileManager.default.removeItem(at: removedSource)
        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()

        XCTAssertEqual(diffs.count, 1, "a settled burst must report one diff, not one per file")
        let diff = try XCTUnwrap(diffs.first)
        XCTAssertEqual(diff.added.map { URL(fileURLWithPath: $0.stagedPath).lastPathComponent },
                       ["added-1.png", "added-2.png"])
        XCTAssertEqual(diff.removed.map { URL(fileURLWithPath: $0.stagedPath).lastPathComponent }, ["gone.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(diff.removed.first).stagedPath))
        XCTAssertEqual(store.stagedFiles(propertyId: "gallery").count, 3)
    }

    func testUnchangedDirectoryReportsNoDiff() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        try writeSource("a.png", in: folder)
        var watcher: ManualDirectoryWatcher?
        let store = makeStore(watcher: { url, onChange in
            let made = ManualDirectoryWatcher(url: url, trigger: onChange)
            watcher = made
            return made
        })
        var diffs = 0
        store.onDirectoryChanged = { _, _, _ in diffs += 1 }
        try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)

        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()
        XCTAssertEqual(diffs, 0)
    }

    func testTemporarilyUnavailableDirectoryKeepsRetainedFilesAndRecovers() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        try writeSource("kept.png", bytes: "only retained bytes", in: folder)
        var watcher: ManualDirectoryWatcher?
        let store = makeStore(watcher: { url, change in
            let made = ManualDirectoryWatcher(url: url, trigger: change)
            watcher = made
            return made
        })
        let before = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        let saved = try manifest()
        let disconnected = root.appendingPathComponent("temporarily-disconnected")
        try FileManager.default.moveItem(at: folder, to: disconnected)

        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()

        XCTAssertEqual(try manifest(), saved)
        XCTAssertEqual(store.stagedFiles(propertyId: "gallery"), before)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(before.first).stagedPath)),
                       Data("only retained bytes".utf8))
        XCTAssertTrue(store.isSourceMissing(propertyId: "gallery"))

        try FileManager.default.moveItem(at: disconnected, to: folder)
        try writeSource("later.png", in: folder)
        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()
        XCTAssertFalse(store.isSourceMissing(propertyId: "gallery"))
        XCTAssertEqual(store.stagedFiles(propertyId: "gallery").count, 2)
    }

    func testUnreadableDirectoryEntryDoesNotAuthorizeDeletingItsRetainedCopy() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        let source = try writeSource("kept.png", in: folder)
        var watcher: ManualDirectoryWatcher?
        let store = makeStore(watcher: { url, change in
            let made = ManualDirectoryWatcher(url: url, trigger: change)
            watcher = made
            return made
        })
        let before = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        let saved = try manifest()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path) }
        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()
        XCTAssertEqual(try manifest(), saved)
        XCTAssertEqual(store.stagedFiles(propertyId: "gallery"), before)
        XCTAssertEqual(storedFiles(wallpaperId: "2001", propertyId: "gallery").count, 1)
    }

    func testFailedManifestCommitPreservesReferencesAndBytesUntilRetry() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        let source = try writeSource("kept.png", in: folder)
        var watcher: ManualDirectoryWatcher?
        let store = makeStore(watcher: { url, change in
            let made = ManualDirectoryWatcher(url: url, trigger: change)
            watcher = made
            return made
        })
        let before = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        let saved = try manifest()
        let directory = managedRoot.appendingPathComponent("2001", isDirectory: true)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        XCTAssertThrowsError(try ManagedUserAssetStore().write(saved), "the fixture must actually refuse the commit")

        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()
        XCTAssertEqual(try manifest(), saved)
        XCTAssertEqual(store.stagedFiles(propertyId: "gallery"), before)
        XCTAssertEqual(storedFiles(wallpaperId: "2001", propertyId: "gallery").count, 1)
        do { try await store.clear(propertyId: "gallery"); XCTFail("Expected a manifest write failure") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        XCTAssertEqual(try manifest(), saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(before.first).stagedPath))

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()
        XCTAssertEqual(store.stagedFiles(propertyId: "gallery"), [])
        XCTAssertEqual(try manifest().properties["gallery"]?.assets, [])
        XCTAssertEqual(storedFiles(wallpaperId: "2001", propertyId: "gallery"), [])
    }

    func testReplacedFileIsRestagedSoTheStagedBytesFollowTheSource() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        let source = try writeSource("a.png", bytes: "before", in: folder)
        var watcher: ManualDirectoryWatcher?
        let store = makeStore(watcher: { url, onChange in
            let made = ManualDirectoryWatcher(url: url, trigger: onChange)
            watcher = made
            return made
        })
        let imported = try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        let staged = try XCTUnwrap(imported.first)

        // A replace, not an in-place write: the staged hard link would otherwise still
        // point at the old inode.
        try FileManager.default.removeItem(at: source)
        try Data("after-the-replacement".utf8).write(to: source)
        try XCTUnwrap(watcher).fire()
        await store.waitForPendingChanges()

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: staged.stagedPath)),
                       Data("after-the-replacement".utf8))
    }

    func testDepartedDirectoryCallbacksCannotReplaceOrPruneCurrentSelection() async throws {
        let departed = root.appendingPathComponent("departed", isDirectory: true)
        let current = root.appendingPathComponent("current", isDirectory: true)
        let original = try writeSource("a.png", bytes: "departed bytes", in: departed)
        let replacement = try writeSource("a.png", bytes: "current bytes", in: current)
        var watchers: [ManualDirectoryWatcher] = []
        let retiredStore = makeStore(watcher: { url, callback in
            let watcher = ManualDirectoryWatcher(url: url, trigger: callback)
            watchers.append(watcher)
            return watcher
        })
        _ = try await retiredStore.importDirectory(at: departed, propertyId: "gallery", filter: .image, limit: 100)
        let repeated = try await retiredStore.importDirectory(at: departed, propertyId: "gallery", filter: .image, limit: 100)
        // A queued callback from an earlier watcher cannot act for its replacement,
        // even when both watched the same directory.
        try Data("unobserved departure".utf8).write(to: original, options: .atomic)
        watchers[0].fire()
        await retiredStore.waitForPendingChanges()
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(repeated.first).stagedPath)), Data("departed bytes".utf8))

        let currentStore = makeStore()
        let selected = try await currentStore.importDirectory(at: current, propertyId: "gallery", filter: .image, limit: 100)
        let currentManifest = try manifest()
        try FileManager.default.removeItem(at: departed)
        watchers[1].fire()
        await retiredStore.waitForPendingChanges()
        XCTAssertEqual(try manifest(), currentManifest)
        XCTAssertEqual(currentStore.stagedFiles(propertyId: "gallery"), selected)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(selected.first).stagedPath)), Data("current bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: replacement), Data("current bytes".utf8))
        XCTAssertTrue(watchers[1].isStopped)
    }

    // MARK: - Random selection

    func testPreparationRunsOffMainAndCancellationDoesNotPublishASelection() async throws {
        let gate = PreparationGate(entered: expectation(description: "background preparation"))
        defer { gate.release() }
        let store = UserAssetStore(projectURL: project, wallpaperId: "2001",
            watcherFactory: { ManualDirectoryWatcher(url: $0, trigger: $1) },
            beforePreparation: { try gate.wait() })
        let source = try writeSource("cancelled.png")
        let task = Task { try await store.importFile(at: source, propertyId: "cover", filter: .image) }
        await fulfillment(of: [gate.entered], timeout: 5)
        // Reaching here while the worker is held proves this actor can still service UI work.
        XCTAssertTrue(Thread.isMainThread)
        task.cancel()
        gate.release()
        do { _ = try await task.value; XCTFail("Cancelled selection must not commit") }
        catch is CancellationError {} catch { throw error }
        XCTAssertTrue(try manifest().properties.isEmpty)
        XCTAssertTrue(store.stagedFiles(propertyId: "cover").isEmpty)
    }

    private final class PreparationGate: @unchecked Sendable {
        let entered: XCTestExpectation
        private let condition = NSCondition()
        private var held = true
        init(entered: XCTestExpectation) { self.entered = entered }
        func wait() throws {
            XCTAssertFalse(Thread.isMainThread)
            condition.lock()
            defer { condition.unlock() }
            entered.fulfill()
            let deadline = Date().addingTimeInterval(5)
            while held {
                guard condition.wait(until: deadline) else { throw CancellationError() }
            }
        }
        func release() {
            condition.lock()
            held = false
            condition.broadcast()
            condition.unlock()
        }
    }

    func testSeparateStoresSerializeOneWallpaperButOtherWallpapersContinue() async throws {
        let gate = PreparationGate(entered: expectation(description: "first preparation held"))
        defer { gate.release() }
        let queued = expectation(description: "second preparation queued")
        let first = UserAssetStore(projectURL: project, wallpaperId: "2001",
            managed: ManagedUserAssetStore(root: managedRoot), beforePreparation: { try gate.wait() })
        let second = UserAssetStore(projectURL: project, wallpaperId: "2001",
            managed: ManagedUserAssetStore(root: managedRoot, onPreparationQueued: { queued.fulfill() }))
        let firstURL = try writeSource("first.png", bytes: "retired")
        let secondURL = try writeSource("second.png", bytes: "newest")
        let retired = Task { try await first.importFile(at: firstURL, propertyId: "cover", filter: .image) }
        await fulfillment(of: [gate.entered], timeout: 5)
        let current = Task { try await second.importFile(at: secondURL, propertyId: "cover", filter: .image) }
        await fulfillment(of: [queued], timeout: 5)
        let independentProject = root.appendingPathComponent("independent")
        try FileManager.default.createDirectory(at: independentProject, withIntermediateDirectories: true)
        let independent = UserAssetStore(projectURL: independentProject, wallpaperId: "3001",
            managed: ManagedUserAssetStore(root: managedRoot))
        _ = try await independent.importFile(at: firstURL, propertyId: "cover", filter: .image)
        XCTAssertTrue(try manifest(wallpaperId: "2001").properties.isEmpty)
        retired.cancel()
        gate.release()
        do { _ = try await retired.value; XCTFail("Retired preparation must cancel") }
        catch is CancellationError {} catch { throw error }
        let selected = try await current.value
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: selected.stagedPath)), Data("newest".utf8))
        XCTAssertEqual(try manifest().properties["cover"]?.sourcePath, secondURL.path)
        XCTAssertNotNil(try manifest(wallpaperId: "3001").properties["cover"])
    }

    func testPurgeWaitsForAdoptedBytesToBeCommitted() async throws {
        let gate = PreparationGate(entered: expectation(description: "adopted before manifest commit"))
        defer { gate.release() }
        let queued = expectation(description: "purge queued")
        let source = try writeSource("pending.png", bytes: "pending retained bytes")
        let importing = UserAssetStore(projectURL: project, wallpaperId: "2001",
            managed: ManagedUserAssetStore(root: managedRoot, beforePropertyCommit: { try gate.wait() }))
        let preparing = Task { try await importing.importFile(at: source, propertyId: "cover", filter: .image) }
        await fulfillment(of: [gate.entered], timeout: 5)
        let stored = try XCTUnwrap(storedFiles(wallpaperId: "2001", propertyId: "cover").first)
        let purgingStore = ManagedUserAssetStore(root: managedRoot, onPreparationQueued: { queued.fulfill() })
        let purge = Task { try await UserAssetStorage.purgeUnreferencedDerivedCaches(store: purgingStore) }
        await fulfillment(of: [queued], timeout: 5)
        XCTAssertEqual(try Data(contentsOf: stored), Data("pending retained bytes".utf8))
        gate.release()
        let selected = try await preparing.value
        let released = try await purge.value
        XCTAssertEqual(released, 0)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: selected.stagedPath)), Data("pending retained bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: stored), Data("pending retained bytes".utf8))
    }

    func testCancelledSameContentPublisherCannotDeleteAnotherInstancesWinner() async throws {
        let gate = PreparationGate(entered: expectation(description: "first copy waits before publishing"))
        defer { gate.release() }
        let source = try writeSource("shared.png", bytes: "shared content")
        let first = ManagedUserAssetStore(root: managedRoot, beforePublication: { try gate.wait() })
        let second = ManagedUserAssetStore(root: managedRoot)
        let pending = Task.detached {
            try first.adopt(readingFrom: source, fileName: "shared.png", sourcePath: source.path,
                wallpaperId: "2001", propertyId: "cover", known: nil)
        }
        await fulfillment(of: [gate.entered], timeout: 5)
        let winner = try await Task.detached {
            try second.adopt(readingFrom: source, fileName: "shared.png", sourcePath: source.path,
                wallpaperId: "2001", propertyId: "cover", known: nil)
        }.value
        pending.cancel()
        gate.release()
        do { _ = try await pending.value; XCTFail("Cancelled publisher must not return a selection") }
        catch is CancellationError {} catch { throw error }
        let destination = try second.storedURL(wallpaperId: "2001", propertyId: "cover", asset: winner)
        XCTAssertEqual(try Data(contentsOf: destination), Data("shared content".utf8))
        XCTAssertEqual(storedFiles(wallpaperId: "2001", propertyId: "cover").map { $0.resolvingSymlinksInPath() },
                       [destination.resolvingSymlinksInPath()])
    }

    func testAuthorizationRollbackKeepsAnotherWorkersCommittedProperty() async throws {
        enum FailedCommit: Error { case expected }
        let original = try writeSource("original.png")
        let other = try writeSource("other.png", bytes: "independent property")
        _ = try await makeStore().importFile(at: original, propertyId: "cover", filter: .image)
        let managed = ManagedUserAssetStore(root: managedRoot)
        var originalManifest = try managed.manifest(wallpaperId: "2001")
        originalManifest.properties["cover"]?.originalSourceUnauthorized = true
        try managed.write(originalManifest)
        let anotherWorker = makeStore()
        do {
            try await UserAssetSelectionAuthorization.perform(managed: managed, wallpaperID: "2001",
                selections: ["cover": original.path]) {
                _ = try await anotherWorker.importFile(at: other, propertyId: "background", filter: .image)
                throw FailedCommit.expected
            }
            XCTFail("Expected the engine commit to fail")
        } catch FailedCommit.expected {}
        let final = try managed.manifest(wallpaperId: "2001")
        XCTAssertEqual(final.properties["cover"], originalManifest.properties["cover"])
        XCTAssertEqual(final.properties["background"]?.sourcePath, other.path)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(anotherWorker.stagedFiles(propertyId: "background").first).stagedPath)), Data("independent property".utf8))
    }

    func testOlderRollbackCannotRevokeANewerSuccessfulSelectionOfTheSamePath() async throws {
        enum FailedCommit: Error { case expected }
        let source = try writeSource("same.png")
        _ = try await makeStore().importFile(at: source, propertyId: "cover", filter: .image)
        let managed = ManagedUserAssetStore(root: managedRoot)
        var original = try managed.manifest(wallpaperId: "2001")
        original.properties["cover"]?.originalSourceUnauthorized = true
        try managed.write(original)
        do {
            try await UserAssetSelectionAuthorization.perform(managed: managed, wallpaperID: "2001",
                selections: ["cover": source.path]) {
                try await UserAssetSelectionAuthorization.perform(
                    managed: ManagedUserAssetStore(root: self.managedRoot), wallpaperID: "2001",
                    selections: ["cover": source.path], commit: {})
                throw FailedCommit.expected
            }
            XCTFail("Expected the earlier engine mutation to fail")
        } catch FailedCommit.expected {}
        let current = try XCTUnwrap(managed.manifest(wallpaperId: "2001").properties["cover"])
        XCTAssertNil(current.originalSourceUnauthorized)
        XCTAssertEqual(current.authorizedSourcePath, source.path)
    }

    func testRandomFileIsNilWithoutStagedEntries() async throws {
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let store = makeStore()

        XCTAssertNil(store.randomFile(propertyId: "gallery"))
        try await store.importDirectory(at: empty, propertyId: "gallery", filter: .image, limit: 100)
        XCTAssertNil(store.randomFile(propertyId: "gallery"))
    }

    func testBothSamePathSelectionsFailInEitherCompletionOrder() async throws {
        enum FailedCommit: Error { case expected }
        for olderFailsFirst in [false, true] {
            let source = try writeSource("same-order-\(olderFailsFirst).png")
            _ = try await makeStore().importFile(at: source, propertyId: "cover", filter: .image)
            let managed = ManagedUserAssetStore(root: managedRoot)
            var original = try managed.manifest(wallpaperId: "2001")
            original.properties["cover"]?.originalSourceUnauthorized = true
            original.properties["cover"]?.authorizedSourcePath = nil
            try managed.write(original)
            let firstEntered = expectation(description: "first grant")
            let secondEntered = expectation(description: "second grant")
            var firstRelease: CheckedContinuation<Void, Never>?
            var secondRelease: CheckedContinuation<Void, Never>?
            defer { firstRelease?.resume(); secondRelease?.resume() }
            let first = Task { @MainActor in
                do {
                    try await UserAssetSelectionAuthorization.perform(managed: managed, wallpaperID: "2001",
                        selections: ["cover": source.path]) {
                        await withCheckedContinuation { firstRelease = $0; firstEntered.fulfill() }
                        throw FailedCommit.expected
                    }
                    XCTFail("First commit must fail")
                } catch FailedCommit.expected {}
            }
            await fulfillment(of: [firstEntered], timeout: 5)
            let second = Task { @MainActor in
                do {
                    try await UserAssetSelectionAuthorization.perform(managed: managed, wallpaperID: "2001",
                        selections: ["cover": source.path]) {
                        await withCheckedContinuation { secondRelease = $0; secondEntered.fulfill() }
                        throw FailedCommit.expected
                    }
                    XCTFail("Second commit must fail")
                } catch FailedCommit.expected {}
            }
            await fulfillment(of: [secondEntered], timeout: 5)
            if olderFailsFirst {
                firstRelease?.resume(); firstRelease = nil
                try await first.value
                XCTAssertNil(try managed.manifest(wallpaperId: "2001").properties["cover"]?.originalSourceUnauthorized)
                secondRelease?.resume(); secondRelease = nil
                try await second.value
            } else {
                secondRelease?.resume(); secondRelease = nil
                try await second.value
                XCTAssertNil(try managed.manifest(wallpaperId: "2001").properties["cover"]?.originalSourceUnauthorized)
                firstRelease?.resume(); firstRelease = nil
                try await first.value
            }
            XCTAssertEqual(try managed.manifest(wallpaperId: "2001"), original)
        }
    }

    func testRandomFileOnlyReturnsStagedEntriesAndDoesNotRescan() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        for index in 0..<3 { try writeSource("image-\(index).png", in: folder) }
        let store = makeStore()
        let staged = Set(try await store.importDirectory(
            at: folder, propertyId: "gallery", filter: .image, limit: 100).map(\.stagedPath))

        // Added without a change notification: an implementation that walked the folder on
        // every call would start handing this one out.
        try writeSource("unnoticed.png", in: folder)

        var seen = Set<String>()
        for _ in 0..<60 {
            let pick = try XCTUnwrap(store.randomFile(propertyId: "gallery"))
            XCTAssertTrue(staged.contains(pick.stagedPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: pick.stagedPath))
            seen.insert(pick.stagedPath)
        }
        XCTAssertEqual(seen, staged, "selection must be able to reach every staged entry")
    }

    // MARK: - Removal

    func testClearingAPropertyRemovesItsStagingAndStopsWatching() async throws {
        let folder = root.appendingPathComponent("gallery", isDirectory: true)
        let source = try writeSource("a.png", in: folder)
        var watcher: ManualDirectoryWatcher?
        let store = makeStore(watcher: { url, onChange in
            let made = ManualDirectoryWatcher(url: url, trigger: onChange)
            watcher = made
            return made
        })
        try await store.importDirectory(at: folder, propertyId: "gallery", filter: .image, limit: 100)
        try await store.importFile(at: try writeSource("solo.png"), propertyId: "background", filter: .image)

        try await store.clear(propertyId: "gallery")

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("gallery").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.appendingPathComponent("background").path))
        XCTAssertTrue(try XCTUnwrap(watcher).isStopped)
        XCTAssertNil(store.randomFile(propertyId: "gallery"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the user's own file must survive")
    }

    func testClearAllRemovesTheWholeStagingDirectoryAndNothingElse() async throws {
        let store = makeStore()
        let authored = project.appendingPathComponent("index.html")
        try Data("<html></html>".utf8).write(to: authored)
        try await store.importFile(at: try writeSource("clouds.png"), propertyId: "background", filter: .image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))

        await store.clearAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: authored.path))
        XCTAssertNil(store.randomFile(propertyId: "background"))
    }

    // MARK: - Managed storage

    /// The bridge inside the project is derived. Wiping all of it must cost nothing but
    /// the work of relinking, because the bytes live in the managed store — which the
    /// user's own file being gone as well is what actually proves.
    func testDeletingTheWholeBridgeLosesNothing() async throws {
        let source = try writeSource("clouds.png", bytes: "survives-the-bridge")
        let first = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.stagedPath))

        try FileManager.default.removeItem(at: staging)
        try FileManager.default.removeItem(at: source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.stagedPath))

        let rebuilt = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        XCTAssertEqual(rebuilt.stagedPath, first.stagedPath)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: rebuilt.stagedPath)),
            Data("survives-the-bridge".utf8))
    }

    /// Deleting the wallpaper and downloading it again replaces the whole project
    /// folder. The property's asset is keyed on the stable wallpaper id, so it comes
    /// back — and it comes back even though the user's own file is gone too.
    func testStoreSurvivesDeletingAndRecreatingTheProject() async throws {
        let source = try writeSource("clouds.png", bytes: "survives-redownload")
        try await makeStore().importFile(at: source, propertyId: "background", filter: .image)

        try FileManager.default.removeItem(at: project)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let store = makeStore()
        let restored = try await store.importFile(at: source, propertyId: "background", filter: .image)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: restored.stagedPath)),
            Data("survives-redownload".utf8))
        XCTAssertTrue(store.isSourceMissing(propertyId: "background"),
                      "the user's own file is gone, and the panel has to be able to say so")
        XCTAssertTrue(store.isManaged(propertyId: "background"))
    }

    /// A second wallpaper id is a different wallpaper. A bridge this build wrote names
    /// its owner, so the other id cannot mistake it for a round-6 staging directory and
    /// adopt files that are not its own.
    func testAnotherWallpaperIdDoesNotInheritTheStoredAsset() async throws {
        let source = try writeSource("clouds.png")
        try await makeStore(wallpaperId: "2001").importFile(at: source, propertyId: "background", filter: .image)
        try FileManager.default.removeItem(at: source)

        XCTAssertEqual(
            try Data(contentsOf: staging.appendingPathComponent(UserAssetStore.ownerMarkerName)),
            Data("2001".utf8), "the bridge has to say whose it is")
        await assertFails(.sourceUnreadable) {
            try await makeStore(wallpaperId: "3002").importFile(
                at: source, propertyId: "background", filter: .image)
        }
        XCTAssertTrue(
            try manifest(wallpaperId: "3002").properties.isEmpty,
            "nothing may be recorded for a wallpaper that owns none of this")
        _ = try await makeStore(wallpaperId: "2001").importFile(
            at: source, propertyId: "background", filter: .image)
    }

    /// An unchanged selection must not be re-copied on every launch. The stored file's
    /// inode is the proof: a fresh copy would be a new one.
    func testReimportingAnUnchangedSelectionCopiesNothing() async throws {
        let source = try writeSource("clouds.png", bytes: "stable")
        try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        let stored = try XCTUnwrap(storedFiles(wallpaperId: "2001", propertyId: "background").first)
        let before = try inode(stored.path)

        for _ in 0..<3 {
            try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        }

        let after = storedFiles(wallpaperId: "2001", propertyId: "background")
        XCTAssertEqual(after.count, 1, "a second copy of an unchanged file is a leak")
        XCTAssertEqual(try inode(XCTUnwrap(after.first).path), before)
    }

    func testManifestPreservesPreciseSourceTimestampAcrossRecreation() async throws {
        let source = try writeSource("precise.png")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000.375)], ofItemAtPath: source.path)
        _ = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        let saved = try XCTUnwrap(manifest().properties["background"]?.assets.first)
        let actual = try XCTUnwrap(source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        XCTAssertEqual(saved.sourceModificationDate, actual)
        _ = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        XCTAssertEqual(try manifest().properties["background"]?.assets.first, saved)
    }

    /// An asset present in neither the user's folder nor the store is missing, and the
    /// property has to fail loudly rather than come back silently empty.
    func testAnAssetMissingFromBothPlacesIsReportedRatherThanCleared() async throws {
        let source = try writeSource("clouds.png")
        let store = makeStore()
        try await store.importFile(at: source, propertyId: "background", filter: .image)

        try FileManager.default.removeItem(at: source)
        try FileManager.default.removeItem(
            at: managedRoot.appendingPathComponent("2001/background", isDirectory: true))

        await assertFails(.sourceUnreadable) {
            try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        }
    }

    /// A round-6 project still holds hard links into the user's file and nothing in the
    /// store. Absorbing them must not touch the old location, and must happen once.
    func testALegacyStagingDirectoryIsMigratedOnceWithoutBeingDeleted() async throws {
        let legacy = staging.appendingPathComponent("background", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let original = try writeSource("clouds.png", bytes: "round-six-bytes")
        let staged = legacy.appendingPathComponent("clouds.png")
        try FileManager.default.linkItem(at: original, to: staged)
        try FileManager.default.removeItem(at: original)

        let restored = try await makeStore().importFile(at: original, propertyId: "background", filter: .image)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: restored.stagedPath)),
            Data("round-six-bytes".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path),
                      "migration publishes into the store; it never deletes the old location")
        let record = try XCTUnwrap(try manifest().properties["background"])
        XCTAssertEqual(record.migratedLegacyPaths, [legacy.path])
        XCTAssertEqual(record.sourcePath, original.path,
                       "the path recorded is the user's original, not the staged link")

        let stored = try XCTUnwrap(storedFiles(wallpaperId: "2001", propertyId: "background").first)
        let before = try inode(stored.path)
        try await makeStore().importFile(at: original, propertyId: "background", filter: .image)
        XCTAssertEqual(storedFiles(wallpaperId: "2001", propertyId: "background").count, 1)
        XCTAssertEqual(try inode(XCTUnwrap(storedFiles(wallpaperId: "2001", propertyId: "background").first).path),
                       before, "migration is recorded, so a second launch copies nothing")
    }

    // MARK: - Purging

    func testPurgeKeepsEveryAssetTheManifestStillListsAndReclaimsTheRest() async throws {
        let store = makeStore()
        try await store.importFile(at: try writeSource("kept.png", bytes: "keep-me"), propertyId: "background", filter: .image)
        let kept = try XCTUnwrap(storedFiles(wallpaperId: "2001", propertyId: "background").first)

        // An orphan of exactly the shape a crash between copying and recording leaves.
        let orphan = managedRoot
            .appendingPathComponent("2001/background/deadbeefdeadbeefdeadbeefdeadbeef", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data(String(repeating: "x", count: 512).utf8).write(to: orphan.appendingPathComponent("orphan.png"))
        // A whole wallpaper folder nothing recorded.
        let strayWallpaper = managedRoot.appendingPathComponent("9999/gallery", isDirectory: true)
        try FileManager.default.createDirectory(at: strayWallpaper, withIntermediateDirectories: true)
        try Data(String(repeating: "y", count: 256).utf8).write(to: strayWallpaper.appendingPathComponent("stray.png"))

        let released = try await UserAssetStorage.purgeUnreferencedDerivedCaches()

        XCTAssertEqual(released, 768, "only the two unreferenced files can be reclaimed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path),
                      "a referenced asset is never a purge candidate")
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedRoot.appendingPathComponent("9999").path))
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: store.stagedFiles(propertyId: "background")[0].stagedPath)),
            Data("keep-me".utf8))
    }

    /// A property whose source has gone missing is exactly the case where the store's
    /// copy is the only copy. Purging must not be what finally loses it.
    func testPurgeKeepsTheStoredCopyOfAnAssetWhoseSourceIsGone() async throws {
        let source = try writeSource("clouds.png", bytes: "last-copy")
        try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        try FileManager.default.removeItem(at: source)

        let released = try await UserAssetStorage.purgeUnreferencedDerivedCaches()
        XCTAssertEqual(released, 0)

        let store = makeStore()
        let restored = try await store.importFile(at: source, propertyId: "background", filter: .image)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: restored.stagedPath)), Data("last-copy".utf8))
    }

    func testInvalidManifestPreventsPurgeAndReimportFromDiscardingRetainedFiles() async throws {
        let source = try writeSource("kept.png", bytes: "last-copy")
        _ = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
        let stored = try XCTUnwrap(storedFiles(wallpaperId: "2001", propertyId: "background").first)
        let manifestURL = managedRoot.appendingPathComponent("2001/manifest.json")
        let original = try Data(contentsOf: manifestURL)
        let unsupported = try XCTUnwrap(String(data: original, encoding: .utf8))
            .replacingOccurrences(of: "\"version\":1", with: "\"version\":999")
        let foreign = try XCTUnwrap(String(data: original, encoding: .utf8))
            .replacingOccurrences(of: "\"wallpaperId\":\"2001\"", with: "\"wallpaperId\":\"other\"")
        for bytes in [Data("incomplete manifest".utf8), Data(unsupported.utf8), Data(foreign.utf8)] {
            try bytes.write(to: manifestURL)
            let orphan = managedRoot.appendingPathComponent("9999/orphan")
            try FileManager.default.createDirectory(at: orphan.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("reclaim".utf8).write(to: orphan)
            let released = try await UserAssetStorage.purgeUnreferencedDerivedCaches()
            XCTAssertEqual(released, 7)
            XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
            await assertFails(.manifestUnreadable) {
                _ = try await makeStore().importFile(at: source, propertyId: "background", filter: .image)
            }
            XCTAssertEqual(try Data(contentsOf: stored), Data("last-copy".utf8))
            XCTAssertEqual(try Data(contentsOf: manifestURL), bytes)
        }
        try original.write(to: manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: manifestURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path) }
        let released = try await UserAssetStorage.purgeUnreferencedDerivedCaches()
        XCTAssertEqual(released, 0)
        XCTAssertEqual(try Data(contentsOf: stored), Data("last-copy".utf8))
    }
}

/// Stands in for `DirectoryWatcher` so the store's diffing is exercised without FSEvents
/// timing. `DirectoryWatcherTests` covers the real stream.
private final class ManualDirectoryWatcher: DirectoryWatching {
    let url: URL
    private let trigger: @MainActor () -> Void
    private(set) var isStopped = false

    init(url: URL, trigger: @escaping @MainActor () -> Void) {
        self.url = url
        self.trigger = trigger
    }

    @MainActor func fire() { trigger() }

    func stop() { isStopped = true }
}
