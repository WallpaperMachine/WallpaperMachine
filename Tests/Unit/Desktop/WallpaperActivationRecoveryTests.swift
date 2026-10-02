import XCTest
@testable import WallpaperMachine

/// A wallpaper that refuses to render leaves the engine restoring its previous
/// configuration. The Library must stay usable so another wallpaper can be
/// applied without restarting the app.
@MainActor
final class WallpaperActivationRecoveryTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = home.appendingPathComponent("Library/failing", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A complete web project passes its preflight without decoding media or
        // needing scene assets; this test covers the apply failure, not validation.
        try Data(#"{"type":"web","title":"Failing","file":"index.html"}"#.utf8)
            .write(to: folder.appendingPathComponent("project.json"))
        try Data("<!doctype html><title>Failing</title>".utf8)
            .write(to: folder.appendingPathComponent("index.html"))
        setenv("WALLPAPER_MACHINE_HOME", home.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("WALLPAPER_MACHINE_HOME")
        try FileManager.default.removeItem(at: home)
    }

    func testFailedApplyKeepsLibraryActionsAvailable() async throws {
        let bridge = ApplyFailureBridge(noPointer: .init())
        let store = BridgeStore(bridge: bridge)
        try await store.refreshAllAsync()

        await XCTAssertThrowsErrorAsync(
            try await store.activateWallpaperAsync(id: "failing", displayId: "primary"))

        XCTAssertFalse(store.activationNeedsRefresh,
                       "A recovered apply failure must not lock the Library behind a manual refresh")
        XCTAssertNil(store.activatingWallpaperID)

        // The user must be able to pick another wallpaper right away.
        bridge.applyError = nil
        try await store.activateWallpaperAsync(id: "failing", displayId: "primary")
    }

    func testUnrecoverableApplyFailureStillDemandsRefresh() async throws {
        let bridge = ApplyFailureBridge(noPointer: .init())
        let store = BridgeStore(bridge: bridge)
        try await store.refreshAllAsync()
        bridge.snapshotsFail = true

        await XCTAssertThrowsErrorAsync(
            try await store.activateWallpaperAsync(id: "failing", displayId: "primary"))

        XCTAssertTrue(store.activationNeedsRefresh,
                      "Without a trustworthy re-read the app must ask for a full refresh")
    }

    func testMatroskaVideoCanBeActivatedWithEitherBackendPreference() async throws {
        let folder = try writeVideoProject(entry: "compatibility.mkv")
        _ = try SyntheticVideoFixture.writeMatroska(name: "compatibility", into: folder)

        for backend in ["compatibility", "native_preferred"] {
            let (store, _) = try await videoStore(backend: backend)
            try await store.activateWallpaperAsync(id: "failing", displayId: "primary")

            XCTAssertEqual(store.monitorInformationSnapshot.rows.first?.wallpaperId, "failing", backend)
            XCTAssertNil(store.activatingWallpaperID)
        }
    }

    func testMatroskaVideoOptionsCanBeAppliedWithEitherBackendPreference() async throws {
        let folder = try writeVideoProject(entry: "compatibility.mkv")
        _ = try SyntheticVideoFixture.writeMatroska(name: "compatibility", into: folder)

        for backend in ["compatibility", "native_preferred"] {
            let (store, _) = try await videoStore(backend: backend)
            try await store.applyWallpaperOptionsAsync(wallpaperId: "failing")

            XCTAssertEqual(store.monitorInformationSnapshot.rows.first?.wallpaperId, "failing", backend)
            XCTAssertNil(store.applyingWallpaperID)
        }
    }

    func testIncompleteVideoEntriesCannotChangeDisplayAssignment() async throws {
        let folder = home.appendingPathComponent("Library/failing", isDirectory: true)
        try Data().write(to: folder.appendingPathComponent("empty.mkv"))
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("directory.mkv"), withIntermediateDirectories: false)

        for entry in [nil, "", "missing.mkv", "empty.mkv", "directory.mkv"] as [String?] {
            _ = try writeVideoProject(entry: entry)
            let (store, _) = try await videoStore(backend: "compatibility")

            await XCTAssertThrowsErrorAsync(
                try await store.activateWallpaperAsync(id: "failing", displayId: "primary"))
            XCTAssertEqual(store.monitorInformationSnapshot.rows.first?.wallpaperId, "")
            await XCTAssertThrowsErrorAsync(
                try await store.applyWallpaperOptionsAsync(wallpaperId: "failing"))
            XCTAssertEqual(store.monitorInformationSnapshot.rows.first?.wallpaperId, "")
            XCTAssertFalse(store.activationNeedsRefresh)
            XCTAssertNil(store.activatingWallpaperID)
            XCTAssertNil(store.applyingWallpaperID)
        }
    }

    func testVideoDecoderFailurePreservesErrorAndAllowsRetry() async throws {
        for applyChanges in [false, true] {
            let folder = try writeVideoProject(entry: "broken.mov")
            _ = try SyntheticVideoFixture.writeCorrupt(name: "broken", into: folder)
            let (store, bridge) = try await videoStore(backend: "compatibility")
            let decoderError = NSError(domain: "VideoDecoder", code: 23)
            bridge.applyError = decoderError

            do {
                if applyChanges {
                    try await store.applyWallpaperOptionsAsync(wallpaperId: "failing")
                } else {
                    try await store.activateWallpaperAsync(id: "failing", displayId: "primary")
                }
                XCTFail("A decoder failure must not be reported as a successful application")
            } catch {
                XCTAssertEqual((error as NSError).domain, decoderError.domain)
                XCTAssertEqual((error as NSError).code, decoderError.code)
            }
            XCTAssertEqual(store.monitorInformationSnapshot.rows.first?.wallpaperId, "")
            XCTAssertFalse(store.activationNeedsRefresh)
            XCTAssertNil(store.activatingWallpaperID)
            XCTAssertNil(store.applyingWallpaperID)

            _ = try writeVideoProject(entry: "compatibility.mkv")
            _ = try SyntheticVideoFixture.writeMatroska(name: "compatibility", into: folder)
            bridge.applyError = nil
            if applyChanges {
                try await store.applyWallpaperOptionsAsync(wallpaperId: "failing")
            } else {
                try await store.activateWallpaperAsync(id: "failing", displayId: "primary")
            }
            XCTAssertEqual(store.monitorInformationSnapshot.rows.first?.wallpaperId, "failing")
        }
    }

    private func writeVideoProject(entry: String?) throws -> URL {
        let folder = home.appendingPathComponent("Library/failing", isDirectory: true)
        var manifest = ["type": "video", "title": "Video"]
        manifest["file"] = entry
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: folder.appendingPathComponent("project.json"))
        return folder
    }

    private func videoStore(backend: String) async throws -> (BridgeStore, ApplyFailureBridge) {
        let bridge = ApplyFailureBridge(noPointer: .init())
        bridge.kind = .video
        bridge.videoBackend = backend
        bridge.applyError = nil
        let store = BridgeStore(bridge: bridge)
        try await store.refreshAllAsync()
        return (store, bridge)
    }

    func testSupportPromptWaitsForSuccessfulDownloadedActivation() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prompt = SupportPromptStore(defaults: defaults)
        prompt.recordDownload(wallpaperID: "failing")
        let bridge = ApplyFailureBridge(noPointer: .init())
        let store = BridgeStore(bridge: bridge, supportPrompt: prompt)
        try await store.refreshAllAsync()
        XCTAssertFalse(prompt.isPending)

        await XCTAssertThrowsErrorAsync(
            try await store.activateWallpaperAsync(id: "failing", displayId: "primary", userInitiated: true))
        XCTAssertFalse(prompt.isPending)

        bridge.applyError = nil
        try await store.activateWallpaperAsync(id: "failing", displayId: "primary", userInitiated: true)
        XCTAssertTrue(prompt.isPending)
    }

    func testSupportPromptDoesNotTreatMissingDisplayAssignmentAsSuccess() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prompt = SupportPromptStore(defaults: defaults)
        prompt.recordDownload(wallpaperID: "failing")
        let bridge = ApplyFailureBridge(noPointer: .init())
        bridge.applyError = nil
        bridge.reportsActivation = false
        let store = BridgeStore(bridge: bridge, supportPrompt: prompt)
        try await store.refreshAllAsync()

        await XCTAssertThrowsErrorAsync(
            try await store.activateWallpaperAsync(id: "failing", displayId: "primary", userInitiated: true))
        XCTAssertFalse(prompt.isPending)
    }

    func testAutomaticActivationAndNoOpReapplyDoNotRequestSupport() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prompt = SupportPromptStore(defaults: defaults)
        prompt.recordDownload(wallpaperID: "failing")
        let bridge = ApplyFailureBridge(noPointer: .init())
        bridge.applyError = nil
        let store = BridgeStore(bridge: bridge, supportPrompt: prompt)
        try await store.refreshAllAsync()

        try await store.activateWallpaperAsync(id: "failing", displayId: "primary")
        XCTAssertFalse(prompt.isPending)
        try await store.activateWallpaperAsync(id: "failing", displayId: "primary", userInitiated: true)
        XCTAssertFalse(prompt.isPending)
    }

    func testApplyingAnImportedWallpaperDoesNotRequestSupport() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prompt = SupportPromptStore(defaults: defaults)
        let bridge = ApplyFailureBridge(noPointer: .init())
        bridge.applyError = nil
        let store = BridgeStore(bridge: bridge, supportPrompt: prompt)
        try await store.refreshAllAsync()

        try await store.activateWallpaperAsync(id: "failing", displayId: "primary", userInitiated: true)
        XCTAssertFalse(prompt.isPending)
    }

    func testEnablingDownloadedWallpaperThroughApplyChangesRequestsSupportOnlyOnSuccess() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prompt = SupportPromptStore(defaults: defaults)
        prompt.recordDownload(wallpaperID: "failing")
        let bridge = ApplyFailureBridge(noPointer: .init())
        let store = BridgeStore(bridge: bridge, supportPrompt: prompt)
        try await store.refreshAllAsync()

        await XCTAssertThrowsErrorAsync(
            try await store.applyWallpaperOptionsAsync(wallpaperId: "failing", userInitiated: true))
        XCTAssertFalse(prompt.isPending)
        bridge.applyError = nil
        try await store.applyWallpaperOptionsAsync(wallpaperId: "failing", userInitiated: true)
        XCTAssertTrue(prompt.isPending)
    }

    /// Downloads and imports rescan the library on their own schedule; one landing mid-apply
    /// waits for the apply instead of failing with a "wait" error.
    func testLibraryRefreshDuringApplyWaitsForIt() async throws {
        let bridge = ApplyFailureBridge(noPointer: .init())
        bridge.applyError = nil
        let store = BridgeStore(bridge: bridge)
        try await store.refreshAllAsync()
        var release: CheckedContinuation<Void, Never>?
        bridge.holdApply = { await withCheckedContinuation { release = $0 } }

        let activation = Task { try await store.activateWallpaperAsync(id: "failing", displayId: "primary") }
        while release == nil { await Task.yield() }
        let refresh = Task { try await store.refreshLibraryAsync() }
        for _ in 0..<50 { await Task.yield() }
        XCTAssertNil(bridge.refreshSawActive, "The rescan must not start while the apply is in flight")

        release?.resume()
        try await activation.value
        try await refresh.value
        XCTAssertEqual(bridge.refreshSawActive, true)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}

