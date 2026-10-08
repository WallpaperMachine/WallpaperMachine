import AppKit
import XCTest
@testable import WallpaperMachine

@MainActor
final class ControlPanelAutomationTests: ControlPanelTestCase {
  private func openAutomation(_ panel: PanelFixture) async throws {
    panel.store.librarySnapshot.wallpapers = ["a", "b"].map { id in
      BridgeWallpaperEntry(id: id, title: id == "a" ? "Ocean <img src=x>" : "Evening",
        kind: .webpage, supported: true, active: false, selected: false, previewPath: nil)
    }
    try await panel.finishWelcome()
    panel.navigation.selection = .settings
    panel.show()
    try await panel.waitJS("powerProbe.received.at(-1)?.page === 'settings'")
    _ = try await panel.js("document.querySelector('[data-section=\"displays\"]').click(); document.querySelector('[data-key=\"automation-primary\"] > summary').click()")
    try await panel.waitJS("document.querySelector('[data-auto-mode]').getClientRects().length > 0")
  }

  func testWeekdayRuleCanBeSavedEditedToSunsetAndCancelledWithFocusRestored() async throws {
    try await withPanel { panel in
      try await openAutomation(panel)
      _ = try await panel.js("const mode = document.querySelector('[data-auto-mode]'); mode.value = 'schedule'; mode.dispatchEvent(new Event('change', { bubbles: true }))")
      try await panel.waitUntil { panel.automations.configuration(for: "primary").mode == .schedule }
      try await panel.waitJS("document.querySelector('[data-action=\"autoRuleNew\"]') && !document.querySelector('[data-action=\"autoRuleNew\"]').disabled")
      _ = try await panel.js("""
        document.querySelector('[data-action="autoRuleNew"]').click();
        [...document.querySelectorAll('[data-action="autoDays"]')].find(button => JSON.parse(button.dataset.args).value === 'weekdays').click();
        const time = document.querySelector('[data-auto-field="time"]'); time.value = '09:15'; time.dispatchEvent(new Event('input', { bubbles: true }));
        const target = document.querySelector('[data-auto-field="target"]'); target.value = JSON.stringify({ kind: 'wallpaper', id: 'a' }); target.dispatchEvent(new Event('change', { bubbles: true }));
        document.querySelector('[data-form="automation-rule"]').requestSubmit();
        """)
      try await panel.waitUntil { panel.automations.configuration(for: "primary").rules.count == 1 }
      try await panel.waitJS("!document.querySelector('[data-form=\"automation-rule\"]') && !document.querySelector('[data-action=\"autoRuleNew\"]').disabled")
      let saved = try XCTUnwrap(panel.automations.configuration(for: "primary").rules.first)
      XCTAssertEqual(saved.weekdays, [2, 3, 4, 5, 6])
      XCTAssertEqual(saved.minute, 555)
      try await panel.expectJS("return document.activeElement.dataset.action", equals: "autoRuleNew")
      try await panel.expectJS("return document.querySelectorAll('.settings-auto-rule img').length", equals: 0)
      _ = try await panel.js("""
        document.querySelector('[data-action="autoRuleEdit"]').click();
        const time = document.querySelector('[data-auto-field="time"]'); time.value = ''; time.dispatchEvent(new Event('input', { bubbles: true }));
        const event = document.querySelector('[data-auto-field="event"]'); event.value = 'sunset'; event.dispatchEvent(new Event('change', { bubbles: true }));
        const offset = document.querySelector('[data-auto-field="offset"]'); offset.value = '-25'; offset.dispatchEvent(new Event('input', { bubbles: true }));
        document.querySelector('[data-form="automation-rule"]').requestSubmit();
        """)
      try await panel.waitUntil { panel.automations.configuration(for: "primary").rules.first?.event == .sunset }
      try await panel.waitJS("!document.querySelector('[data-form=\"automation-rule\"]') && !document.querySelector('[data-action=\"autoRuleEdit\"]').disabled")
      XCTAssertEqual(panel.automations.configuration(for: "primary").rules.first?.id, saved.id)
      XCTAssertEqual(panel.automations.configuration(for: "primary").rules.first?.offset, -25)
      try await panel.expectJS("return document.activeElement.dataset.action", equals: "autoRuleEdit")
      _ = try await panel.js("""
        document.activeElement.click();
        const offset = document.querySelector('[data-auto-field="offset"]'); offset.value = '181'; offset.dispatchEvent(new Event('input', { bubbles: true }));
        const event = document.querySelector('[data-auto-field="event"]'); event.value = 'time'; event.dispatchEvent(new Event('change', { bubbles: true }));
        const time = document.querySelector('[data-auto-field="time"]'); time.value = '10:30'; time.dispatchEvent(new Event('input', { bubbles: true }));
        document.querySelector('[data-form="automation-rule"]').requestSubmit();
        """)
      try await panel.waitUntil { panel.automations.configuration(for: "primary").rules.first?.minute == 630 }
      try await panel.waitJS("!document.querySelector('[data-form=\"automation-rule\"]') && !document.querySelector('[data-action=\"autoRuleEdit\"]').disabled")
      XCTAssertEqual(panel.automations.configuration(for: "primary").rules.first?.offset, 0)
      _ = try await panel.js("document.activeElement.click(); document.querySelector('[data-action=\"autoRuleCancel\"]').click()")
      try await panel.expectJS("return document.activeElement.dataset.action", equals: "autoRuleEdit")
      _ = try await panel.js("document.activeElement.click(); document.querySelector('[data-action=\"automationRuleRemove\"]').click()")
      try await panel.waitUntil { panel.automations.configuration(for: "primary").rules.isEmpty }
      try await panel.waitJS("!document.querySelector('[data-form=\"automation-rule\"]') && !document.querySelector('[data-action=\"autoRuleNew\"]').disabled")
      try await panel.expectJS("return document.activeElement.dataset.action", equals: "autoRuleNew")
    }
  }

