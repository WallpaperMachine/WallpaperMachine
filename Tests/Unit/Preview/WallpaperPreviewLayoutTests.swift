import AppKit
import XCTest
@testable import WallpaperMachine

@MainActor
final class WallpaperPreviewLayoutTests: XCTestCase {
    func testMinimumWidthKeepsLocalizedControlsAndFailureTextInSeparateRows() async throws {
        let reason = String(repeating: "A preview resource could not load. Reload the preview. ", count: 4)
        let session = WallpaperPreviewSession(load: { _ in throw WallpaperPreviewFailure(message: reason) }, makeSurface: { _, _ in
            throw WallpaperPreviewFailure(message: "A failed load must not create a surface")
        })
        let controller = WallpaperPreviewWindowController(session: session)
        let root = controller.makeContentView(size: CGSize(width: 480, height: 320))
        XCTAssertNil(root.window)
        session.open(.init(wallpaperID: "fixture", displayID: "primary"))
        for _ in 0..<40 { await Task.yield() }
        XCTAssertEqual(session.phase, .failed(reason))
        let controls = try XCTUnwrap(root.subviews.compactMap { $0 as? NSStackView }.first)
        let buttons = controls.arrangedSubviews.compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 3)
        let status = try XCTUnwrap(root.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "preview-status" })
        for titles in [["Pause", "Unmute", "Reload preview"], ["暂停", "取消静音", "重新载入预览"], ["一時停止", "消音を解除", "プレビューを再読み込み"]] {
            for (button, title) in zip(buttons, titles) { button.title = title }
            root.layoutSubtreeIfNeeded()
            for button in buttons {
                let rect = button.convert(button.bounds, to: root)
                XCTAssertGreaterThanOrEqual(rect.minX, 0)
                XCTAssertLessThanOrEqual(rect.maxX, root.bounds.width)
                XCTAssertGreaterThanOrEqual(rect.width + 1, button.intrinsicContentSize.width)
            }
            XCTAssertGreaterThan(status.frame.width, 400)
            XCTAssertLessThanOrEqual(status.frame.maxY, controls.frame.minY)
            XCTAssertEqual(status.toolTip, reason, "the complete diagnostic remains available even when its visible lines are capped")
            XCTAssertTrue(status.isSelectable)
        }
        session.close()
    }
}
