import Darwin
import XCTest

@testable import WallpaperMachine

@MainActor
final class WallpaperImportPickerTests: XCTestCase {
    func testCancellationBeforeLaunchCannotStartAPickerLater() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("picker-start-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("started")
        let helper = WallpaperImportPicker.HelperProcess(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "touch \"$1\"", "picker-test", marker.path])
        helper.cancel()
        do {
            _ = try await helper.run { _ in }
            XCTFail("A cancelled presentation must not launch a picker")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCancellationReapsThePickerWaitingForASelection() async throws {
        let helper = WallpaperImportPicker.HelperProcess(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '\\001'; exec /bin/sleep 60"])
        defer { helper.cancel() }
        let ready = expectation(description: "Picker launched")
        var child: Int32 = 0
        let task = Task {
            try await helper.run { pid in
                child = pid
                ready.fulfill()
            }
        }
        await fulfillment(of: [ready], timeout: 5)
        helper.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must not report a selected file")
        } catch is CancellationError {}
        assertReaped(child)
    }

    func testActivationFailureDoesNotLeaveThePickerRunning() async throws {
        enum ActivationFailure: Error { case rejected }
        let helper = WallpaperImportPicker.HelperProcess(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '\\001'; exec /bin/sleep 60"])
        var child: Int32 = 0
        do {
            _ = try await helper.run { pid in
                child = pid
                throw ActivationFailure.rejected
            }
            XCTFail("A rejected activation must fail the presentation")
        } catch ActivationFailure.rejected {}
        assertReaped(child)
    }

    func testInvalidHandshakeFailsInsteadOfHangingOrReturningCancellation() async throws {
        let helper = WallpaperImportPicker.HelperProcess(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf invalid; exec /bin/sleep 60"])
        do {
            _ = try await helper.run { _ in }
            XCTFail("Unexpected output must not be treated as a user cancellation")
        } catch WallpaperImportPicker.Failure.unexpectedOutput {}
    }

    func testFailedExitAfterActivationIsNotAUserCancellation() async throws {
        let helper = WallpaperImportPicker.HelperProcess(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '\\001'; /bin/dd bs=1 count=1 of=/dev/null 2>/dev/null; exit 7"])
        do {
            _ = try await helper.run { _ in }
            XCTFail("A failed picker must not be reported as Cancel")
        } catch WallpaperImportPicker.Failure.exited(let status) {
            XCTAssertEqual(status, 7)
        }
    }

    private func assertReaped(_ pid: Int32, file: StaticString = #filePath, line: UInt = #line) {
        guard pid > 0 else { return XCTFail("The picker did not publish its PID", file: file, line: line) }
        let result = kill(pid, 0)
        let code = errno
        XCTAssertEqual(result, -1, "The picker must be gone, not just sent a signal", file: file, line: line)
        XCTAssertEqual(code, ESRCH, file: file, line: line)
    }
}
