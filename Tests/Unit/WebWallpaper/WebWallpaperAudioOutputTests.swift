import WebKit
import XCTest

@testable import WallpaperMachine

@MainActor
final class WebWallpaperAudioOutputTests: XCTestCase {
    func testNativePageOutputMuteCanBeCleared() throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let muted = WebWallpaperAudioOutput.apply(volume: 0.4, muted: true, to: webView)
        guard muted.pageMute else { throw XCTSkip("This WebKit does not expose page output mute") }
        XCTAssertEqual(WebWallpaperAudioOutput.isMuted(webView), true)
        let restored = WebWallpaperAudioOutput.apply(volume: 0.4, muted: false, to: webView)
        XCTAssertTrue(restored.pageMute)
        XCTAssertEqual(WebWallpaperAudioOutput.isMuted(webView), false)
        XCTAssertNil(webView.window)
    }

    func testZeroVolumeMutesWebAudioAndRestoringGainRespectsExplicitMute() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let page = WebWallpaperPage(projectURL: project, entryFile: "index.html")
        page.applyAudioOutput(volume: 0, muted: false)
        guard page.audioOutputCapabilities?.pageMute == true else {
            throw XCTSkip("This WebKit does not expose page output mute")
        }
        XCTAssertEqual(WebWallpaperAudioOutput.isMuted(page.webView), true)
        page.applyAudioOutput(volume: 0.6, muted: true)
        XCTAssertEqual(WebWallpaperAudioOutput.isMuted(page.webView), true)
        page.applyAudioOutput(volume: 0.6, muted: false)
        XCTAssertEqual(WebWallpaperAudioOutput.isMuted(page.webView), false)
        page.stop()
    }
}
