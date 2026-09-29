import XCTest

@testable import WallpaperMachine

/// The playlist actions the panel sends, checked against the store without a web view.
@MainActor
final class WebPanelPlaylistTests: XCTestCase {
  private var root: URL!
  private var defaults: UserDefaults!
  private var playlists: PlaylistStore!
  private var controller: WebPanelController!

  override func setUp() async throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("panel-playlist-\(UUID().uuidString)")
    defaults = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
    playlists = PlaylistStore(defaults: defaults)
    let store = BridgeStore(bridge: WallpaperBridge(noPointer: .init()))
    store.settingsSnapshot = BridgeSnapshotFixtures.settings(displays: [
      display("primary", enabled: true, mode: .standalone),
      display("mirrored", enabled: true, mode: .mirror),
    ])
    store.librarySnapshot = BridgeLibrarySnapshot(
      wallpapers: [
        BridgeWallpaperEntry(
          id: "a", title: "A", kind: .video, supported: true, active: false, selected: false, previewPath: nil),
        BridgeWallpaperEntry(
          id: "b", title: "B", kind: .video, supported: true, active: false, selected: false, previewPath: nil),
        BridgeWallpaperEntry(
          id: "app", title: "App", kind: .unknown, supported: false, active: false, selected: false,
          previewPath: nil),
      ],
      scanStatus: BridgeLibraryScanStatus(scanning: false, done: 0, total: 0), sceneCount: 0,
      videoCount: 2, webpageCount: 0, unknownCount: 1)
    let workshop = WorkshopStore(
      downloader: WorkshopDownloadManager(sessionDirectory: root), supportDirectory: root,
      defaults: defaults)
    controller = WebPanelController(
      store: store, navigation: ControlPanelNavigation(), workshop: workshop, defaults: defaults,
      appLanguage: .english(), playlists: playlists)
  }

  override func tearDown() async throws {
    controller.stop()
    defaults.removePersistentDomain(forName: root.lastPathComponent)
    try? FileManager.default.removeItem(at: root)
  }

  private func display(_ id: String, enabled: Bool, mode: BridgeDisplayMode) -> BridgeDisplaySettingsRow {
    BridgeDisplaySettingsRow(
      displayId: id, title: id, enabled: enabled, mode: mode, mirrorTargets: [],
      selectedMirrorTarget: nil, scalingMode: .fill, scalingFactor: 1, targetFps: 30, maxFps: 60,
      muted: false, volume: 1)
  }

  func testSettingsReachThePlaylistOfTheNamedDisplay() async throws {
    try await controller.perform("playlistSetting", body: ["displayID": "primary", "key": "mode", "value": "rotate"])
    try await controller.perform("playlistSetting", body: ["displayID": "primary", "key": "interval", "value": 60])
    try await controller.perform("playlistSetting", body: ["displayID": "primary", "key": "dayStart", "value": 390])
    try await controller.perform("playlistSetting", body: ["displayID": "primary", "key": "dayWallpaper", "value": "b"])
    let playlist = playlists.playlist(for: "primary")
    XCTAssertEqual(playlist.mode, .rotate)
    XCTAssertEqual(playlist.interval, 60)
    XCTAssertEqual(playlist.dayStart, 390)
    XCTAssertEqual(playlist.dayWallpaperID, "b")
    let snapshot = try XCTUnwrap(controller.snapshot()["playlists"] as? [String: [String: Any]])
    XCTAssertEqual(snapshot["primary"]?["mode"] as? String, "rotate")
  }

  func testValuesThePanelNeverOffersAreRefused() async {
    for body: [String: Any] in [
      ["displayID": "primary", "key": "interval", "value": 7],
      ["displayID": "primary", "key": "dayStart", "value": 1440],
      ["displayID": "primary", "key": "mode", "value": "sometimes"],
      ["displayID": "primary", "key": "nightWallpaper", "value": "app"],
      ["displayID": "mirrored", "key": "mode", "value": "rotate"],
      ["displayID": "gone", "key": "mode", "value": "rotate"],
    ] {
      do {
        try await controller.perform("playlistSetting", body: body)
        XCTFail("accepted \(body)")
      } catch {}
    }
    XCTAssertEqual(playlists.playlist(for: "primary"), DisplayPlaylist())
    XCTAssertEqual(playlists.playlist(for: "mirrored"), DisplayPlaylist())
  }

  func testTheListGrowsFromTheLibraryAndShrinksOnRequest() async throws {
    try await controller.perform("playlistAdd", body: ["ids": ["b", "a", "b"]])
    XCTAssertEqual(playlists.playlist(for: "primary").wallpaperIDs, ["b", "a"], "the target display, once each")
    do {
      try await controller.perform("playlistAdd", body: ["ids": ["missing"]])
      XCTFail("a wallpaper that is not installed cannot join a list")
    } catch {}
    try await controller.perform("playlistRemove", body: ["id": "b"])
    XCTAssertEqual(playlists.playlist(for: "primary").wallpaperIDs, ["a"])
  }

  func testChangeNowNeedsARotatingDisplay() async throws {
    do {
      try await controller.perform("playlistSkip", body: ["displayID": "primary"])
      XCTFail("a display without a scheduler to move it cannot change now")
    } catch {}
    var asked: [String] = []
    playlists.skipHandler = { display in
      asked.append(display)
      return true
    }
    try await controller.perform("playlistSkip", body: ["displayID": "primary"])
    XCTAssertEqual(asked, ["primary"])
  }
}
