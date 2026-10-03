import Darwin
import XCTest

@testable import WallpaperMachine

/// Reading `file` and `directory` properties out of the bridge's
/// `applyUserProperties` payload, and rewriting a `file` value to the staged
/// path the page is allowed to load. Optional keys are genuinely optional: an
/// author may declare no file-type option and no directory mode.
@MainActor
final class WebWallpaperPropertyPayloadTests: XCTestCase {
  private let payload = """
    {
      "scheme": { "value": "dark", "type": "combo" },
      "cover": { "value": "/Users/x/Pictures/a b+c.png", "type": "file", "fileFilter": "image" },
      "clip": { "value": "", "type": "file" },
      "gallery": { "value": "/Users/x/Pictures", "type": "directory", "mode": "fetchall", "fileFilter": "image" },
      "picks": { "value": "/Users/x/Movies", "type": "directory", "mode": "ondemand" },
      "loose": { "value": "/Users/x/Any", "type": "directory" },
      "surface": { "value": "materials/x.tex", "type": "texture" },
      "odd": { "value": "1", "type": "hologram" },
      "broken": "not an object"
    }
    """

  func testOnlyFileAndDirectoryPropertiesAreTreatedAsPaths() {
    let properties = WebWallpaperHost.pathProperties(in: payload)
    XCTAssertEqual(
      properties.map(\.id), ["clip", "cover", "gallery", "loose", "picks"],
      "a texture picker has no directory semantics and an unknown kind is not a path")
  }

  func testAnAbsentFileFilterRestrictsNothingRatherThanMeaningImages() {
    let properties = WebWallpaperHost.pathProperties(in: payload)
    XCTAssertEqual(properties.first { $0.id == "cover" }?.filter, .image)
    XCTAssertEqual(
      properties.first { $0.id == "clip" }?.filter, .any,
      "the author declared no file-type option, which is not the same as declaring images")
  }

  func testDirectoryModeDefaultsToOnDemand() {
    let properties = WebWallpaperHost.pathProperties(in: payload)
    XCTAssertEqual(properties.first { $0.id == "gallery" }?.fetchAll, true)
    XCTAssertEqual(properties.first { $0.id == "picks" }?.fetchAll, false)
    XCTAssertEqual(
      properties.first { $0.id == "loose" }?.fetchAll, false,
      "a directory with no declared mode is ondemand")
  }

  func testAnUnsetPropertyHasNoSourcePath() {
    let properties = WebWallpaperHost.pathProperties(in: payload)
    XCTAssertEqual(properties.first { $0.id == "cover" }?.source, "/Users/x/Pictures/a b+c.png")
    XCTAssertEqual(properties.first { $0.id == "clip" }?.source, "")
  }