  func testEmptyWeekdaysDoNotSaveAndLocationPersistsThroughNativeBridge() async throws {
    try await withPanel { panel in
      try panel.automations.update("primary") { $0.mode = .schedule }
      try await openAutomation(panel)
      _ = try await panel.js("""
        document.querySelector('[data-action="autoRuleNew"]').click();
        document.querySelectorAll('[data-auto-day]').forEach(input => { input.checked = false; input.dispatchEvent(new Event('change', { bubbles: true })); });
        const target = document.querySelector('[data-auto-field="target"]'); target.value = JSON.stringify({ kind: 'wallpaper', id: 'a' }); target.dispatchEvent(new Event('change', { bubbles: true }));
        document.querySelector('[data-form="automation-rule"]').requestSubmit();
        """)
      try await panel.waitJS("document.querySelector('.settings-auto-days [role=\"alert\"]')?.textContent.includes('Choose at least one weekday')")
      try await panel.expectJS("return document.activeElement.dataset.autoDay", equals: "1")
      try await panel.expectJS("return document.querySelector('.settings-auto-days').getAttribute('aria-describedby')", equals: "automatic-primary-days-error")
      XCTAssertTrue(panel.automations.configuration(for: "primary").rules.isEmpty)
      _ = try await panel.js("""
        document.querySelector('[data-action="autoRuleCancel"]').click();
        const form = document.querySelector('[data-form="solar-location"]');
        for (const [key, value] of [['latitude', '-33.87'], ['longitude', '151.21']]) {
          form.elements[key].value = value; form.elements[key].dispatchEvent(new Event('input', { bubbles: true }));
        }
        form.requestSubmit();
        """)
      try await panel.waitUntil { panel.automations.location?.latitude == -33.87 }
      try await panel.waitJS("document.querySelector('[data-action=\"automationClearLocation\"]') && !document.querySelector('[data-action=\"automationClearLocation\"]').disabled")
      XCTAssertEqual(WallpaperAutomationStore(defaults: panel.defaults).location?.longitude, 151.21)
      _ = try await panel.js("document.querySelector('[data-action=\"automationClearLocation\"]').click()")
      try await panel.waitUntil { panel.automations.location == nil }
    }
  }

  func testAppearanceTargetSupportsClearingAndTheEditorFitsACompactPanel() async throws {
    try await withPanel { panel in
      try panel.automations.update("primary") { $0.mode = .appearance }
      try await openAutomation(panel)
      panel.web.setFrameSize(NSSize(width: 760, height: 640))
      _ = try await panel.js("const target = document.querySelector('[data-auto-appearance=\"dark\"]'); target.value = JSON.stringify({kind:'wallpaper', id:'b'}); target.dispatchEvent(new Event('change', {bubbles:true}))")
      try await panel.waitUntil { panel.automations.configuration(for: "primary").dark?.id == "b" }
      try await panel.waitJS("!document.querySelector('[data-auto-appearance=\"dark\"]').disabled")
      try await panel.expectJS("const scroll = document.querySelector('.settings-scroll'); return scroll.scrollWidth <= scroll.clientWidth + 1", equals: true)
      _ = try await panel.js("const target = document.querySelector('[data-auto-appearance=\"dark\"]'); target.value = ''; target.dispatchEvent(new Event('change', {bubbles:true}))")
      try await panel.waitUntil { panel.automations.configuration(for: "primary").dark == nil }
    }
  }
}
