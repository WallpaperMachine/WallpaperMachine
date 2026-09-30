import XCTest

@testable import WallpaperMachine

final class LockScreenExtensionDiagnosticsTests: XCTestCase {
  private var exchange: URL!
  private var bundle: URL { exchange.appendingPathComponent("WallpaperMachineExtension.appex") }

  override func setUpWithError() throws {
    exchange = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: exchange)
  }

  private func publish(_ json: String, revision: String = "current") throws {
    try Data(json.utf8).write(to: exchange.appendingPathComponent(LockScreenConfiguration.fileName))
    try JSONEncoder().encode(LockScreenExtensionRequest(revision: revision)).write(
      to: exchange.appendingPathComponent(LockScreenExtensionRequest.fileName))
  }

  private func load(supportedVersion: Int = LockScreenConfiguration.supportedVersion) throws -> LockScreenConfiguration {
    try LockScreenExtensionStatus.loadConfiguration(
      exchange: exchange, bundleURL: bundle, supportedVersion: supportedVersion,
      reportWriteFailure: { XCTFail("Could not report configuration failure: \($0)") })
  }

  private func status() throws -> LockScreenExtensionStatus {
    try JSONDecoder().decode(LockScreenExtensionStatus.self, from: Data(
      contentsOf: exchange.appendingPathComponent(LockScreenExtensionStatus.fileName)))
  }

  func testVersionMismatchIsReportedBeforeDecodingAnUnknownSceneSchema() throws {
    try publish(#"{"version":99,"revision":"current","scenes":"new schema"}"#)
    XCTAssertThrowsError(try load()) { error in
      guard case LockScreenExtensionStatus.ConfigurationError.unsupportedVersion(99) = error
      else { return XCTFail("Expected protocol mismatch, got \(error)") }
    }
    let report = try status()
    XCTAssertEqual(report.revision, "current")
    XCTAssertNotNil(report.error)
    XCTAssertEqual(report.bundlePath, bundle.resolvingSymlinksInPath().path)
  }

  func testMalformedAndMissingConfigurationReportAgainstTheRequest() throws {
    for json in ["{", #"{"version":2,"revision":"current","scenes":false}"#] {
      try publish(json)
      XCTAssertThrowsError(try load())
      XCTAssertEqual(try status().revision, "current")
      XCTAssertNotNil(try status().error)
    }
    try FileManager.default.removeItem(at: exchange.appendingPathComponent(LockScreenConfiguration.fileName))
    XCTAssertThrowsError(try load())
    XCTAssertEqual(try status().revision, "current")
    XCTAssertNotNil(try status().error)
  }

  func testPublicationTransitionDoesNotAttributeFailureToAnotherRevision() throws {
    try publish(#"{"version":99,"revision":"next","scenes":false}"#, revision: "previous")
    XCTAssertThrowsError(try load())
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: exchange.appendingPathComponent(LockScreenExtensionStatus.fileName).path))
  }

  func testSuccessfulRetryReplacesFailureWithoutClaimingFrameReadiness() throws {
    try publish("{")
    XCTAssertThrowsError(try load())
    let configuration = LockScreenConfiguration(revision: "retry", scenes: [])
    try publish(String(decoding: JSONEncoder().encode(configuration), as: UTF8.self), revision: "retry")
    XCTAssertEqual(try load(), configuration)
    XCTAssertNil(try status().error)
    XCTAssertEqual(try status().revision, "retry")
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: exchange.path)
      .contains { $0.hasPrefix("ready-") })
  }

  func testDiagnosticWriteFailureDoesNotPreventLoadingConfiguration() throws {
    let configuration = LockScreenConfiguration(revision: "current", scenes: [])
    try publish(String(decoding: JSONEncoder().encode(configuration), as: UTF8.self))
    try FileManager.default.createDirectory(
      at: exchange.appendingPathComponent(LockScreenExtensionStatus.fileName), withIntermediateDirectories: false)
    var writeError: Error?
    let loaded = try LockScreenExtensionStatus.loadConfiguration(
      exchange: exchange, bundleURL: bundle, reportWriteFailure: { writeError = $0 })
    XCTAssertEqual(loaded, configuration)
    XCTAssertNotNil(writeError)
  }

  func testOnlyCurrentMatchingExtensionIsAcceptedAndSymlinksAreResolved() throws {
    var report = LockScreenExtensionStatus(
      revision: "current", bundlePath: bundle.path,
      supportedVersion: LockScreenConfiguration.supportedVersion, error: nil)
    func failure() -> LockScreenWallpaperFailure? {
      LockScreenExtensionDiagnostics.failure(status: report, revision: "current", expectedBundle: bundle)
    }
    XCTAssertNil(failure())
    report.supportedVersion = 1
    XCTAssertNotNil(failure())
    report.supportedVersion = LockScreenConfiguration.supportedVersion
    report.bundlePath = exchange.appendingPathComponent("old.appex").path
    XCTAssertNotNil(failure())
    report.revision = "stale"
    report.error = "old failure"
    XCTAssertNil(failure())
    report.revision = "current"
    report.error = nil
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: false)
    let alias = exchange.appendingPathComponent("alias.appex")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: bundle)
    report.bundlePath = alias.path
    XCTAssertNil(failure())
    report.error = "configuration unreadable"
    XCTAssertNotNil(failure())
  }
}
