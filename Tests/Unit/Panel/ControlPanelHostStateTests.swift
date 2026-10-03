import Foundation
import XCTest

@testable import WallpaperMachine

@MainActor
final class ControlPanelHostStateTests: ControlPanelTestCase {
  private func configure(_ panel: PanelFixture) {
    panel.store.librarySnapshot.wallpapers = ["alpha", "beta"].map {
      .init(id: $0, title: "Wallpaper \($0)", kind: .webpage, supported: true,
        active: false, selected: false, previewPath: nil)
    }
    panel.store.settingsSnapshot.displays = [1, 2, 3].map { id in
      .init(displayId: String(id), title: "Display \(id)", enabled: true, mode: .standalone,
        mirrorTargets: [], selectedMirrorTarget: nil, scalingMode: .fill, scalingFactor: 1,
        targetFps: 30, maxFps: 60, muted: false, volume: 1)
    }
    panel.store.monitorInformationSnapshot.rows = [1, 2, 3].map { id in
      .init(displayId: String(id), title: "Display \(id)", wallpaperId: id == 3 ? "beta" : "alpha",
        wallpaperTitle: id == 3 ? "Wallpaper beta" : "Wallpaper alpha", mirrorTargetDisplayId: nil,
        mirrorTargetTitle: nil, scalingMode: "fill", targetFps: "30", audioResponse: false)
    }
    panel.navigation.targetDisplayID = "1"
    panel.store.appSnapshot.selectedWallpaperId = "alpha"
    let fallback = bundle(panel.store)
    panel.bridge.bundleProvider = { [weak store = panel.store] in
      guard let store else { return fallback }
      return BridgeSnapshotBundle(app: store.appSnapshot, library: store.librarySnapshot,
        wallpaperOptions: store.wallpaperOptionsSnapshot, monitorInformation: store.monitorInformationSnapshot,
        settings: store.settingsSnapshot)
    }
  }

  private func bundle(_ store: BridgeStore) -> BridgeSnapshotBundle {
    .init(app: store.appSnapshot, library: store.librarySnapshot, wallpaperOptions: store.wallpaperOptionsSnapshot,
      monitorInformation: store.monitorInformationSnapshot, settings: store.settingsSnapshot)
  }

  private func state(_ id: String, display: UInt32, revision: UInt64,
    phase: HostWallpaperState.Phase, kind: HostWallpaperState.Kind = .web,
    admission: UInt64? = nil, message: String? = nil, canRetry: Bool = false) -> HostWallpaperState {
    .init(kind: kind, displayID: display, wallpaperID: id, startupRevision: revision,
      nativeAdmissionKey: admission, phase: phase, message: message, canRetry: canRetry)
  }

  func testInspectorScopesHostStatesEscapesReasonsAndRetriesTheExactDisplay() async throws {
    try await withPanel { panel in
      try await panel.finishWelcome()
      configure(panel)
      var retries: [(String, UInt32)] = []
      panel.store.retryHostWallpaper = { retries.append(($0, $1)) }
      let reason = #"Cannot open <strong>preview</strong> & "video" content."#
      panel.store.receiveHostState(state("alpha", display: 1, revision: 7, phase: .loading))
      panel.store.receiveHostState(state("alpha", display: 2, revision: 8, phase: .failed, message: reason, canRetry: true))
      panel.store.receiveHostState(state("beta", display: 3, revision: 9, phase: .ready,
        kind: .nativeVideo, admission: 42))
      panel.show()
      try await panel.waitJS("document.querySelectorAll('#inspector [data-host-display]').length === 2")
      try await panel.expectJS("return [...document.querySelectorAll('#inspector [data-host-display]')].map(row => row.dataset.hostDisplay)", equals: ["1", "2"])
      try await panel.expectJS("return document.querySelector('#inspector [data-host-display=\"2\"] p').textContent", equals: reason)
      try await panel.expectJS("return document.querySelectorAll('#inspector [data-host-display=\"2\"] p strong').length", equals: 0)
      try await panel.expectJS("return document.querySelector('#inspector [data-host-display=\"1\"] strong').textContent.includes('Loading wallpaper content')", equals: true)
      try await panel.expectJS("return document.querySelector('#inspector [data-host-display=\"2\"] strong').textContent.includes('Display 2')", equals: true)
      _ = try await panel.js("document.querySelector('#inspector [data-host-display=\"2\"] [data-action=\"retryHostWallpaper\"]').click()")
      try await panel.waitUntil { retries.count == 1 }
      XCTAssertEqual(retries.first?.0, "alpha")
      XCTAssertEqual(retries.first?.1, 2)
      try await panel.waitUntil { panel.bridge.hostStartupCalls.count == 2 }
      XCTAssertEqual(panel.bridge.hostStartupCalls.map(\.wallpaper), ["alpha", "beta"])
      XCTAssertEqual(panel.bridge.hostStartupCalls.map(\.ready), [false, true])
      XCTAssertEqual(panel.bridge.hostStartupCalls.last?.admission, 42)

      panel.store.appSnapshot.selectedWallpaperId = "beta"
      try await panel.waitJS("document.querySelectorAll('#inspector [data-host-display]').length === 1 && document.querySelector('#inspector [data-host-display=\"3\"]') !== null")
      try await panel.expectJS("return document.querySelectorAll('#inspector [data-action=\"retryHostWallpaper\"]').length", equals: 0)
      try await panel.expectJS("return document.querySelector('#inspector [data-host-display=\"3\"] strong').textContent.includes('Wallpaper content is ready')", equals: true)
      XCTAssertNil(panel.controller.actionError)
    }
  }

