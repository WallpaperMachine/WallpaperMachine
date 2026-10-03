import Foundation
import XCTest

@testable import WallpaperMachine

/// Exercises the actual native payload boundary and bundled page without a desktop window.
@MainActor
final class ControlPanelSnapshotDeliveryTests: ControlPanelTestCase {
  private func entry(_ index: Int, title: String? = nil) -> BridgeWallpaperEntry {
    .init(id: "synthetic-\(index)", title: title ?? "Synthetic wallpaper \(index)", kind: .video,
      supported: true, active: false, selected: false, previewPath: nil)
  }

  func testTenThousandWallpapersReuseTheLibraryDuringDownloadProgress() async throws {
    let fixture = makeStore()
    let transport = PanelProgressTransport()
    let panel = try PanelFixture(store: fixture.store, bridge: fixture.bridge,
      displayTitles: .renderer, pixivTransport: transport)
    do {
      try await panel.start()
      try await panel.finishWelcome()
      // Discover receives progress while the installed library is retained in the page. It
      // does not need 10,000 DOM tiles to verify the transport and cache boundary.
      panel.navigation.selection = .workshop
      panel.store.librarySnapshot.wallpapers = (0..<10_000).map { entry($0) }
      let started = ProcessInfo.processInfo.systemUptime
      let full = panel.controller.snapshot()
      let firstBuild = ProcessInfo.processInfo.systemUptime - started
      let fullBytes = try JSONSerialization.data(withJSONObject: full).count
      let revision = try XCTUnwrap(full["libraryRevision"] as? String)
      XCTAssertEqual((full["wallpapers"] as? [[String: Any]])?.count, 10_000)
      panel.controller.deliveredLibraryRevision = revision
      let work = PixivWork(id: "901", title: "Progress fixture", authorID: "1", authorName: "Fixture",
        thumbnailURL: nil, width: 64, height: 64, pageCount: 1, rating: .everyone,
        aiGenerated: nil, tags: [], rank: nil)
      let job = panel.pixiv.downloads.enqueue(work, page: 0)
      try await panel.waitUntil { transport.isWaiting }
      var durations: [Double] = []
      var deltaSizes: [Int] = []
      for step in 1...5 {
        try await Task.sleep(for: .milliseconds(210))
        transport.report(received: Int64(step * 65_536), expected: 1_048_576)
        try await panel.waitUntil { job.bytesReceived == Int64(step * 65_536) }
        let before = ProcessInfo.processInfo.systemUptime
        let delta = panel.controller.deliverySnapshot()
        durations.append(ProcessInfo.processInfo.systemUptime - before)
        deltaSizes.append(try JSONSerialization.data(withJSONObject: delta).count)
        XCTAssertEqual(delta["libraryRevision"] as? String, revision)
        XCTAssertNil(delta["wallpapers"])
        let download = (delta["pixiv"] as? [String: Any])?["downloads"] as? [[String: Any]]
        XCTAssertEqual(download?.first?["received"] as? Int64, Int64(step * 65_536))
      }
      let average = durations.reduce(0, +) / Double(durations.count)
      XCTAssertLessThan(average, firstBuild, "progress should not rebuild every library row")
      XCTAssertLessThan(try XCTUnwrap(deltaSizes.max()), fullBytes / 20)

      // Verify the same omission on real WKWebView pushes, beyond the testable payload helper.
      panel.controller.deliveredLibraryRevision = nil
      _ = try await panel.js("powerProbe.measureWire = true; powerProbe.wire = []")
      panel.show()
      try await panel.waitJS("powerProbe.wire.some(row => row.hasLibrary && row.count === 10000)")
      try await panel.waitUntil { panel.controller.deliveredLibraryRevision == revision }
      try await Task.sleep(for: .milliseconds(210))
      transport.report(received: 6 * 65_536, expected: 1_048_576)
      try await panel.waitJS("powerProbe.received.at(-1)?.pixiv?.downloads[0]?.received === 393216 && powerProbe.wire.at(-1)?.hasLibrary === false")
      let wireValue = try await panel.js("return powerProbe.wire")
      let wire = try XCTUnwrap(wireValue as? [[String: Any]])
      let fullWire = try XCTUnwrap(wire.first { $0["hasLibrary"] as? Bool == true }?["bytes"] as? Int)
      let deltaWire = try XCTUnwrap(wire.last?["bytes"] as? Int)
      XCTAssertLessThan(deltaWire, fullWire / 20)
      let measurement: [String: Any] = [
        "wallpapers": 10_000, "progressSamples": durations.count,
        "firstConstructionMilliseconds": firstBuild * 1_000,
        "meanProgressConstructionMilliseconds": average * 1_000,
        "firstJSONBytes": fullBytes, "maxProgressJSONBytes": deltaSizes.max()!,
        "actualFullPushUTF8Bytes": fullWire, "actualProgressPushUTF8Bytes": deltaWire,
      ]
      let data = try JSONSerialization.data(withJSONObject: measurement, options: [.prettyPrinted, .sortedKeys])
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
      attachment.name = "APP21-10000-wallpapers"
      attachment.lifetime = .keepAlways
      add(attachment)
      print("APP21 measurement: \(String(decoding: data, as: UTF8.self))")
    } catch {
      await panel.shutdown()
      throw error
    }
    await panel.shutdown()
  }

