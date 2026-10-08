import XCTest
@testable import WallpaperMachine

@MainActor
final class ControlPanelSpaceWallpaperTests: ControlPanelTestCase {
  func testDesktopChoicePersistsByUUIDAfterReorderingAndMissingDesktopCanBeForgotten() async throws {
    var topology: [String: WallpaperDisplaySpaces]? = ["1": .init(displayUUID: "screen", spaces: [
      .init(id: "space-a", number: 1), .init(id: "space-b", number: 2),
    ], current: "space-a")]
    let spaces = WallpaperSpaceMonitor(provider: { topology }); spaces.refresh(); defer { spaces.stop() }
    try await withPanel(spaces: spaces) { panel in
      panel.store.settingsSnapshot.displays[0].title = "Main (1 - Primary)"
      panel.store.librarySnapshot.wallpapers = ["a", "b"].map {
        .init(id: $0, title: $0, kind: .webpage, supported: true, active: false, selected: false, previewPath: nil)
      }
      try await panel.finishWelcome()
      panel.navigation.selection = .settings; panel.show()
      try await panel.waitJS("powerProbe.received.at(-1)?.page === 'settings'")
      _ = try await panel.js("""
        document.querySelector('[data-section="displays"]').click();
        document.querySelector('[data-key="automation-primary"] > summary').click();
        const mode = document.querySelector('[data-auto-mode]'); mode.value = 'spaces'; mode.dispatchEvent(new Event('change', {bubbles:true}));
        """)
      try await panel.waitUntil { panel.automations.configuration(for: "primary").mode == .spaces }
      try await panel.waitJS("document.querySelector('[data-auto-space=\"space-a\"]') && !document.querySelector('[data-auto-space=\"space-a\"]').disabled")
      _ = try await panel.js("const choice = document.querySelector('[data-auto-space=\"space-a\"]'); choice.value = JSON.stringify({kind:'wallpaper',id:'b'}); choice.dispatchEvent(new Event('change', {bubbles:true}))")
      try await panel.waitUntil { panel.automations.configuration(for: "primary").spaces["space-a"]?.id == "b" }
      XCTAssertEqual(WallpaperAutomationStore(defaults: panel.defaults).configuration(for: "primary").spaces["space-a"]?.id, "b")
      topology?["1"]?.spaces = [.init(id: "space-b", number: 1), .init(id: "space-a", number: 2)]
      spaces.refresh()
      try await panel.waitJS("document.querySelector('[data-auto-space=\"space-a\"]').getAttribute('aria-label').includes('Desktop 2')")
      try await panel.expectJS("return JSON.parse(document.querySelector('[data-auto-space=\"space-a\"]').value).id", equals: "b")
      topology?["1"]?.current = "space-b"
      topology?["1"]?.spaces = [.init(id: "space-b", number: 1)]
      spaces.refresh()
      try await panel.waitJS("document.querySelector('[data-action=\"automationSpace\"]') && !document.querySelector('[data-action=\"automationSpace\"]').disabled")
      XCTAssertEqual(panel.automations.configuration(for: "primary").spaces["space-a"]?.id, "b")
      _ = try await panel.js("const remove = document.querySelector('[data-action=\"automationSpace\"]'); remove.focus(); remove.click()")
      try await panel.waitUntil { panel.automations.configuration(for: "primary").spaces["space-a"] == nil }
      try await panel.waitJS("!document.querySelector('[data-action=\"automationSpace\"]') && !document.querySelector('[data-auto-mode]').disabled")
      try await panel.expectJS("return document.activeElement.dataset.autoMode", equals: "primary")
    }
  }

  func testUnavailableInformationDisablesSpaceModeAndNativeRequestsCannotInventDesktops() async throws {
    try await withPanel { panel in
      panel.store.settingsSnapshot.displays[0].title = "Main (1 - Primary)"
      do {
        try await panel.controller.perform("automationMode", body: ["displayID": "primary", "value": "spaces"])
        XCTFail("enabled unavailable Space mode")
      } catch {}
      XCTAssertEqual(panel.automations.configuration(for: "primary").mode, .off)
      panel.store.librarySnapshot.wallpapers = [.init(id: "a", title: "A", kind: .webpage, supported: true, active: false, selected: false, previewPath: nil)]
      do {
        try await panel.controller.perform("automationSpace", body: ["displayID": "primary", "spaceID": "made-up", "target": ["kind": "wallpaper", "id": "a"]])
        XCTFail("stored an invented Space")
      } catch {}
      XCTAssertTrue(panel.automations.configuration(for: "primary").spaces.isEmpty)
      try await panel.finishWelcome()
      panel.navigation.selection = .settings; panel.show()
      try await panel.waitJS("powerProbe.received.at(-1)?.page === 'settings'")
      _ = try await panel.js("document.querySelector('[data-section=\"displays\"]').click()")
      try await panel.expectJS("return document.querySelector('[data-auto-mode] option[value=\"spaces\"]').disabled", equals: true)
    }
  }
}
