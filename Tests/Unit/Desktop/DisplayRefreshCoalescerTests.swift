import CoreGraphics
import XCTest
@testable import WallpaperMachine

@MainActor
final class DisplayRefreshCoalescerTests: XCTestCase {
    /// A display waking can post dozens of screen changes in a second. Each
    /// refresh used to queue behind the last in the bridge, and the resume
    /// after an unlock waited behind all of them.
    func testABurstDuringARefreshIsAnsweredByOneMoreRefresh() async throws {
        var displays = Self.configuration(width: 1728)
        var runs = 0
        var held: [CheckedContinuation<Void, Never>] = []
        let coalescer = DisplayRefreshCoalescer(configuration: { displays }) {
            runs += 1
            await withCheckedContinuation { held.append($0) }
            return true
        }

        coalescer.request()
        try await waitUntil { held.count == 1 }
        displays = Self.configuration(width: 1512)
        for _ in 0..<50 { coalescer.request() }
        XCTAssertEqual(runs, 1, "a change during a refresh must not start another one alongside it")

        held.removeFirst().resume()
        try await waitUntil { held.count == 1 }
        XCTAssertEqual(runs, 2, "the burst is answered by exactly one more refresh")

        held.removeFirst().resume()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(runs, 2, "nothing arrived during the second refresh, so there is no third")
    }

    func testAChangeAfterTheLastRefreshFinishedRefreshesAgain() async throws {
        var displays = Self.configuration(width: 1728)
        var runs = 0
        let coalescer = DisplayRefreshCoalescer(configuration: { displays }) {
            runs += 1
            return true
        }

        coalescer.request()
        try await waitUntil { runs == 1 }
        displays = Self.configuration(width: 1728, refreshRate: 60)
        coalescer.request()
        try await waitUntil { runs == 2 }
    }

    /// An XDR display posts a screen change for every frame of an EDR headroom
    /// ramp, about 240 in two seconds, with every display exactly as it was.
    /// Refreshing for each held the app and the control panel near a full core
    /// for the whole ramp.
    func testScreenChangesThatLeaveTheDisplaysAsTheyWereDoNotRefresh() async throws {
        let displays = Self.configuration(width: 1728)
        var runs = 0
        let coalescer = DisplayRefreshCoalescer(configuration: { displays }) {
            runs += 1
            return true
        }

        coalescer.request()
        try await waitUntil { runs == 1 }
        for _ in 0..<240 {
            coalescer.request()
            await Task.yield()
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(runs, 1)
    }

    func testAnUnchangedBurstDuringARefreshEndsWithIt() async throws {
        var runs = 0
        var held: [CheckedContinuation<Void, Never>] = []
        let coalescer = DisplayRefreshCoalescer(configuration: { Self.configuration(width: 1728) }) {
            runs += 1
            await withCheckedContinuation { held.append($0) }
            return true
        }

        coalescer.request()
        try await waitUntil { held.count == 1 }
        for _ in 0..<50 { coalescer.request() }
        held.removeFirst().resume()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(runs, 1, "the displays the burst left are the ones the running refresh read")
    }

    func testAFailedRefreshIsRetriedOnTheNextChangeWithTheSameDisplays() async throws {
        var runs = 0
        var succeeds = false
        let coalescer = DisplayRefreshCoalescer(configuration: { Self.configuration(width: 1728) }) {
            runs += 1
            return succeeds
        }

        coalescer.request()
        try await waitUntil { runs == 1 }
        succeeds = true
        coalescer.request()
        try await waitUntil { runs == 2 }
        coalescer.request()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(runs, 2, "once one succeeds, the same displays are left alone")
    }

    /// The filter is only as good as the reading: anything in it that moves
    /// without the displays changing, as EDR headroom does, brings every
    /// refresh back.
    func testTwoReadingsOfTheSameDisplaysAreEqual() {
        XCTAssertEqual(DisplayConfiguration.current(), DisplayConfiguration.current())
    }

    private static func configuration(width: CGFloat, refreshRate: Int = 120) -> DisplayConfiguration {
        DisplayConfiguration(displays: [
            .init(id: 1, frame: CGRect(x: 0, y: 0, width: width, height: 1117), scale: 2, refreshRate: refreshRate)
        ])
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw TestFailure.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private enum TestFailure: Error { case timeout }
}
