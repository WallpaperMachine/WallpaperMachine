import XCTest

@testable import WallpaperMachine

/// Every fixed address the bundled panel asks `openExternal` to open must pass the native
/// allowlist; one that does not fails with "This control sent an invalid value".
@MainActor
final class WebPanelExternalLinkTests: XCTestCase {
  func testEveryFixedLinkThePanelOpensPassesTheAllowlist() throws {
    let folder = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("WebUI", isDirectory: true))
    let scripts = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "js" }
    XCTAssertFalse(scripts.isEmpty, "the panel's scripts are bundled")
    // `'openExternal', { url: 'https://…' }`, and the `*_URL` constants such links are built from.
    let pattern = try NSRegularExpression(
      pattern: #"(?:'openExternal',\s*\{\s*url:\s*|const [A-Z_]+_URL\s*=\s*)'(https://[^'$]+)'"#)
    var links: [String] = []
    for script in scripts {
      let source = try String(contentsOf: script, encoding: .utf8)
      for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
        if let range = Range(match.range(at: 1), in: source) { links.append(String(source[range])) }
      }
    }
    XCTAssertTrue(links.contains { $0.contains("help.steampowered.com") }, "the emailed-code help link is found")
    for link in links {
      let url = try XCTUnwrap(URL(string: link), link)
      XCTAssertTrue(WebPanelController.allowedExternalURL(url), "\(link) must pass the external allowlist")
    }
  }
}
