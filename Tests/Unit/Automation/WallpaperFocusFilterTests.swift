import XCTest
@testable import WallpaperMachine

final class WallpaperFocusFilterTests: XCTestCase {
    /// macOS performs the filter with its default values when the Focus turns off, so the
    /// default has to be the choice that asks nothing of wallpapers, or ending a Focus would
    /// pause them instead of letting them run again.
    func testTurningAFocusOffLetsWallpapersRunAgain() {
        XCTAssertNil(WallpaperFocusFilter().action.ruleAction)
    }

    func testInactiveFocusIgnoresRetainedChoicesAndActiveChoiceRequiresItsEntity() throws {
        var filter = WallpaperFocusFilter()
        filter.action = .wallpaper
        XCTAssertThrowsError(try filter.wallpaperSelection())
        filter.wallpaper = WallpaperEntity(id: "wallpaper", title: "Wallpaper")
        filter.playlist = WallpaperPlaylistEntity(id: "plan", title: "Plan")
        XCTAssertEqual(try filter.wallpaperSelection()?.target, .init(kind: .wallpaper, id: "wallpaper"))
        filter.action = .playlist
        XCTAssertEqual(try filter.wallpaperSelection()?.target, .init(kind: .playlist, id: "plan"))
        filter.action = .keepRunning
        XCTAssertNil(try filter.wallpaperSelection(), "the Focus-off defaults must release the temporary choice")
    }
}
