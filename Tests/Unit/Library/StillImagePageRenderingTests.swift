import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit
import XCTest
@testable import WallpaperMachine

/// Real generated page/property delivery, without a desktop window or image readback.
@MainActor
final class StillImagePageRenderingTests: XCTestCase {
    private var project: URL!

    override func setUpWithError() throws {
        project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8,
            bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: project.appendingPathComponent("image.png"))
        try StillImageWallpaper.page(showing: "image.png", fit: .fillTop)
            .write(to: project.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: project)
        project = nil
    }

    func testLivePlacementUsesFitAwareGeometryAndResetRestoresAuthorFitWithoutReload() async throws {
        let page = WebWallpaperPage(projectURL: project, entryFile: "index.html")
        page.webView.setFrameSize(NSSize(width: 100, height: 100))
        let placement = try StillImagePlacement(x: 1, y: 0, zoom: 2)
        let properties = #"{"fit":{"value":"fill-top"},"background":{"value":"0.1 0.2 0.3"}}"#
        page.applyUserProperties(json: try StillImagePlacement.merging(properties, placement: placement))
        page.load()
        let filled = try await state(page, until: { ($0["width"] as? Double) == 400 })
        XCTAssertEqual(filled["left"] as? Double, -300)
        XCTAssertEqual(filled["top"] as? Double, 0)
        XCTAssertEqual(filled["height"] as? Double, 200)
        XCTAssertEqual(filled["background"] as? String, "rgb(26, 51, 77)")
        _ = try await page.webView.callAsyncJavaScript("window.__placementDocument = 123", arguments: [:], in: nil, contentWorld: .page)

        let fit = #"{"fit":{"value":"fit"},"background":{"value":"0.1 0.2 0.3"}}"#
        page.applyUserProperties(json: try StillImagePlacement.merging(fit, placement: placement))
        let contained = try await state(page, until: { ($0["width"] as? Double) == 200 })
        XCTAssertEqual(contained["left"] as? Double, -100)
        XCTAssertEqual(contained["height"] as? Double, 100)

        page.applyUserProperties(json: try StillImagePlacement.merging(properties, placement: nil))
        let reset = try await state(page, until: { ($0["objectFit"] as? String) == "cover" })
        XCTAssertEqual(reset["width"] as? Double, 100)
        XCTAssertEqual(reset["height"] as? Double, 100)
        XCTAssertEqual(reset["marker"] as? Int, 123, "drag/reset must keep the existing document")
        XCTAssertEqual(reset["background"] as? String, "rgb(26, 51, 77)")
        XCTAssertNil(page.webView.window)
    }

    private func state(_ page: WebWallpaperPage, until condition: ([String: Any]) -> Bool) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(10)
        var last: [String: Any] = [:]
        while Date() < deadline {
            if page.isLoaded,
               let value = try? await page.webView.callAsyncJavaScript("""
               const art = document.getElementById('art');
               if (!art.naturalWidth) return {};
               const box = art.getBoundingClientRect(), style = getComputedStyle(art);
               return {left:box.left,top:box.top,width:box.width,height:box.height,
                 objectFit:style.objectFit,objectPosition:style.objectPosition,
                 background:getComputedStyle(document.body).backgroundColor,
                 marker:window.__placementDocument ?? null};
               """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] {
                last = value
                if condition(value) { return value }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Generated image page did not reach expected placement: \(last)")
        return last
    }
}
