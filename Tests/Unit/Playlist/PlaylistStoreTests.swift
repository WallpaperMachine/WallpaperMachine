import XCTest
@testable import WallpaperMachine

@MainActor
final class PlaylistStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "WallpaperMachine.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    func testAnUnconfiguredDisplayDoesNothingOnItsOwn() {
        XCTAssertEqual(PlaylistStore(defaults: defaults).playlist(for: "primary").mode, .off)
    }

    func testPlaylistsAndDatesOutliveTheApp() {
        let store = PlaylistStore(defaults: defaults)
        store.update("primary") {
            $0.mode = .rotate
            $0.order = .shuffle
            $0.interval = 60
        }
        store.add(["a", "b", "a"], to: "primary")
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        store.schedule("primary", at: due)

        let reloaded = PlaylistStore(defaults: defaults)
        XCTAssertEqual(reloaded.playlist(for: "primary").mode, .rotate)
        XCTAssertEqual(reloaded.playlist(for: "primary").order, .shuffle)
        XCTAssertEqual(reloaded.playlist(for: "primary").interval, 60)
        XCTAssertEqual(reloaded.playlist(for: "primary").wallpaperIDs, ["a", "b"], "a wallpaper is on a list once")
        XCTAssertEqual(reloaded.nextChange["primary"], due)
    }

    func testChangingTheRhythmStartsAFreshWait() {
        let store = PlaylistStore(defaults: defaults)
        store.update("primary") { $0.mode = .rotate }
        store.schedule("primary", at: Date())
        store.add(["a"], to: "primary")
        XCTAssertNotNil(store.nextChange["primary"], "editing the list keeps the wait")
        store.update("primary") { $0.interval = 120 }
        XCTAssertNil(store.nextChange["primary"])
    }

    func testWallpapersThatLeaveTheLibraryLeaveEveryPlaylist() {
        let store = PlaylistStore(defaults: defaults)
        store.add(["a", "b"], to: "primary")
        store.update("second") {
            $0.mode = .dayNight
            $0.dayWallpaperID = "b"
            $0.nightWallpaperID = "c"
        }
        store.forget(["b"])
        XCTAssertEqual(store.playlist(for: "primary").wallpaperIDs, ["a"])
        XCTAssertNil(store.playlist(for: "second").dayWallpaperID)
        XCTAssertEqual(store.playlist(for: "second").nightWallpaperID, "c")
        XCTAssertNil(PlaylistStore(defaults: defaults).playlist(for: "second").dayWallpaperID)
    }

    func testRedatingToTheSameDateIsNotAChange() {
        let store = PlaylistStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.schedule("primary", at: date)
        let posts = PostCount()
        let token = NotificationCenter.default.addObserver(
            forName: PlaylistStore.didChangeNotification, object: store, queue: nil
        ) { _ in posts.value += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        store.schedule("primary", at: date)
        XCTAssertEqual(posts.value, 0, "the scheduler re-dates on every evaluation without a feedback loop")
    }
}

private final class PostCount: @unchecked Sendable {
    var value = 0
}