  func testSubstitutionRewritesOnlyTheNamedValues() async throws {
    let rewritten = try XCTUnwrap(
      WebWallpaperHost.substituting(
        ["cover": "Users/x/staged/a b+c.png", "clip": ""], in: payload))
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: XCTUnwrap(rewritten.data(using: .utf8)))
        as? [String: Any])

    let cover = try XCTUnwrap(root["cover"] as? [String: Any])
    XCTAssertEqual(cover["value"] as? String, "Users/x/staged/a b+c.png")
    XCTAssertEqual(cover["type"] as? String, "file", "the kind must survive the rewrite")
    XCTAssertEqual(cover["fileFilter"] as? String, "image")
    XCTAssertEqual(
      (root["gallery"] as? [String: Any])?["value"] as? String, "/Users/x/Pictures",
      "a directory value stays the user's own path; the page only uses it to detect 'not set'")
    XCTAssertEqual((root["scheme"] as? [String: Any])?["value"] as? String, "dark")
    XCTAssertEqual(root["broken"] as? String, "not an object")
  }

  func testAMalformedPayloadYieldsNothingRatherThanThrowing() {
    XCTAssertTrue(WebWallpaperHost.pathProperties(in: "not json").isEmpty)
    XCTAssertTrue(WebWallpaperHost.pathProperties(in: "[]").isEmpty)
    XCTAssertNil(WebWallpaperHost.substituting(["a": "b"], in: "[]"))
  }

  // MARK: - staging

  /// A page may only read inside its own project folder, so a `file` property
  /// has to reach it as a staged path under the project rather than as the
  /// path the user picked.
  func testAFilePropertyIsStagedIntoTheProjectAndRewrittenForThePage() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let host = WebWallpaperHost(
      fetch: { [] }, screens: { [] },
      assetStore: { UserAssetStore(projectURL: $0, wallpaperId: $1) })

    let staged = await host.stageAssets(for: fixture.wallpaper)
    XCTAssertTrue(staged.restaged)
    let root = try Fixture.object(staged.json)
    let cover = try XCTUnwrap((root["cover"] as? [String: Any])?["value"] as? String)
    XCTAssertFalse(cover.hasPrefix("/"), "the page prepends file:///, so the value carries no leading slash")
    let stagedPath = "/" + cover.replacingOccurrences(of: "%25", with: "%")
    XCTAssertTrue(
      stagedPath.hasPrefix(fixture.project.standardizedFileURL.path),
      "the staged file must be inside the folder WebKit grants the page")
    XCTAssertTrue(FileManager.default.fileExists(atPath: stagedPath))
    XCTAssertEqual(
      (root["gallery"] as? [String: Any])?["value"] as? String, fixture.source.path,
      "a directory value stays the user's own path; the page only uses it to detect 'not set'")
  }

  func testAnUnchangedSelectionIsNotStagedAgain() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let host = WebWallpaperHost(
      fetch: { [] }, screens: { [] },
      assetStore: { UserAssetStore(projectURL: $0, wallpaperId: $1) })
    let first = await host.stageAssets(for: fixture.wallpaper)
    let second = await host.stageAssets(for: fixture.wallpaper)
    XCTAssertFalse(second.restaged, "re-linking a whole folder on every reconcile is not free")
    XCTAssertEqual(second.json, first.json)
  }

  func testClearingASelectionReachesThePageAsAnEmptyValue() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let host = WebWallpaperHost(
      fetch: { [] }, screens: { [] },
      assetStore: { UserAssetStore(projectURL: $0, wallpaperId: $1) })
    _ = await host.stageAssets(for: fixture.wallpaper)

    var cleared = fixture.wallpaper
    cleared.propertiesJson = """
      {
        "cover": { "value": "", "type": "file", "fileFilter": "image" },
        "gallery": { "value": "", "type": "directory", "mode": "fetchall", "fileFilter": "image" }
      }
      """
    let staged = await host.stageAssets(for: cleared)
    XCTAssertTrue(staged.restaged)
    let root = try Fixture.object(staged.json)
    XCTAssertEqual((root["cover"] as? [String: Any])?["value"] as? String, "")
  }

  func testExplicitReselectionOfTheSamePathRestagesChangedBytes() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let host = WebWallpaperHost(fetch: { [] }, screens: { [] },
      assetStore: { UserAssetStore(projectURL: $0, wallpaperId: $1) })
    defer { host.shutdown() }
    let first = await host.stageAssets(for: fixture.wallpaper)
    let root = try Fixture.object(first.json)
    let pagePath = try XCTUnwrap((root["cover"] as? [String: Any])?["value"] as? String)
    let source = try XCTUnwrap(WebWallpaperHost.pathProperties(in: fixture.wallpaper.propertiesJson)
      .first { $0.id == "cover" }?.source)
    let bytes = Data("same path with new content".utf8)
    try bytes.write(to: URL(fileURLWithPath: source), options: .atomic)
    host.invalidateAsset(wallpaperID: fixture.wallpaper.wallpaperId, propertyID: "cover")
    let second = await host.stageAssets(for: fixture.wallpaper)
    XCTAssertTrue(second.restaged)
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: "/" + pagePath.replacingOccurrences(of: "%25", with: "%"))), bytes)
    let unchanged = await host.stageAssets(for: fixture.wallpaper)
    XCTAssertFalse(unchanged.restaged)
  }

  func testStagingFixtureRestoresTheCallersHomeIncludingSetupFailure() async throws {
    let previous = ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_HOME"]
    defer {
      if let previous { setenv("WALLPAPER_MACHINE_HOME", previous, 1) }
      else { unsetenv("WALLPAPER_MACHINE_HOME") }
    }
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("caller-home-\(UUID().uuidString)")
    setenv("WALLPAPER_MACHINE_HOME", marker.path, 1)
    let fixture = try Fixture()
    fixture.remove()
    XCTAssertEqual(ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_HOME"], marker.path)

    let file = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-directory-\(UUID().uuidString)")
    try Data("fixture setup must fail".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    XCTAssertThrowsError(try Fixture(base: file))
    XCTAssertEqual(ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_HOME"], marker.path)
  }

  /// A project folder and a separate folder of the user's own files, the way a
  /// real selection arrives: the source is never inside the project.
  private struct Fixture {
    let home: URL
    let project: URL
    let source: URL
    let wallpaper: BridgeWebWallpaper
    let previousHome: String?

    init(base: URL = FileManager.default.temporaryDirectory) throws {
      previousHome = ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_HOME"]
      home = base.appendingPathComponent("web-home-\(UUID().uuidString)", isDirectory: true)
      project = base.appendingPathComponent("web-staging-\(UUID().uuidString)", isDirectory: true)
      source = base.appendingPathComponent("web-source-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
      let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      // A name with a space and a plus: both load unescaped and must survive.
      try png.write(to: source.appendingPathComponent("a b+c.png"))
      try png.write(to: source.appendingPathComponent("second.png"))
      wallpaper = BridgeWebWallpaper(
        displayId: 1, startupRevision: 0, displayKey: "1", audioSourceDisplayId: 1,
        wallpaperId: "w", title: "Test", projectPath: project.path,
        entryFile: "index.html", fps: 30, paused: false, volume: 1, muted: false,
        audioResponseEnabled: false,
        mediaIntegrationEnabled: false,
        propertiesJson: """
          {
            "cover": {
              "value": "\(source.appendingPathComponent("a b+c.png").path)",
              "type": "file", "fileFilter": "image"
            },
            "gallery": { "value": "\(source.path)", "type": "directory", "mode": "fetchall" }
          }
          """)
      // Change process state only once every throwing setup operation succeeded.
      setenv("WALLPAPER_MACHINE_HOME", home.path, 1)
    }

    func remove() {
      if let previousHome { setenv("WALLPAPER_MACHINE_HOME", previousHome, 1) }
      else { unsetenv("WALLPAPER_MACHINE_HOME") }
      try? FileManager.default.removeItem(at: home)
      try? FileManager.default.removeItem(at: project)
      try? FileManager.default.removeItem(at: source)
    }

    static func object(_ json: String) throws -> [String: Any] {
      try XCTUnwrap(
        try JSONSerialization.jsonObject(with: XCTUnwrap(json.data(using: .utf8)))
          as? [String: Any])
    }
  }
}
