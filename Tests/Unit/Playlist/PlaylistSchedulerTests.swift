import XCTest
@testable import WallpaperMachine

@MainActor
final class PlaylistSchedulerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: PlaylistStore!
    private var shown: [String: String] = [:]
    private var running = true
    private var clock = Date()
    private var applied: [String] = []
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        suite = "WallpaperMachine.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        store = PlaylistStore(defaults: defaults)
        shown = ["primary": "a"]
        running = true
        clock = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 12))!
        applied = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        store = nil
        super.tearDown()
    }

    private func makeScheduler(library: [String] = ["a", "b", "c"], favorites: Set<String> = []) -> PlaylistScheduler {
        PlaylistScheduler(
            store: store, displays: { ["primary"] }, library: { library }, favorites: { favorites },
            current: { self.shown[$0] }, isRunning: { self.running },
            activate: { display, choose in
                guard let id = choose() else { return nil }
                self.shown[display] = id
                self.applied.append(id)
                return id
            },
            now: { self.clock }, calendar: calendar, center: NotificationCenter(),
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    }

    /// Lets the switch a scheduler started on the main actor run to its end.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    func testRotationWaitsItsIntervalThenAdvancesInOrder() async {
        store.update("primary") {
            $0.mode = .rotate
            $0.interval = 30
        }
        let scheduler = makeScheduler()
        scheduler.start()
        defer { scheduler.stop() }
        await settle()
        XCTAssertTrue(applied.isEmpty, "turning rotation on does not change the wallpaper at once")
        XCTAssertEqual(store.nextChange["primary"], clock.addingTimeInterval(30 * 60))

        clock.addTimeInterval(30 * 60)
        scheduler.evaluate()
        await settle()
        XCTAssertEqual(applied, ["b"])
        XCTAssertEqual(store.nextChange["primary"], clock.addingTimeInterval(30 * 60))
    }

    func testAChangeThatFellDueWhilePausedHappensOnceOnResume() async {
        store.update("primary") {
            $0.mode = .rotate
            $0.interval = 5
        }
        let scheduler = makeScheduler()
        scheduler.start()
        defer { scheduler.stop() }
        running = false
        clock.addTimeInterval(3 * 60 * 60)
        scheduler.evaluate()
        await settle()
        XCTAssertTrue(applied.isEmpty, "nothing changes while wallpapers are paused or hidden")

        running = true
        scheduler.evaluate()
        await settle()
        scheduler.evaluate()
        await settle()
        XCTAssertEqual(applied, ["b"], "missed intervals are not caught up one by one")
    }

    func testDayAndNightFollowTheClockButLeaveAManualChoiceAlone() async {
        store.update("primary") {
            $0.mode = .dayNight
            $0.dayWallpaperID = "b"
            $0.nightWallpaperID = "c"
        }
        let scheduler = makeScheduler()
        scheduler.start()
        defer { scheduler.stop() }
        await settle()
        XCTAssertEqual(applied, ["b"], "at noon the day wallpaper takes over")
        XCTAssertEqual(store.nextChange["primary"], calendar.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 19)))

        shown["primary"] = "a"
        scheduler.evaluate()
        await settle()
        XCTAssertEqual(applied, ["b"], "a wallpaper applied by hand stays until the next half of the day")

        clock = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 20))!
        scheduler.evaluate()
        await settle()
        XCTAssertEqual(applied, ["b", "c"])
        XCTAssertEqual(store.nextChange["primary"], calendar.date(from: DateComponents(year: 2027, month: 1, day: 16, hour: 7)))
    }

    func testChoosingADifferentDayWallpaperAppliesAtOnce() async {
        store.update("primary") {
            $0.mode = .dayNight
            $0.dayWallpaperID = "b"
        }
        let scheduler = makeScheduler()
        scheduler.start()
        defer { scheduler.stop() }
        await settle()
        store.update("primary") { $0.dayWallpaperID = "c" }
        scheduler.evaluate()
        await settle()
        XCTAssertEqual(applied, ["b", "c"])
    }

    func testSkipChangesARotatingDisplayNowAndRestartsItsInterval() async {
        let scheduler = makeScheduler()
        scheduler.start()
        defer { scheduler.stop() }
        XCTAssertFalse(scheduler.skip("primary"), "a display without a rotation leaves Next to the library order")

        store.update("primary") {
            $0.mode = .rotate
            $0.source = .list
            $0.wallpaperIDs = ["c", "a"]
            $0.interval = 60
        }
        XCTAssertTrue(scheduler.canSkip("primary"))
        XCTAssertTrue(scheduler.skip("primary"))
        await settle()
        XCTAssertEqual(applied, ["c"])
        XCTAssertEqual(store.nextChange["primary"], clock.addingTimeInterval(60 * 60))
        store.update("primary") { $0.wallpaperIDs = ["c"] }
        XCTAssertFalse(scheduler.canSkip("primary"), "the only wallpaper on the list is already showing")
    }

    func testNothingPlayableLeavesTheDisplayAsItIs() async {
        store.update("primary") {
            $0.mode = .rotate
            $0.source = .favorites
        }
        let scheduler = makeScheduler(favorites: ["gone"])
        scheduler.start()
        defer { scheduler.stop() }
        clock.addTimeInterval(60 * 60)
        scheduler.evaluate()
        await settle()
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(store.nextChange["primary"], clock.addingTimeInterval(30 * 60), "it tries again an interval later")
    }
}
