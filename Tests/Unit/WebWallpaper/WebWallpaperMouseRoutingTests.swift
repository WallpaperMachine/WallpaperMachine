import AppKit
import XCTest

@testable import WallpaperMachine

/// The routing policy decides whether an observed desktop pointer event
/// belongs to a web wallpaper page. Window numbers stand in for AppKit windows.
final class WebWallpaperMouseRoutingTests: XCTestCase {
  private let wallpaper = 100
  private let finderDesktop = 10
  private let appWindow = 50
  private var layers: [Int: Int] = [:]

  override func setUp() {
    layers = [10: Int(CGWindowLevelForKey(.desktopIconWindow)), 50: 0]
  }

  private func route(
    _ routing: inout WebWallpaperMouseRouting, _ kind: WebWallpaperMouseRouting.Kind,
    over wallpaper: Int? = 100, front: Int
  ) -> WebWallpaperMouseRouting.Decision {
    routing.route(kind, wallpaperWindow: wallpaper, frontWindow: front) { self.layers[$0] }
  }

  func testEventsOverTheDesktopReachTheWallpaperUnderThePointer() {
    var routing = WebWallpaperMouseRouting()
    XCTAssertEqual(route(&routing, .move, front: finderDesktop), .deliver(to: wallpaper))
    XCTAssertEqual(route(&routing, .scroll, front: finderDesktop), .deliver(to: wallpaper))
    XCTAssertEqual(route(&routing, .down(button: 0), front: wallpaper), .deliver(to: wallpaper),
      "A wallpaper window reported as frontmost needs no layer lookup")
    XCTAssertEqual(route(&routing, .up(button: 0), front: wallpaper), .deliver(to: wallpaper))
  }

  func testApplicationWindowsAndUnknownWindowsShieldTheWallpaper() {
    var routing = WebWallpaperMouseRouting()
    XCTAssertEqual(route(&routing, .down(button: 0), front: appWindow), .ignore)
    XCTAssertEqual(route(&routing, .up(button: 0), front: appWindow), .ignore,
      "A release without a forwarded press is not a click")
    XCTAssertEqual(route(&routing, .scroll, front: 999), .ignore, "unknown layer is not the desktop")
    XCTAssertEqual(route(&routing, .move, over: nil, front: finderDesktop), .ignore,
      "no wallpaper under the pointer")
  }

  func testForwardedPressKeepsItsDragAndReleaseOverOtherWindows() {
    var routing = WebWallpaperMouseRouting()
    XCTAssertEqual(route(&routing, .down(button: 0), front: finderDesktop), .deliver(to: wallpaper))
    XCTAssertTrue(routing.isPressed)
    XCTAssertEqual(route(&routing, .drag(button: 0), over: nil, front: appWindow), .deliver(to: wallpaper))
    XCTAssertEqual(route(&routing, .up(button: 0), over: nil, front: appWindow), .deliver(to: wallpaper))
    XCTAssertFalse(routing.isPressed)
    XCTAssertEqual(route(&routing, .drag(button: 0), front: finderDesktop), .ignore,
      "drags after the release are stale")
    // Buttons are tracked independently.
    XCTAssertEqual(route(&routing, .down(button: 1), front: finderDesktop), .deliver(to: wallpaper))
    XCTAssertEqual(route(&routing, .up(button: 0), front: finderDesktop), .ignore)
    XCTAssertEqual(route(&routing, .up(button: 1), front: appWindow), .deliver(to: wallpaper))
  }

  func testHoverExitsOnceWhenThePointerLeavesTheDesktop() {
    var routing = WebWallpaperMouseRouting()
    XCTAssertEqual(route(&routing, .move, front: finderDesktop), .deliver(to: wallpaper))
    XCTAssertEqual(route(&routing, .move, front: appWindow), .exit(wallpaper))
    XCTAssertEqual(route(&routing, .move, front: appWindow), .ignore, "exit fires only once")
    XCTAssertEqual(route(&routing, .scroll, front: appWindow), .ignore)
    XCTAssertEqual(route(&routing, .move, front: finderDesktop), .deliver(to: wallpaper))
    XCTAssertEqual(route(&routing, .move, over: 200, front: finderDesktop), .exitThenDeliver(exit: wallpaper, to: 200),
      "crossing to another display's wallpaper exits the previous page")
    routing.reset()
    XCTAssertEqual(route(&routing, .move, front: appWindow), .ignore)
  }

  // MARK: - front window

  private func event(_ type: CGEventType, under window: Int64?) throws -> NSEvent {
    let cgEvent = try XCTUnwrap(
      type == .scrollWheel
        ? CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)
        : CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: .left))
    if let window { cgEvent.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: window) }
    return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
  }

  // A scroll-wheel event does not keep a mouse-event field set on it, so scrolls
  // are covered by the fallback below.
  func testTheWindowRecordedInTheEventIsUsedWithoutAskingTheWindowServer() throws {
    for (type, kind) in [
      (CGEventType.mouseMoved, WebWallpaperMouseRouting.Kind.move), (.leftMouseDown, .down(button: 0)),
      (.leftMouseDragged, .drag(button: 0)), (.leftMouseUp, .up(button: 0)),
    ] {
      var asked = false
      let front = WebWallpaperMouseForwarder.frontWindow(of: try event(type, under: 41), kind: kind) {
        asked = true
        return 7
      }
      XCTAssertEqual(front, 41, "\(kind)")
      XCTAssertFalse(asked, "\(kind) must not block on a window-server query")
    }
  }

  func testOnlyAPressOrScrollWithoutARecordedWindowAsksTheWindowServer() throws {
    var asked = 0
    let hitTest = { asked += 1; return 7 }
    XCTAssertNil(
      WebWallpaperMouseForwarder.frontWindow(of: try event(.mouseMoved, under: nil), kind: .move, hitTest: hitTest),
      "a move without a window is dropped; the next move corrects hover")
    XCTAssertEqual(
      WebWallpaperMouseForwarder.frontWindow(
        of: try event(.leftMouseDragged, under: nil), kind: .drag(button: 0), hitTest: hitTest), 0)
    XCTAssertEqual(
      WebWallpaperMouseForwarder.frontWindow(of: try event(.leftMouseUp, under: nil), kind: .up(button: 0), hitTest: hitTest),
      0)
    XCTAssertEqual(asked, 0, "moves, drags and releases never query")
    XCTAssertEqual(
      WebWallpaperMouseForwarder.frontWindow(
        of: try event(.leftMouseDown, under: nil), kind: .down(button: 0), hitTest: hitTest), 7)
    XCTAssertEqual(
      WebWallpaperMouseForwarder.frontWindow(of: try event(.scrollWheel, under: nil), kind: .scroll, hitTest: hitTest), 7)
    XCTAssertEqual(asked, 2)
  }
}
