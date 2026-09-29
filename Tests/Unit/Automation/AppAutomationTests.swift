import XCTest
@testable import WallpaperMachine

@MainActor
final class AppAutomationTests: XCTestCase {
    func testACommandWaitsForTheAppToBeReady() async throws {
        let automation = AppAutomation(wait: .seconds(5), poll: .milliseconds(5))
        var received: [AutomationCommand] = []
        Task { @MainActor in
            try await Task.sleep(for: .milliseconds(30))
            automation.handler = { received.append($0) }
        }
        try await automation.perform(.pause)
        XCTAssertEqual(received, [.pause])
    }

    func testACommandThatOutwaitsTheStartSaysSo() async {
        let automation = AppAutomation(wait: .milliseconds(30), poll: .milliseconds(5))
        do {
            try await automation.perform(.play)
            XCTFail("no handler ever arrived")
        } catch {
            XCTAssertEqual(error as? AutomationError, .notReady)
        }
    }

    func testTheHandlersFailureReachesTheCaller() async {
        let automation = AppAutomation(wait: .milliseconds(30), poll: .milliseconds(5))
        automation.handler = { _ in throw AutomationError(message: "no such wallpaper") }
        do {
            try await automation.perform(.apply(wallpaperID: "gone", display: nil))
            XCTFail("the failure must not be swallowed")
        } catch {
            XCTAssertEqual((error as? AutomationError)?.message, "no such wallpaper")
        }
    }
}