  func testFailureWithoutRetryCapabilityShowsTheErrorAndRejectsStaleRetryActions() async throws {
    try await withPanel { panel in
      try await panel.finishWelcome()
      configure(panel)
      panel.store.retryHostWallpaper = { _, _ in XCTFail("a failure without a retryable page must not reload") }
      let reason = "The project could not be read."
      panel.store.receiveHostState(state("alpha", display: 1, revision: 7, phase: .failed, message: reason))
      panel.show()
      try await panel.waitJS("document.querySelector('#inspector [data-host-display=\"1\"] p') !== null")
      try await panel.expectJS("return document.querySelector('#inspector [data-host-display=\"1\"] p').textContent", equals: reason)
      try await panel.expectJS("return document.querySelectorAll('#inspector [data-action=\"retryHostWallpaper\"]').length", equals: 0)
      do {
        try await panel.controller.perform("retryHostWallpaper", body: ["id": "alpha", "displayID": "1"])
        XCTFail("an action from an older snapshot must recheck retry eligibility")
      } catch is WallpaperActionError { }
    }
  }

  func testOldWallpaperCompletionAndCloseCannotReplaceTheNewInspectorState() async throws {
    try await withPanel { panel in
      try await panel.finishWelcome()
      configure(panel)
      panel.store.retryHostWallpaper = { _, _ in XCTFail("a retired failure must not expose retry") }
      panel.store.receiveHostState(state("alpha", display: 1, revision: 10, phase: .loading))
      panel.store.receiveHostState(state("beta", display: 1, revision: 11, phase: .loading))
      panel.store.receiveHostState(state("alpha", display: 1, revision: 10, phase: .failed, message: "Old completion"))
      panel.store.receiveHostState(state("alpha", display: 1, revision: 10, phase: .closed))
      panel.store.receiveHostState(state("alpha", display: 1, revision: 11, phase: .failed, message: "Wrong assignment"))
      panel.store.appSnapshot.selectedWallpaperId = "beta"
      panel.show()
      try await panel.waitJS("document.querySelector('#inspector [data-host-display=\"1\"] strong')?.textContent.includes('Loading wallpaper content')")
      XCTAssertEqual(panel.store.hostWallpaperStates["web:1"]?.wallpaperID, "beta")
      XCTAssertTrue(panel.bridge.hostStartupCalls.isEmpty)
      try await panel.expectJS("return document.querySelectorAll('#inspector [data-action=\"retryHostWallpaper\"]').length", equals: 0)
      panel.store.receiveHostState(state("beta", display: 1, revision: 11, phase: .ready))
      try await panel.waitJS("document.querySelector('#inspector [data-host-display=\"1\"] strong')?.textContent.includes('Wallpaper content is ready')")
      try await panel.waitUntil { panel.bridge.hostStartupCalls.count == 1 }
      XCTAssertEqual(panel.bridge.hostStartupCalls.first?.wallpaper, "beta")
      XCTAssertEqual(panel.bridge.hostStartupCalls.first?.revision, 11)
      panel.store.receiveHostState(state("alpha", display: 1, revision: 10, phase: .closed))
      XCTAssertEqual(panel.store.hostWallpaperStates["web:1"]?.phase, .ready)
      panel.store.receiveHostState(state("beta", display: 1, revision: 11, phase: .closed))
      try await panel.waitJS("document.querySelector('#inspector [data-host-display=\"1\"]') === null")
      XCTAssertNil(panel.controller.actionError)
    }
  }
}
