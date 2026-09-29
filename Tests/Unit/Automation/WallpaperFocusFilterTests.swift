import XCTest
@testable import WallpaperMachine

final class WallpaperFocusFilterTests: XCTestCase {
    /// macOS performs the filter with its default values when the Focus turns off, so the
    /// default has to be the choice that asks nothing of wallpapers, or ending a Focus would
    /// pause them instead of letting them run again.
    func testTurningAFocusOffLetsWallpapersRunAgain() {
        XCTAssertNil(WallpaperFocusFilter().action.ruleAction)
    }

    func testEachChoiceActsAsTheSameAppRuleWould() {
        XCTAssertEqual(
            FocusWallpaperAction.allCases.map(\.ruleAction), [nil, .mute, .pause, .stop])
    }
}