  func testSelectionLanguageReconnectAndLibraryChangesKeepThePageConsistent() async throws {
    try await withPanel { panel in
      try await panel.finishWelcome()
      panel.store.librarySnapshot.wallpapers = [entry(1), entry(2)]
      panel.store.appSnapshot.selectedWallpaperId = "synthetic-1"
      panel.show()
      try await panel.waitJS("document.querySelector('.tile-select[data-id=\"synthetic-1\"]')?.getAttribute('aria-pressed') === 'true'")
      let revision = try XCTUnwrap(panel.controller.librarySectionCache?.revision)
      try await panel.waitUntil { panel.controller.deliveredLibraryRevision == revision }
      let sameLibrary = panel.store.librarySnapshot
      let sameMonitors = panel.store.monitorInformationSnapshot
      panel.store.librarySnapshot = sameLibrary
      panel.store.monitorInformationSnapshot = sameMonitors
      panel.store.appSnapshot.selectedWallpaperId = "synthetic-2"
      try await panel.waitJS("document.querySelector('.tile-select[data-id=\"synthetic-2\"]')?.getAttribute('aria-pressed') === 'true'")
      XCTAssertEqual(panel.controller.deliveredLibraryRevision, revision)
      try await panel.expectJS("return Object.hasOwn(powerProbe.received.at(-1), 'wallpapers')", equals: false)
      try await panel.controller.perform("languageSetting", body: ["value": "zh-Hans"])
      panel.controller.scheduleUpdate()
      try await panel.waitJS("document.documentElement.lang === 'zh-Hans'")
      try await panel.waitUntil { panel.controller.deliveredLibraryRevision != revision }
      let translatedRevision = try XCTUnwrap(panel.controller.deliveredLibraryRevision)
      XCTAssertNotEqual(translatedRevision, revision)
      try await panel.expectJS("return powerProbe.received.at(-1).selectedID", equals: "synthetic-2")
      panel.store.librarySnapshot.wallpapers[1].title = "Renamed retained item"
      try await panel.waitJS("document.querySelector('.tile-select[data-id=\"synthetic-2\"] .tile-title')?.textContent === 'Renamed retained item'")
      let renamedRevision = try XCTUnwrap(panel.controller.librarySectionCache?.revision)
      try await panel.waitUntil { panel.controller.deliveredLibraryRevision == renamedRevision }
      XCTAssertNotEqual(renamedRevision, translatedRevision)
      let beforeReconnect = try await panel.js("return powerProbe.received.length") as? Int ?? 0
      try await panel.controller.perform("ready", body: [:])
      panel.controller.scheduleUpdate()
      try await panel.waitJS("powerProbe.received.slice(\(beforeReconnect)).some(row => Array.isArray(row.wallpapers))")
      try await panel.expectJS("return document.querySelector('.tile-select[data-id=\"synthetic-2\"]')?.getAttribute('aria-pressed')", equals: "true")
      XCTAssertNil(panel.controller.actionError)
    }
  }

