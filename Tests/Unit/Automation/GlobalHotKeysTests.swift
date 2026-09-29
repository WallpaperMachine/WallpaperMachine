import Carbon
import XCTest
@testable import WallpaperMachine

@MainActor
final class GlobalHotKeysTests: XCTestCase {
    func testAShortcutNeedsAModifierUnlessItsKeyTypesNothing() {
        XCTAssertThrowsError(try GlobalHotKeys.hotKey(code: "KeyP", command: false, option: false, control: false, shift: true))
        XCTAssertNoThrow(try GlobalHotKeys.hotKey(code: "F15", command: false, option: false, control: false, shift: false))
        XCTAssertThrowsError(try GlobalHotKeys.hotKey(code: "F5", command: false, option: false, control: false, shift: false))
        XCTAssertThrowsError(
            try GlobalHotKeys.hotKey(code: "Escape", command: true, option: false, control: false, shift: false),
            "a key the table does not know is refused")
    }

    func testAShortcutIsTheKeysPositionWithItsModifiersInMenuOrder() throws {
        let hotKey = try GlobalHotKeys.hotKey(code: "KeyP", command: true, option: true, control: true, shift: true)
        XCTAssertEqual(hotKey.keyCode, UInt32(kVK_ANSI_P))
        XCTAssertEqual(hotKey.modifiers, UInt32(controlKey | optionKey | shiftKey | cmdKey))
        XCTAssertEqual(hotKey.label, "⌃⌥⇧⌘P")
    }
}
