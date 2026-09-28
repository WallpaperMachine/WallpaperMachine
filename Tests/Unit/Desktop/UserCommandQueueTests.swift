import XCTest
@testable import WallpaperMachine

/// A command given while another runs must wait its turn, never fail for being early; and
/// only the latest of several waiting switches is carried out.
@MainActor
final class UserCommandQueueTests: XCTestCase {
    func testCommandsGivenWhileBusyRunInArrivalOrder() async throws {
        let queue = UserCommandQueue()
        let log = Log()
        let gate = Gate()
        let first = Task { try await queue.run { log.add("first"); await gate.wait(); log.add("first done") } }
        await until { queue.isBusy }
        let second = Task { try await queue.run { log.add("second") } }
        await until { queue.waiting.count == 1 }
        let third = Task { try await queue.run { log.add("third") } }
        await until { queue.waiting.count == 2 }
        XCTAssertEqual(log.entries, ["first"], "Nothing may start while a command runs")

        gate.open()
        let ran = try await [first.value, second.value, third.value]

        XCTAssertEqual(ran, [true, true, true])
        XCTAssertEqual(log.entries, ["first", "first done", "second", "third"])
        XCTAssertFalse(queue.isBusy)
    }

    func testNewerCommandInSameSlotReplacesOneStillWaiting() async throws {
        let queue = UserCommandQueue()
        let log = Log()
        let gate = Gate()
        let running = Task { try await queue.run(slot: "activate:1", subject: "a") { await gate.wait(); log.add("a") } }
        await until { queue.isBusy }
        let replaced = Task { try await queue.run(slot: "activate:1", subject: "b") { log.add("b") } }
        await until { queue.waiting.count == 1 }
        let other = Task { try await queue.run(slot: "activate:2", subject: "x") { log.add("x") } }
        await until { queue.waiting.count == 2 }
        let latest = Task { try await queue.run(slot: "activate:1", subject: "c") { log.add("c") } }
        await until { queue.waiting.map(\.subject) == ["x", "c"] }

        let replacedRan = try await replaced.value
        XCTAssertFalse(replacedRan, "A replaced switch reports that it did not run, without an error")
        gate.open()
        let ran = try await [running.value, other.value, latest.value]

        XCTAssertEqual(ran, [true, true, true])
        XCTAssertEqual(log.entries, ["a", "x", "c"],
                       "The running switch finishes; another display's switch keeps its place; the latest joins the back")
    }

    func testFailedCommandStillHandsOverToTheNext() async throws {
        let queue = UserCommandQueue()
        let log = Log()
        let gate = Gate()
        let failing = Task {
            try await queue.run {
                await gate.wait()
                throw WallpaperActionError(message: "boom")
            }
        }
        await until { queue.isBusy }
        let next = Task { try await queue.run { log.add("next") } }
        await until { queue.waiting.count == 1 }

        gate.open()
        do {
            _ = try await failing.value
            XCTFail("The failure belongs to the command that failed")
        } catch {}
        _ = try await next.value

        XCTAssertEqual(log.entries, ["next"])
        XCTAssertFalse(queue.isBusy)
    }
}

@MainActor
private final class Log {
    private(set) var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}

@MainActor
private final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }
}

/// Lets other main-actor tasks run until `condition` holds; fails the test if it never does.
@MainActor
private func until(
    _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line
) async {
    for _ in 0..<1_000 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("Condition never became true", file: file, line: line)
}