  func testPixivInstalledPagesRefreshWhenLibraryMembershipChanges() async throws {
    try await withPanel { panel in
      try await panel.controller.perform("navigate", body: ["page": "pixiv"])
      try await panel.waitUntil { panel.pixiv.hasLoaded }
      @MainActor func installedPages() throws -> [Int] {
        let rows = try XCTUnwrap(panel.controller.pixivSnapshot()["items"] as? [[String: Any]])
        return try XCTUnwrap(rows.first { $0["id"] as? String == "301" }?["installed"] as? [Int])
      }
      func page(_ index: Int) -> BridgeWallpaperEntry {
        .init(id: "pixiv-301-p\(index)", title: "Installed page \(index)", kind: .webpage,
          supported: true, active: false, selected: false, previewPath: nil)
      }
      panel.store.librarySnapshot.wallpapers = [page(0)]
      XCTAssertEqual(try installedPages(), [0])
      panel.store.appSnapshot.playbackState = .paused
      XCTAssertEqual(try installedPages(), [0])
      panel.store.librarySnapshot.wallpapers.append(page(1))
      XCTAssertEqual(try installedPages(), [0, 1])
      panel.store.librarySnapshot.wallpapers.removeFirst()
      XCTAssertEqual(try installedPages(), [1])
    }
  }

  func testUnknownDeltaRevisionRequestsAFullNativeFallback() async throws {
    try await withPanel { panel in
      try await panel.finishWelcome()
      panel.store.librarySnapshot.wallpapers = [entry(1)]
      panel.show()
      try await panel.waitUntil { panel.controller.deliveredLibraryRevision != nil }
      _ = try await panel.js("""
        powerProbe.measureWire = true;
        powerProbe.wire = [];
        window.deltaReplies = [];
        const receive = wallpaperUI.receive;
        let rejectNextDelta = true;
        wallpaperUI.receive = snapshot => {
          if (rejectNextDelta && !Array.isArray(snapshot.wallpapers)) {
            rejectNextDelta = false;
            snapshot = {...snapshot, libraryRevision:'missing-fixture-base'};
          }
          const answer = receive(snapshot);
          deltaReplies.push(answer ?? null);
          return answer;
        };
        """)
      panel.store.appSnapshot.playbackState = .paused
      try await panel.waitJS("deltaReplies.includes('needsFullSnapshot') && powerProbe.wire.some(row => row.hasLibrary)")
      let pattern = try await panel.js("return powerProbe.wire.map(row => row.hasLibrary)") as? [Bool]
      XCTAssertEqual(Array(pattern?.prefix(2) ?? []), [false, true])
      try await panel.expectJS("return document.querySelectorAll('#wallpaper-grid .tile-select').length", equals: 1)
      XCTAssertNil(panel.controller.actionError)
    }
  }
}

private final class PanelProgressTransport: PixivTransport, @unchecked Sendable {
  private let lock = NSLock()
  private let gate = PixivGate()
  private var progress: (@Sendable (Int64, Int64?) -> Void)?
  var isWaiting: Bool { gate.waiting > 0 }
  func data(from url: URL, session: String?) async throws -> Data { PixivFixtures.pages(workID: 901, count: 1) }
  func image(from url: URL, limit: Int, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Data {
    lock.withLock { self.progress = progress }
    try await gate.pass()
    return Data()
  }
  func report(received: Int64, expected: Int64) {
    let report = lock.withLock { progress }
    report?(received, expected)
  }
}