private final class ApplyFailureBridge: WallpaperBridge {
    var applyError: Error? = WallpaperActionError(
        message: "The wallpaper did not render a first frame within 90 seconds.")
    var snapshotsFail = false
    var kind: BridgeWallpaperKind = .projectScene
    var videoBackend = "compatibility"
    var reportsActivation = true
    var holdApply: (@MainActor () async -> Void)?
    /// Whether the wallpaper was already active when the library rescan reached the bridge.
    var refreshSawActive: Bool?

    override func refreshLibrary() async throws -> BridgeSnapshotBundle {
        refreshSawActive = active
        return bundle
    }

    override func allSnapshots() async throws -> BridgeSnapshotBundle {
        if snapshotsFail { throw CancellationError() }
        return bundle
    }

    override func selectWallpaper(id: String) async throws -> BridgeSnapshotBundle { bundle }

    override func setDisplayConfigEnabled(
        wallpaperId: String,
        displayId: String,
        enabled: Bool
    ) async throws -> BridgeWallpaperMutationBundle {
        mutation
    }

    override func wallpaperOptionsSnapshot(
        wallpaperId: String
    ) async throws -> BridgeWallpaperOptionsSnapshot {
        options
    }

    override func applyWallpaperOptions(
        wallpaperId: String
    ) async throws -> BridgeWallpaperMutationBundle {
        if let holdApply { await holdApply() }
        if let applyError { throw applyError }
        active = reportsActivation
        return mutation
    }

