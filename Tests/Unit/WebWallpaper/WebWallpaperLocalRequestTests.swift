import WebKit
import XCTest

@testable import WallpaperMachine

/// Local loaders must see server-like success without turning missing files or
/// cancelled requests into successes. All fixtures are synthetic and offscreen.
@MainActor
final class WebWallpaperLocalRequestTests: XCTestCase {
  private var project: URL!

  override func setUpWithError() throws {
    project = FileManager.default.temporaryDirectory.appendingPathComponent(
      "web-local-request-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try #"{"answer":42}"#.write(
      to: project.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    try "".write(to: project.appendingPathComponent("empty.txt"), atomically: true, encoding: .utf8)
    try """
      <!doctype html><html><body><div id="stage">loading</div><script>
      const request = new XMLHttpRequest();
      request.open("GET", "settings.json", false);
      request.overrideMimeType("text/plain;charset=utf-8");
      request.send();
      if (request.status === 200) {
        document.getElementById("stage").textContent = JSON.parse(request.responseText).answer;
      }
      </script></body></html>
      """.write(to: project.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: project)
  }

  func testSynchronousStartupLoaderAdvancesPastLoading() async throws {
    let page = try await loadedPage()
    defer { page.stop() }
    let result = try await evaluate(page, """
      const empty = new XMLHttpRequest();
      empty.open('GET', 'empty.txt', false);
      empty.send();
      return {
        stage: document.getElementById('stage').textContent,
        status: empty.status, statusText: empty.statusText, body: empty.responseText,
        url: empty.responseURL.endsWith('/empty.txt')
      };
      """)
    XCTAssertEqual(result["stage"] as? String, "42")
    XCTAssertEqual(result["status"] as? Int, 200, "An empty successful response still succeeds")
    XCTAssertEqual(result["statusText"] as? String, "OK")
    XCTAssertEqual(result["body"] as? String, "")
    XCTAssertEqual(result["url"] as? Bool, true)
  }

  func testAsynchronousResponseMetadataIsAvailableInsideCallbacks() async throws {
    let page = try await loadedPage()
    defer { page.stop() }
    let result = try await evaluate(page, """
      return await new Promise(resolve => {
        const xhr = new XMLHttpRequest(), states = [], events = [];
        xhr.onreadystatechange = () => states.push([xhr.readyState, xhr.status, xhr.statusText]);
        xhr.onload = () => events.push('load');
        xhr.onerror = () => events.push('error');
        xhr.onloadend = () => resolve({states, events, answer: xhr.response?.answer,
          url: xhr.responseURL.endsWith('/settings.json')});
        xhr.open('GET', 'settings.json', true);
        xhr.responseType = 'json';
        xhr.send();
      });
      """)
    let states = try XCTUnwrap(result["states"] as? [[Any]])
    XCTAssertEqual(states.first?[0] as? Int, 1)
    XCTAssertEqual(states.first?[1] as? Int, 0, "Opening a request is not a successful response")
    XCTAssertEqual(states.last?[0] as? Int, 4)
    for state in states.dropFirst() {
      XCTAssertEqual(state[1] as? Int, 200, "Metadata must be visible before load: \(states)")
      XCTAssertEqual(state[2] as? String, "OK")
    }
    XCTAssertEqual(result["answer"] as? Int, 42, "Native JSON decoding must remain intact")
    XCTAssertEqual(result["url"] as? Bool, true)
    XCTAssertEqual(result["events"] as? [String], ["load"])
  }

  func testFailuresAbortAndReuseNeverInheritSuccessfulStatus() async throws {
    let page = try await loadedPage()
    defer { page.stop() }
    let result = try await evaluate(page, """
      const xhr = new XMLHttpRequest();
      const state = () => [xhr.status, xhr.statusText, xhr.responseURL];
      const unopened = state();
      xhr.open('GET', 'settings.json', false); xhr.send();
      const success = xhr.status;
      xhr.open('GET', 'missing.json', false);
      const reopened = state();
      try { xhr.send(); } catch (_) {}
      const missing = state();
      xhr.open('GET', 'settings.json', true); xhr.send(); xhr.abort();
      const aborted = state();
      const asyncMissing = await new Promise(resolve => {
        const failed = new XMLHttpRequest();
        failed.onloadend = () => resolve([failed.status, failed.statusText, failed.responseURL]);
        failed.open('GET', 'missing.json'); failed.send();
      });
      xhr.open('GET', 'settings.json', false); xhr.send();
      return {unopened, success, reopened, missing, aborted, asyncMissing, recovered: xhr.status};
      """)
    XCTAssertEqual(result["success"] as? Int, 200)
    XCTAssertEqual(result["recovered"] as? Int, 200)
    for key in ["unopened", "reopened", "missing", "aborted", "asyncMissing"] {
      let state = try XCTUnwrap(result[key] as? [Any])
      XCTAssertEqual(state[0] as? Int, 0, "\(key): \(state)")
      XCTAssertEqual(state[1] as? String, "", key)
      XCTAssertEqual(state[2] as? String, "", key)
    }
  }

  func testNonFileRequestsKeepNativeMetadataAndBinaryBodies() async throws {
    let page = try await loadedPage()
    defer { page.stop() }
    let result = try await evaluate(page, """
      const data = new XMLHttpRequest();
      data.open('GET', 'data:text/plain,hello', false); data.send();
      const bytes = await new Promise(resolve => {
        const file = new XMLHttpRequest();
        file.open('GET', 'settings.json'); file.responseType = 'arraybuffer';
        file.onloadend = () => resolve({status: file.status,
          text: new TextDecoder().decode(file.response)});
        file.send();
      });
      return {status: data.status, statusText: data.statusText, body: data.responseText,
        url: data.responseURL, bytes};
      """)
    XCTAssertEqual(result["status"] as? Int, 200)
    XCTAssertEqual(result["statusText"] as? String, "OK")
    XCTAssertEqual(result["body"] as? String, "hello")
    XCTAssertEqual(result["url"] as? String, "data:text/plain,hello")
    let bytes = try XCTUnwrap(result["bytes"] as? [String: Any])
    XCTAssertEqual(bytes["status"] as? Int, 200)
    XCTAssertEqual(bytes["text"] as? String, #"{"answer":42}"#)
  }

  private func loadedPage() async throws -> WebWallpaperPage {
    let page = WebWallpaperPage(projectURL: project, entryFile: "index.html")
    page.load()
    let deadline = Date().addingTimeInterval(10)
    while !page.isLoaded && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    XCTAssertTrue(page.isLoaded)
    XCTAssertNil(page.webView.window, "No desktop window is needed")
    return page
  }

  private func evaluate(_ page: WebWallpaperPage, _ script: String) async throws -> [String: Any] {
    let value = try await page.webView.callAsyncJavaScript(
      script, arguments: [:], in: nil, contentWorld: .page)
    return try XCTUnwrap(value as? [String: Any])
  }
}
