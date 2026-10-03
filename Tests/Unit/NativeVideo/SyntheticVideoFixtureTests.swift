import AVFoundation
import XCTest

final class SyntheticVideoFixtureTests: XCTestCase {
    func testReadyInputContinuesImmediately() async throws {
        try await SyntheticVideoFixture.waitUntilReady(isReady: { true }, status: { .writing }, timeout: .zero)
    }

    func testFailedWriterStopsWaitingWithItsError() async {
        do {
            try await SyntheticVideoFixture.waitUntilReady(isReady: { false }, status: { .failed }, failure: { "fixture failure" })
            XCTFail("A failed writer cannot become ready")
        } catch SyntheticVideoFixture.FixtureError.writerFailed(let detail) {
            XCTAssertEqual(detail, "fixture failure")
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testInputThatNeverBecomesReadyReachesItsDeadline() async {
        do {
            try await SyntheticVideoFixture.waitUntilReady(isReady: { false }, status: { .writing }, timeout: .zero)
            XCTFail("An unready input must time out")
        } catch SyntheticVideoFixture.FixtureError.inputTimedOut {
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}