    /// Mirrors the engine: the wallpaper only becomes active once an apply succeeds.
    private var active = false

    var bundle: BridgeSnapshotBundle {
        BridgeSnapshotBundle(app: Self.app, library: library, wallpaperOptions: options,
                             monitorInformation: monitors, settings: settings)
    }

    private var mutation: BridgeWallpaperMutationBundle {
        BridgeWallpaperMutationBundle(app: Self.app, library: library,
                                      wallpaperOptions: options,
                                      monitorInformation: monitors, settings: settings)
    }

    private var monitors: BridgeMonitorInformationSnapshot {
        BridgeMonitorInformationSnapshot(rows: [BridgeMonitorInfoRow(
            displayId: "primary", title: "Primary",
            wallpaperId: active ? "failing" : "", wallpaperTitle: active ? "Failing" : "",
            mirrorTargetDisplayId: nil, mirrorTargetTitle: nil,
            scalingMode: "fill", targetFps: "30", audioResponse: false
        )])
    }

    private static let app = BridgeAppSnapshot(
        playbackState: .playing, selectedWallpaperId: "failing",
        activeWallpaperIds: [], errors: [])

    private var library: BridgeLibrarySnapshot {
        BridgeLibrarySnapshot(
            wallpapers: [BridgeWallpaperEntry(id: "failing", title: "Failing", kind: kind,
                                              supported: true, active: false, selected: true,
                                              previewPath: nil)],
            scanStatus: BridgeLibraryScanStatus(scanning: false, done: 1, total: 1),
            sceneCount: kind == .projectScene ? 1 : 0, videoCount: kind == .video ? 1 : 0,
            webpageCount: 0, unknownCount: 0)
    }

    private var options: BridgeWallpaperOptionsSnapshot {
        BridgeSnapshotFixtures.options(
            wallpaperId: "failing", title: "Failing", kind: kind,
            displayConfigurations: [BridgeDisplayConfigRow(
                displayId: "primary", title: "Primary", enabled: false, scalingMode: .fill,
                scalingFactor: 1, targetFps: 30, maxFps: 60, muted: false, volume: 1,
                dirty: false, canRestoreDefaults: false)],
            audioResponseEnabled: false)
    }

    private var settings: BridgeSettingsSnapshot {
        BridgeSnapshotFixtures.settings(
            displays: [BridgeDisplaySettingsRow(
                displayId: "primary", title: "Primary", enabled: true, mode: .standalone,
                mirrorTargets: [], selectedMirrorTarget: nil, scalingMode: .fill, scalingFactor: 1,
                targetFps: 30, maxFps: 60, muted: false, volume: 1)],
            videoBackend: videoBackend)
    }
}
