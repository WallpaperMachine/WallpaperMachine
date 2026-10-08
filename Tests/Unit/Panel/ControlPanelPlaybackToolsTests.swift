import Foundation
import XCTest
@testable import WallpaperMachine

@MainActor
final class ControlPanelPlaybackToolsTests: ControlPanelTestCase {
  private func installLibrary(_ panel: PanelFixture) {
    panel.store.librarySnapshot.wallpapers = ["a", "b", "c", "d"].map { id in
      BridgeWallpaperEntry(id: id, title: id == "b" ? "B <img src=x onerror=alert(1)>" : id,
        kind: .webpage, supported: true, active: false, selected: false, previewPath: nil)
    }
  }

  func testButtonsAndDragReorderTheNativePlaylistAndRefuseAStaleDrag() async throws {
    try await withPanel { panel in
      installLibrary(panel)
      panel.playlists.update("primary") {
        $0.mode = .rotate; $0.source = .list; $0.wallpaperIDs = ["a", "b", "c"]
      }
      try await panel.finishWelcome()
      panel.navigation.selection = .settings
      panel.show()
      try await panel.waitJS("powerProbe.received.at(-1)?.page === 'settings'")
      _ = try await panel.js("document.querySelector('[data-section=\"displays\"]').click()")
      try await panel.waitJS("document.querySelectorAll('[data-playlist-item]').length === 3")
      _ = try await panel.js("document.querySelector('[data-key=\"display-primary-playlist\"] > summary').click()")
      try await panel.waitJS("document.querySelector('[data-playlist-item] button').getClientRects().length > 0")
      try await panel.expectJS("return document.querySelectorAll('.settings-playlist img').length", equals: 0)
      _ = try await panel.js("""
        const row = document.querySelector('[data-playlist-item="a"]');
        const down = [...row.querySelectorAll('[data-action="playlistMove"]')].find(button => JSON.parse(button.dataset.args).direction === 1);
        down.focus(); down.click();
        """)
      try await panel.waitUntil { panel.playlists.playlist(for: "primary").wallpaperIDs == ["b", "a", "c"] }
      try await panel.waitJS("[...document.querySelectorAll('[data-playlist-item]')].map(row => row.dataset.playlistItem).join(',') === 'b,a,c' && !document.querySelector('[data-action=\"playlistRemove\"]').disabled")
      try await panel.expectJS("return JSON.parse(document.activeElement.dataset.args).id", equals: "a")
      try await panel.expectJS("return JSON.parse(document.activeElement.dataset.args).direction", equals: 1)
      _ = try await panel.js("document.activeElement.click()")
      try await panel.waitUntil { panel.playlists.playlist(for: "primary").wallpaperIDs == ["b", "c", "a"] }
      try await panel.waitJS("document.activeElement.dataset.action === 'playlistMove' && JSON.parse(document.activeElement.dataset.args).direction === -1")
      try await panel.expectJS("return JSON.parse(document.activeElement.dataset.args).id", equals: "a")
      _ = try await panel.js("document.activeElement.click()")
      try await panel.waitUntil { panel.playlists.playlist(for: "primary").wallpaperIDs == ["b", "a", "c"] }
      try await panel.waitJS("[...document.querySelectorAll('[data-playlist-item]')].map(row => row.dataset.playlistItem).join(',') === 'b,a,c' && !document.querySelector('[data-action=\"playlistRemove\"]').disabled")
      try await panel.expectJS("return Boolean(document.querySelector('.settings-playlist + [role=\"status\"]').textContent.trim())", equals: true)
      _ = try await panel.js("""
        const source = document.querySelector('[data-playlist-item="b"]');
        const target = document.querySelector('[data-playlist-item="c"]');
        const rect = target.getBoundingClientRect();
        const dataTransfer = new DataTransfer();
        source.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer }));
        target.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, clientY: rect.bottom - 1, dataTransfer }));
        target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, clientY: rect.bottom - 1, dataTransfer }));
        """)
      try await panel.waitUntil { panel.playlists.playlist(for: "primary").wallpaperIDs == ["a", "c", "b"] }
      XCTAssertEqual(PlaylistStore(defaults: panel.defaults).playlist(for: "primary").wallpaperIDs, ["a", "c", "b"])
      try await panel.waitJS("[...document.querySelectorAll('[data-playlist-item]')].map(row => row.dataset.playlistItem).join(',') === 'a,c,b' && !document.querySelector('[data-action=\"playlistRemove\"]').disabled")
      _ = try await panel.js("document.querySelector('[data-playlist-item=\"a\"]').dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: new DataTransfer() }))")
      panel.playlists.add(["d"], to: "primary")
      try await panel.waitJS("document.querySelectorAll('[data-playlist-item]').length === 4")
      _ = try await panel.js("""
        const target = document.querySelector('[data-playlist-item="b"]');
        target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, clientY: target.getBoundingClientRect().bottom - 1 }));
        """)
      try await panel.waitJS("Boolean(document.querySelector('#settings-content [role=\"alert\"]'))")
      XCTAssertEqual(panel.playlists.playlist(for: "primary").wallpaperIDs, ["a", "c", "b", "d"])
    }
  }

  func testRecentHistoryEscapesTitlesAndClearsOnlyTheTargetDisplay() async throws {
    try await withPanel { panel in
      installLibrary(panel)
      panel.store.history.recordSwitch(from: "a", to: "b", on: "primary")
      panel.store.history.recordSwitch(from: "b", to: "c", on: "primary")
      panel.store.history.recordSwitch(from: "d", to: "a", on: "secondary")
      panel.store.monitorInformationSnapshot.rows = [BridgeMonitorInfoRow(
        displayId: "primary", title: "Primary", wallpaperId: "c", wallpaperTitle: "c",
        mirrorTargetDisplayId: nil, mirrorTargetTitle: nil, scalingMode: "fill", targetFps: "30", audioResponse: false)]
      try await panel.finishWelcome()
      panel.show()
      try await panel.waitJS("document.querySelector('[data-action=\"previousWallpaper\"]')?.disabled === false")
      _ = try await panel.js("document.querySelector('[data-action=\"openHistory\"]').click()")
      try await panel.waitJS("!document.getElementById('history-popover').hidden && document.querySelectorAll('.history-item').length === 3")
      try await panel.expectJS("return [...document.querySelectorAll('.history-item')].map(item => item.dataset.id)", equals: ["c", "b", "a"])
      try await panel.expectJS("return document.querySelector('.history-item[data-id=\"c\"]').getAttribute('aria-current')", equals: "true")
      try await panel.expectJS("return document.querySelector('.history-item[data-id=\"b\"] .history-title').textContent", equals: "B <img src=x onerror=alert(1)>")
      try await panel.expectJS("return document.querySelectorAll('#history-popover img').length", equals: 0)
      _ = try await panel.js("document.querySelector('#history-popover [data-action=\"historyClear\"]').click()")
      try await panel.waitUntil { panel.store.history.entries["primary"] == nil }
      try await panel.waitJS("document.querySelectorAll('.history-item').length === 0 && document.querySelector('[data-action=\"previousWallpaper\"]').disabled")
      XCTAssertEqual(panel.store.history.recent(on: "secondary", available: ["a", "d"]), ["a", "d"])
      _ = try await panel.js("document.querySelector('#history-popover [data-action=\"closePopover\"]').click()")
      try await panel.waitJS("document.getElementById('history-popover').hidden")
      try await panel.expectJS("return document.activeElement.dataset.action", equals: "openHistory")
    }
  }
}
