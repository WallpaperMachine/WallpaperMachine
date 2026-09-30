import CoreGraphics
import Darwin
import Foundation
import XCTest

@testable import WallpaperMachine

final class LockScreenWallpaperServiceTests: XCTestCase {
  private var root: URL!
  private var defaults: UserDefaults!
  private var defaultsSuite: String!
  private var timers: [Timer] = []
  private let preference = "WallpaperMachineAnimateLockScreen"
  private var store: URL { root.appendingPathComponent("Index.plist") }
  private var journal: URL { root.appendingPathComponent("journal.plist") }
  private var exchange: URL { root.appendingPathComponent("Exchange") }
  private var project: URL { root.appendingPathComponent("Project") }
  private var home: URL { root.appendingPathComponent("Home") }
  private var previousHome: String?

  override func setUpWithError() throws {
    defaultsSuite = "lock-screen-service-tests-" + UUID().uuidString
    defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
    defaults.removePersistentDomain(forName: defaultsSuite)
    // Asset snapshots derive relative paths from a resolved enumeration root;
    // the temporary directory is under /var, a symlink that enumeration
    // resolves but standardizedFileURL restores, so stage under Caches instead.
    root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Caches/lock-screen-service-tests-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
    // The managed user-asset store lives under the support root; every test that
    // publishes one has to land in a throwaway home, not the user's own.
    previousHome = ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_HOME"]
    setenv("WALLPAPER_MACHINE_HOME", home.path, 1)
    try Data(#"{"type":"video","title":"t","file":"a.mp4"}"#.utf8).write(
      to: project.appendingPathComponent("project.json"))
    try Data([0x00]).write(to: project.appendingPathComponent("a.mp4"))
    try write(fixture())
  }
  override func tearDownWithError() throws {
    timers.forEach { $0.invalidate() }
    timers.removeAll()
    defaults.removePersistentDomain(forName: defaultsSuite)
    try FileManager.default.removeItem(at: root)
    if let previousHome {
      setenv("WALLPAPER_MACHINE_HOME", previousHome, 1)
    } else {
      unsetenv("WALLPAPER_MACHINE_HOME")
    }
  }

  @MainActor
  private func scheduleMonitor(_ callback: @escaping @MainActor () -> Void) -> Timer {
    // A real Timer, deliberately never registered with a run loop.
    let timer = Timer(timeInterval: 2, repeats: true) { _ in
      MainActor.assumeIsolated { callback() }
    }
    timers.append(timer)
    return timer
  }

  private func choice(_ name: String) -> [String: Any] {
    [
      "Content": [
        "Choices": [["Provider": name, "Configuration": Data(name.utf8), "Files": [String]()]],
        "Shuffle": "$null",
      ], "LastSet": Date(timeIntervalSince1970: 1),
    ]
  }
  private func node(_ name: String) -> [String: Any] {
    [
      "Desktop": choice(name + "-desktop"), "Idle": choice(name + "-idle"), "Type": "individual",
      "Unrelated": name,
    ]
  }
  private func fixture() -> [String: Any] {
    [
      "AllSpacesAndDisplays": node("global"), "SystemDefault": node("system"),
      "Displays": ["one": node("display-one"), "two": node("display-two")],
      "Spaces": [
        "space-a": [
          "Default": node("default-a"),
          "Displays": ["one": node("space-one"), "two": node("space-two")],
        ]
      ],
      "Unrelated": "keep",
    ]
  }
  private func write(_ value: [String: Any]) throws {
    try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(
      to: store, options: .atomic)
  }

  private func scene(propertiesJSON: String? = nil) -> BridgeLockScreenScene {
    BridgeLockScreenScene(
      displayId: CGMainDisplayID(), wallpaperId: "2001", title: "t",
      projectPath: project.appendingPathComponent("project.json").path,
      assetsPath: project.path, fps: 30, scalingMode: .fill, scalingFactor: 1,
      propertiesJson: propertiesJSON, paused: false)
  }

  /// The managed store as the app writes it, isolated per test through
  /// `WALLPAPER_MACHINE_HOME`.
  @discardableResult
  private func writeManagedAsset(
    propertyId: String, fileName: String, bytes: String, kind: String = "file"
  ) throws -> URL {
    let store = ClientPaths.userAssetsURL.appendingPathComponent("2001", isDirectory: true)
    let digest = "d" + String(bytes.hashValue, radix: 16, uppercase: false)
    let directory = store.appendingPathComponent("\(propertyId)/\(digest)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(fileName)
    try Data(bytes.utf8).write(to: file)
    let manifest = """
      {"version":1,"wallpaperId":"2001","properties":{"\(propertyId)":{"kind":"\(kind)",\
      "sourcePath":"/Users/someone/\(fileName)","truncated":false,"migratedLegacyPaths":[],\
      "assets":[{"assetId":"\(digest)","fileName":"\(fileName)",\
      "sourcePath":"/Users/someone/\(fileName)","size":\(bytes.utf8.count),\
      "modified":"2024-01-01T00:00:00Z","digest":"\(digest)"}]}}}
      """
    try Data(manifest.utf8).write(to: store.appendingPathComponent("manifest.json"))
    return file
  }

  @MainActor
  private func waitFor(
    _ description: String, timeout: TimeInterval = 10,
    condition: @MainActor () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("Timed out waiting for \(description)")
  }

  /// Answers the extension's readiness files like the real lock-screen renderer.
  private func readinessResponder() -> Task<Void, Never> {
    let exchange = self.exchange
    return Task.detached {
      while !Task.isCancelled {
        let file = exchange.appendingPathComponent(LockScreenConfiguration.fileName)
        if let data = try? Data(contentsOf: file),
          let configuration = try? JSONDecoder().decode(LockScreenConfiguration.self, from: data)
        {
          for scene in configuration.scenes {
            let readiness = LockScreenReadiness(
              revision: configuration.revision, displayID: scene.displayID, error: nil)
            try? JSONEncoder().encode(readiness).write(
              to: exchange.appendingPathComponent("ready-\(scene.displayID).json"),
              options: .atomic)
          }
        }
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
  }

  @MainActor
  func testActivationFailureAlwaysHandsDesktopBackToPosterProvider() async throws {
    try XCTSkipIf(CGDisplayIsOnline(CGMainDisplayID()) == 0, "No online main display")
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [self.scene()] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal,
      reload: { throw LockScreenWallpaperFailure(message: "agent missing") }),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    var before = 0
    var after = 0
    service.beforeActivation = { before += 1 }
    service.afterDeactivation = { after += 1 }
    service.setEnabled(true)
    await waitFor("the failed activation to settle") { !service.isBusy }
    XCTAssertEqual(before, 1)
    XCTAssertEqual(after, 1)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertFalse(service.isEnabled)
    XCTAssertNotNil(service.errorMessage)
  }

  @MainActor
  func testDisableWithFailedRestorationStillHandsDesktopBack() async throws {
    try XCTSkipIf(CGDisplayIsOnline(CGMainDisplayID()) == 0, "No online main display")
    var failReload = false
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [self.scene()] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal,
      reload: {
        if failReload { throw LockScreenWallpaperFailure(message: "agent missing") }
      }),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    var before = 0
    var after = 0
    service.beforeActivation = { before += 1 }
    service.afterDeactivation = { after += 1 }
    let responder = readinessResponder()
    defer { responder.cancel() }
    service.setEnabled(true)
    await waitFor("the lock screen provider to enable") { service.isEnabled }
    XCTAssertTrue(service.isEnabled)
    XCTAssertTrue(service.ownsDesktopProvider)
    XCTAssertEqual(before, 1)
    failReload = true
    service.setEnabled(false)
    await waitFor("deactivation to finish") { !service.isBusy }
    XCTAssertEqual(after, 1)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertNotNil(service.errorMessage)
  }

  @MainActor
  func testNoAppliedWallpaperReleasesDesktopProvider() async throws {
    try XCTSkipIf(CGDisplayIsOnline(CGMainDisplayID()) == 0, "No online main display")
    var scenes = [scene()]
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { scenes },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    var after = 0
    service.beforeActivation = {}
    service.afterDeactivation = { after += 1 }
    let responder = readinessResponder()
    defer { responder.cancel() }
    service.setEnabled(true)
    await waitFor("the lock screen provider to enable") { service.isEnabled }
    XCTAssertTrue(service.isEnabled)
    XCTAssertTrue(service.ownsDesktopProvider)
    scenes = []
    service.refresh()
    await waitFor("the provider release to settle") { !service.isBusy }
    XCTAssertEqual(after, 1)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertNil(service.errorMessage)
  }

  @MainActor
  func testDisplayTopologyChangesDoNotClearSurvivingLockScreens() async throws {
    var builtIn = scene()
    builtIn.displayId = 1
    var external = builtIn
    external.displayId = 2
    // The external display is first (primary); display identity is not array order.
    var records = [external, builtIn]
    var publications: [LockScreenConfiguration] = []
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { records },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { [1: "one", 2: "two"][$0] },
    persistConfiguration: { url, bytes in
      try bytes.write(to: url, options: .atomic)
      publications.append(try JSONDecoder().decode(
        LockScreenConfiguration.self, from: Data(contentsOf: url)))
    })
    let responder = readinessResponder()
    defer { responder.cancel() }
    try service.start()
    service.setEnabled(true)
    await waitFor("both lock screens ready") { service.isEnabled && !service.isBusy }

    for next in [[builtIn], [external, builtIn], [external]] {
      publications.removeAll()
      records = next
      service.refresh()
      await waitFor("display topology publication") { service.isEnabled && !service.isBusy }
      let expected = Set(next.map(\.displayId))
      XCTAssertEqual(Set(try XCTUnwrap(publications.last).scenes.map(\.displayID)), expected)
      for publication in publications {
        XCTAssertTrue(expected.isSubset(of: Set(publication.scenes.map(\.displayID))),
          "A surviving display must never receive an empty manifest while another display changes")
      }
    }

    publications.removeAll()
    records = [builtIn, external]
    service.refresh()
    await waitFor("both displays return") { service.isEnabled && !service.isBusy }
    let stable = try XCTUnwrap(publications.last)
    publications.removeAll()
    records = [external, builtIn]
    service.refresh()
    await waitFor("primary ordering change") { !service.isBusy }
    XCTAssertTrue(publications.isEmpty, "Reordering displays must not republish their wallpapers")
    let onDisk = try JSONDecoder().decode(LockScreenConfiguration.self,
      from: Data(contentsOf: exchange.appendingPathComponent(LockScreenConfiguration.fileName)))
    XCTAssertEqual(onDisk, stable)

    service.setEnabled(false)
    await waitFor("explicit disable clears every display") { !service.isBusy }
    XCTAssertEqual(try XCTUnwrap(publications.last).scenes, [])
    XCTAssertFalse(service.ownsDesktopProvider)
  }

  @MainActor
  func testWakeDisplayLookupGapPreservesCommittedWallpapersAndRecovers() async throws {
    var builtIn = scene()
    builtIn.displayId = 1
    var external = builtIn
    external.displayId = 2
    var records = [external, builtIn]
    var online: Set<UInt32> = [1, 2]
    var reloads = 0
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { records },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: { reloads += 1 }),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { online.contains($0) ? [1: "one", 2: "two"][$0] : nil })
    let responder = readinessResponder()
    defer { responder.cancel() }
    try service.start()
    service.setEnabled(true)
    await waitFor("external-primary lock screens ready") { service.isEnabled && !service.isBusy }
    let manifest = exchange.appendingPathComponent(LockScreenConfiguration.fileName)
    let committed = try Data(contentsOf: manifest)
    let selected = try Data(contentsOf: store)
    let initialReloads = reloads

    // Core Graphics can temporarily report either or both screens offline
    // before the bridge publishes the settled topology.
    for visible: Set<UInt32> in [[2], [], [1, 2]] {
      online = visible
      service.refresh()
      await waitFor("wake lookup settles") { !service.isBusy }
      XCTAssertTrue(service.isEnabled)
      XCTAssertTrue(service.ownsDesktopProvider)
      XCTAssertNil(service.errorMessage)
      XCTAssertEqual(try Data(contentsOf: manifest), committed)
      XCTAssertEqual(try Data(contentsOf: store), selected)
      XCTAssertEqual(reloads, initialReloads, "A lookup gap must not restart WallpaperAgent")
      XCTAssertTrue(timers.last?.isValid == true, "The existing monitor must keep checking topology")
    }

    online = [2]
    records = [external]
    service.refresh()
    await waitFor("settled external-only topology") { service.isEnabled && !service.isBusy }
    let configuration = try JSONDecoder().decode(LockScreenConfiguration.self,
      from: Data(contentsOf: manifest))
    XCTAssertEqual(configuration.scenes.map(\.displayID), [2])

    // A real removal, unlike an offline lookup, must still release ownership.
    records = []
    service.refresh()
    await waitFor("last wallpaper removed") { !service.isBusy }
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertEqual(try JSONDecoder().decode(LockScreenConfiguration.self,
      from: Data(contentsOf: manifest)).scenes, [])
  }

  @MainActor
  func testMonitorExistsOnlyWhileRequestedAndDoesNotRescheduleWhileBusy() async throws {
    var calls = 0
    var pending: CheckedContinuation<[BridgeLockScreenScene], Never>?
    var suspend = false
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: {
      calls += 1
      if suspend { return await withCheckedContinuation { pending = $0 } }
      return []
    },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    try service.start()
    XCTAssertTrue(timers.isEmpty)
    service.refresh()
    await waitFor("off refresh") { !service.isBusy }
    XCTAssertEqual(calls, 0)
    XCTAssertTrue(timers.isEmpty)
    service.setEnabled(true)
    await waitFor("requested empty scene refresh") { !service.isBusy }
    XCTAssertTrue(service.isRequested)
    XCTAssertFalse(service.isEnabled)
    XCTAssertEqual(timers.count, 1, "Empty scenes still need monitoring for a future wallpaper")
    let timer = try XCTUnwrap(timers.first)
    XCTAssertTrue(timer.isValid)
    suspend = true
    timer.fire()
    await waitFor("suspended scene request") { pending != nil }
    let busyCalls = calls
    timer.fire()
    XCTAssertEqual(calls, busyCalls)
    XCTAssertEqual(timers.count, 1)
    suspend = false
    pending?.resume(returning: [])
    pending = nil
    await waitFor("busy refresh") { !service.isBusy }
    service.refresh()
    await waitFor("explicit refresh") { !service.isBusy }
    XCTAssertEqual(timers.count, 1)
    service.setEnabled(false)
    XCTAssertFalse(timer.isValid, "Disable must stop monitoring before asynchronous restoration")
    await waitFor("disable") { !service.isBusy }
    XCTAssertFalse(defaults.bool(forKey: preference))
    service.setEnabled(true)
    await waitFor("reenable empty scenes") { !service.isBusy }
    XCTAssertEqual(timers.count, 2)
    try await service.shutdown()
    XCTAssertTrue(timers.allSatisfy { !$0.isValid })
    service.setEnabled(true)
    XCTAssertEqual(timers.count, 2)
  }

  @MainActor
  func testPersistedRequestStartsOneMonitorAndErrorsRequireExplicitRetry() async throws {
    defaults.set(true, forKey: preference)
    var fail = true
    var calls = 0
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: {
      calls += 1
      if fail { throw LockScreenWallpaperFailure(message: "scene lookup failed") }
      return []
    },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    try service.start()
    XCTAssertTrue(service.isRequested)
    XCTAssertEqual(timers.count, 1)
    let first = try XCTUnwrap(timers.first)
    first.fire()
    await waitFor("failed polling refresh") { !service.isBusy }
    XCTAssertNotNil(service.errorMessage)
    XCTAssertFalse(first.isValid)
    XCTAssertEqual(calls, 1)
    fail = false
    service.refresh()
    await waitFor("explicit retry") { !service.isBusy }
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(timers.count, 2)
    XCTAssertTrue(try XCTUnwrap(timers.last).isValid)
    try await service.shutdown()
    XCTAssertTrue(timers.allSatisfy { !$0.isValid })
  }

  @MainActor
  func testRecoveryFailureDoesNotStartMonitorAndRefreshCanRecover() async throws {
    defaults.set(true, forKey: preference)
    try Data("invalid journal".utf8).write(to: journal)
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    XCTAssertThrowsError(try service.start())
    XCTAssertTrue(timers.isEmpty)
    XCTAssertNotNil(service.errorMessage)
    try FileManager.default.removeItem(at: journal)
    service.refresh()
    await waitFor("successful recovery retry") { !service.isBusy }
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(timers.count, 1)
    try await service.shutdown()
  }

  @MainActor
  func testDisableCancelsReadinessBeforeEnabledPreferenceCanCommit() async throws {
    try XCTSkipIf(CGDisplayIsOnline(CGMainDisplayID()) == 0, "No online main display")
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [self.scene()] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    try service.start()
    service.setEnabled(true)
    await waitFor("published scene awaiting readiness") {
      service.ownsDesktopProvider && FileManager.default.fileExists(atPath: self.journal.path)
    }
    XCTAssertTrue(service.isBusy)
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(defaults.bool(forKey: preference))
    let timer = try XCTUnwrap(timers.last)
    service.setEnabled(false)
    XCTAssertFalse(timer.isValid)
    try answerPublishedReadiness()
    await waitFor("cancelled readiness and restoration") { !service.isBusy }
    XCTAssertFalse(service.isRequested)
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertFalse(defaults.bool(forKey: preference))
    XCTAssertNil(service.errorMessage)
    XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
  }

  @MainActor
  func testNewGenerationCannotCommitPreviousReadiness() async throws {
    try XCTSkipIf(CGDisplayIsOnline(CGMainDisplayID()) == 0, "No online main display")
    var records = [scene()]
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { records },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    try service.start()
    service.setEnabled(true)
    await waitFor("first generation awaiting readiness") {
      service.ownsDesktopProvider && FileManager.default.fileExists(atPath: self.journal.path)
    }
    records = []
    service.refresh()
    try answerPublishedReadiness()
    await waitFor("replacement generation") { !service.isBusy }
    XCTAssertTrue(service.isRequested)
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertFalse(defaults.bool(forKey: preference))
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(timers.count, 1)
    try await service.shutdown()
  }

  @MainActor
  func testShutdownStopsMonitorBeforeWaitingAndKeepsItStoppedOnFailure() async throws {
    try XCTSkipIf(CGDisplayIsOnline(CGMainDisplayID()) == 0, "No online main display")
    var failReload = false
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [self.scene()] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal,
      reload: {
        if failReload { throw LockScreenWallpaperFailure(message: "restoration failed") }
      }),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    try service.start()
    service.setEnabled(true)
    await waitFor("activation waiting for readiness") {
      service.ownsDesktopProvider && FileManager.default.fileExists(atPath: self.journal.path)
    }
    let timer = try XCTUnwrap(timers.last)
    failReload = true
    let shutdown = Task { try await service.shutdown() }
    await waitFor("shutdown monitor cancellation") { !timer.isValid }
    do {
      try await shutdown.value
      XCTFail("Expected failed restoration")
    } catch {
      XCTAssertNotNil(service.errorMessage)
    }
    XCTAssertFalse(timer.isValid)
    XCTAssertFalse(service.isBusy)
    XCTAssertEqual(timers.count, 1)
    XCTAssertFalse(defaults.bool(forKey: preference))
    failReload = false
    service.setEnabled(false)
    await waitFor("explicit restoration retry") { !service.isBusy }
    XCTAssertNil(service.errorMessage)
    XCTAssertTrue(timers.allSatisfy { !$0.isValid })
  }

  /// An unchanged monitor tick must not disable or republish. After a lookup gap,
  /// that same timer — not another scene or preference change — retries the
  /// committed mapping once the display UUID resolves.
  @MainActor
  func testUnchangedMonitorTickDoesNotRepublishAndResolvedUUIDRecovers() async throws {
    var builtIn = scene()
    builtIn.displayId = 1
    var online: Set<UInt32> = [1]
    var publications = 0
    var reloads = 0
    var sceneReads = 0
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: {
      sceneReads += 1
      return [builtIn]
    },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: { reloads += 1 }),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { online.contains($0) ? [1: "one"][$0] : nil },
    persistConfiguration: { url, bytes in
      try bytes.write(to: url, options: .atomic)
      publications += 1
    })
    let responder = readinessResponder()
    defer { responder.cancel() }
    try service.start()
    service.setEnabled(true)
    await waitFor("lock screen ready") { service.isEnabled && !service.isBusy }
    let manifest = exchange.appendingPathComponent(LockScreenConfiguration.fileName)
    let committed = try Data(contentsOf: manifest)
    let publishedCount = publications
    let reloadCount = reloads
    let timer = try XCTUnwrap(timers.last)
    XCTAssertTrue(timer.isValid)

    let unchangedReads = sceneReads
    timer.fire()
    await waitFor("unchanged monitor tick") { sceneReads > unchangedReads && !service.isBusy }
    XCTAssertTrue(service.isEnabled)
    XCTAssertTrue(service.ownsDesktopProvider)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(publications, publishedCount)
    XCTAssertEqual(reloads, reloadCount)
    XCTAssertEqual(try Data(contentsOf: manifest), committed)
    let enabledStatus = service.status
    let selected = try Data(contentsOf: store)

    online = []
    timer.fire()
    await waitFor("pending topology") { !service.isBusy }
    XCTAssertTrue(service.isEnabled)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(publications, publishedCount)
    XCTAssertEqual(try Data(contentsOf: manifest), committed)
    XCTAssertEqual(try Data(contentsOf: store), selected)
    XCTAssertTrue(timer.isValid)

    online = [1]
    timer.fire()
    await waitFor("monitor recovery") { !service.isBusy }
    XCTAssertTrue(service.isEnabled)
    XCTAssertTrue(service.ownsDesktopProvider)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(publications, publishedCount, "Resolving the same mapping must not republish")
    XCTAssertEqual(reloads, reloadCount, "Recovery must not restart WallpaperAgent")
    XCTAssertEqual(try Data(contentsOf: manifest), committed)
    XCTAssertEqual(try Data(contentsOf: store), selected)
    XCTAssertEqual(service.status, enabledStatus)
    XCTAssertEqual(timers.count, 1)
  }

  /// A compatibility failure still rolls back to disabled. A later lookup gap must
  /// not erase that error or restart the monitor, and must not touch the selection.
  @MainActor
  func testPendingTopologyKeepsEarlierCompatibilityError() async throws {
    var builtIn = scene()
    builtIn.displayId = 1
    var online: Set<UInt32> = [1]
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [builtIn] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { online.contains($0) ? [1: "one"][$0] : nil })
    let responder = readinessResponder()
    defer { responder.cancel() }
    try service.start()
    service.setEnabled(true)
    await waitFor("lock screen ready") { service.isEnabled && !service.isBusy }
    try setGlobalWallpaperLinked()
    builtIn.fps = 24
    service.refresh()
    await waitFor("compatibility rollback") { !service.isBusy }
    let manifest = exchange.appendingPathComponent(LockScreenConfiguration.fileName)
    let error = try XCTUnwrap(service.errorMessage)
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    let errorStatus = service.status
    XCTAssertEqual(
      try JSONDecoder().decode(LockScreenConfiguration.self, from: Data(contentsOf: manifest)).scenes,
      [])
    let timer = try XCTUnwrap(timers.last)
    XCTAssertFalse(timer.isValid)
    let failedStore = try Data(contentsOf: store)
    let failedManifest = try Data(contentsOf: manifest)
    let timerCount = timers.count

    online = []
    service.refresh()
    await waitFor("pending retry") { !service.isBusy }
    XCTAssertEqual(service.errorMessage, error)
    XCTAssertEqual(service.status, errorStatus)
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertEqual(try Data(contentsOf: store), failedStore)
    XCTAssertEqual(try Data(contentsOf: manifest), failedManifest)
    XCTAssertEqual(timers.count, timerCount)
    XCTAssertFalse(timer.isValid, "A preserved error must not restart the monitor")
  }

  /// Replacing a committed mapping keeps isEnabled until the new frame is
  /// acknowledged. A readiness failure still rolls back to disabled.
  @MainActor
  func testReplacementStagingKeepsEnabledUntilReadinessFailureRollsBack() async throws {
    var builtIn = scene()
    builtIn.displayId = 1
    var external = builtIn
    external.displayId = 2
    var records = [builtIn]
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { records },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { [1: "one", 2: "two"][$0] })
    try service.start()
    service.setEnabled(true)
    await waitFor("first publication") {
      service.ownsDesktopProvider && FileManager.default.fileExists(atPath: self.journal.path)
    }
    try answerPublishedReadiness()
    await waitFor("first mapping enabled") { service.isEnabled && !service.isBusy }
    let manifest = exchange.appendingPathComponent(LockScreenConfiguration.fileName)

    records = [builtIn, external]
    service.refresh()
    await waitFor("replacement published") {
      guard service.isBusy else { return false }
      guard let data = try? Data(contentsOf: manifest),
        let configuration = try? JSONDecoder().decode(LockScreenConfiguration.self, from: data)
      else { return false }
      return configuration.scenes.count == 2
    }
    XCTAssertTrue(service.isEnabled, "Staging must not clear the committed enabled state")
    XCTAssertTrue(service.ownsDesktopProvider)
    try failPublishedReadiness("renderer failed")
    await waitFor("readiness rollback") { !service.isBusy }
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertEqual(
      try JSONDecoder().decode(LockScreenConfiguration.self, from: Data(contentsOf: manifest)).scenes,
      [])
    XCTAssertTrue(service.errorMessage?.contains("renderer failed") == true)
  }

  // MARK: - Managed user assets

  /// The extension can only read the exchange directory, so a property pointing at the
  /// app's managed store has to be republished there and the value
  /// rewritten. Only the assets this wallpaper references may travel.
  @MainActor
  func testReferencedUserAssetsArePublishedIntoTheExchangeAndNothingElseIs() async throws {
    try XCTSkipIf(CGDisplayIsOnline(CGMainDisplayID()) == 0, "No online main display")
    try writeManagedAsset(propertyId: "cover", fileName: "a b+c.png", bytes: "cover-bytes")
    // A second wallpaper's import, which this one must not carry into the exchange.
    let other = ClientPaths.userAssetsURL.appendingPathComponent(
      "9999/cover/abc", isDirectory: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try Data("other-wallpaper".utf8).write(to: other.appendingPathComponent("other.png"))

    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [self.scene(propertiesJSON: #"{"cover":"/Users/someone/a b+c.png"}"#)] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    let responder = readinessResponder()
    defer { responder.cancel() }
    try service.start()
    service.setEnabled(true)
    await waitFor("enabled with published assets") { service.isEnabled }

    let configuration = try JSONDecoder().decode(
      LockScreenConfiguration.self,
      from: Data(contentsOf: exchange.appendingPathComponent(LockScreenConfiguration.fileName)))
    let json = try XCTUnwrap(XCTUnwrap(configuration.scenes.first).propertiesJSON)
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: XCTUnwrap(json.data(using: .utf8))) as? [String: Any])
    let value = try XCTUnwrap(root["cover"] as? String)

    XCTAssertTrue(
      value.hasPrefix(exchange.path + "/revisions/"),
      "the extension cannot read the app's own store, so the value must name the exchange copy")
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: value)), Data("cover-bytes".utf8))
    let published = try FileManager.default.subpathsOfDirectory(atPath: exchange.path)
    XCTAssertFalse(
      published.contains { $0.hasSuffix("other.png") },
      "another wallpaper's imports are not this wallpaper's to publish")

    try await service.shutdown()
  }

  /// Republishing the same selection must not copy it again, and must not leave the
  /// revision it replaced behind for good — there was no collection at all before.
  @MainActor
  func testRepublishingReusesTheRevisionAndCollectsOnlyUnreferencedOnes() async throws {
    try XCTSkipIf(CGDisplayIsOnline(CGMainDisplayID()) == 0, "No online main display")
    try writeManagedAsset(propertyId: "cover", fileName: "first.png", bytes: "first-bytes")
    var properties = #"{"cover":"/Users/someone/first.png"}"#
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [self.scene(propertiesJSON: properties)] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor)
    let responder = readinessResponder()
    defer { responder.cancel() }
    try service.start()
    service.setEnabled(true)
    await waitFor("first publication") { service.isEnabled }

    let revisions = exchange.appendingPathComponent("revisions", isDirectory: true)
    let firstNames = try Set(FileManager.default.contentsOfDirectory(atPath: revisions.path))
    let assetRevision = try XCTUnwrap(
      publishedAssetRevision(), "the first publication must name an asset revision")
    let inode = try XCTUnwrap(try? FileManager.default.attributesOfItem(
      atPath: assetRevision.path)[.systemFileNumber] as? NSNumber)

    // A stale revision of exactly the shape earlier activations left behind.
    let orphan = revisions.appendingPathComponent(String(repeating: "a", count: 64), isDirectory: true)
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
    try Data("stale".utf8).write(to: orphan.appendingPathComponent("stale.png"))

    // Off and on again republishes the same selection from scratch, which is the
    // path that would copy the assets a second time if the fingerprint were unstable.
    service.setEnabled(false)
    await waitFor("deactivated") { !service.isBusy && !service.isEnabled }
    service.setEnabled(true)
    await waitFor("second publication") { service.isEnabled && !service.isBusy }

    XCTAssertEqual(
      try XCTUnwrap(try? FileManager.default.attributesOfItem(
        atPath: assetRevision.path)[.systemFileNumber] as? NSNumber), inode,
      "an unchanged selection must reuse its revision rather than copy it again")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: orphan.path),
      "an unreferenced revision is a leak; there was no collection before this")
    let afterNames = try Set(FileManager.default.contentsOfDirectory(atPath: revisions.path))
    XCTAssertTrue(
      firstNames.isSubset(of: afterNames),
      "a revision the published configuration still names must never be collected")

    // Now change the selection: the old asset revision becomes unreferenced.
    try writeManagedAsset(propertyId: "cover", fileName: "second.png", bytes: "second-bytes")
    properties = #"{"cover":"/Users/someone/second.png"}"#
    service.refresh()
    await waitFor("third publication") { service.isEnabled && !service.isBusy }

    XCTAssertFalse(
      FileManager.default.fileExists(atPath: assetRevision.path),
      "the replaced asset revision is unreferenced and must be collected")
    let replacement = try XCTUnwrap(publishedAssetRevision())
    XCTAssertEqual(
      try Data(contentsOf: replacement.appendingPathComponent("cover/second.png")),
      Data("second-bytes".utf8))

    try await service.shutdown()
  }


  @MainActor
  func testScreenSaverOnlySelectsIdleWithoutWaitingForAnActiveSurface() async throws {
    var record = scene()
    record.displayId = 1
    var native = fixture()
    native["AllSpacesAndDisplays"] = ["Type": "idle", "Idle": choice("default")]
    try write(native)
    let original = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: store), format: nil) as! NSDictionary
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [record] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" })
    service.beforeActivation = { XCTFail("Saver-only selection must not take the desktop") }
    try service.start()
    service.setScreenSaverEnabled(true)
    await waitFor("idle selection without a readiness responder") { !service.isBusy }
    XCTAssertTrue(service.screenSaverEnabled)
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    let configuration = try publishedConfiguration()
    XCTAssertFalse(configuration.lockScreenEnabled)
    XCTAssertTrue(configuration.screenSaverEnabled)
    XCTAssertEqual(configuration.scenes.map(\.displayID), [1])
    XCTAssertEqual(try selectedProvider("Desktop"), "display-one-desktop")
    XCTAssertEqual(try selectedProvider("Idle"), LockScreenConfiguration.extensionIdentifier)
    let selected = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: store), format: nil) as! [String: Any]
    XCTAssertNil(selected["AllSpacesAndDisplays"],
      "Selected must mean the default global screen saver no longer overrides the display")

    service.setScreenSaverEnabled(false)
    await waitFor("idle restoration") { !service.isBusy }
    XCTAssertFalse(service.screenSaverEnabled)
    XCTAssertEqual(try PropertyListSerialization.propertyList(
      from: Data(contentsOf: store), format: nil) as? NSDictionary, original)
    XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
  }

  @MainActor
  func testDisablingEitherPresentationPreservesTheOtherInBothOrders() async throws {
    for (disableLockFirst, displayOnline) in [(true, true), (false, true), (true, false), (false, false)] {
      var online = true
      var record = scene()
      record.displayId = 1
      let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [record] },
      selection: LockScreenWallpaperSelection(
        storeURL: store, journalURL: journal, reload: {}),
      exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
      displayUUID: { _ in online ? "one" : nil })
      let responder = readinessResponder()
      try service.start()
      service.setScreenSaverEnabled(true)
      await waitFor("saver selected") { !service.isBusy }
      service.setEnabled(true)
      await waitFor("both presentations selected") { !service.isBusy }
      XCTAssertTrue(service.isEnabled)
      XCTAssertTrue(service.screenSaverEnabled)
      online = displayOnline
      if disableLockFirst { service.setEnabled(false) }
      else { service.setScreenSaverEnabled(false) }
      await waitFor("one presentation restored") { !service.isBusy }
      let configuration = try publishedConfiguration()
      XCTAssertEqual(configuration.lockScreenEnabled, !disableLockFirst)
      XCTAssertEqual(configuration.screenSaverEnabled, disableLockFirst)
      XCTAssertEqual(service.isEnabled, !disableLockFirst)
      XCTAssertEqual(service.screenSaverEnabled, disableLockFirst)
      XCTAssertEqual(service.ownsDesktopProvider, !disableLockFirst)
      XCTAssertEqual(try selectedProvider(disableLockFirst ? "Idle" : "Desktop"),
        LockScreenConfiguration.extensionIdentifier)
      XCTAssertEqual(try selectedProvider(disableLockFirst ? "Desktop" : "Idle"),
        disableLockFirst ? "display-one-desktop" : "display-one-idle")
      if !displayOnline {
        if disableLockFirst { service.setEnabled(true) }
        else { service.setScreenSaverEnabled(true) }
        await waitFor("re-enable deferred by topology") { !service.isBusy }
      }
      if disableLockFirst { service.setScreenSaverEnabled(false) }
      else { service.setEnabled(false) }
      await waitFor("both restored") { !service.isBusy }
      responder.cancel()
      try await service.shutdown()
      XCTAssertTrue(try publishedConfiguration().scenes.isEmpty)
      XCTAssertEqual(try selectedProvider("Desktop"), "display-one-desktop")
      XCTAssertEqual(try selectedProvider("Idle"), "display-one-idle")
    }
  }

  @MainActor
  func testWebSaverPublishesEntryAndManagedPropertiesWithoutTakingLockScreen() async throws {
    try Data(#"{"type":"web","title":"still","file":"pages/index.html"}"#.utf8).write(
      to: project.appendingPathComponent("project.json"))
    try FileManager.default.createDirectory(at: project.appendingPathComponent("pages"),
      withIntermediateDirectories: true)
    try Data("<html><body>local</body></html>".utf8).write(
      to: project.appendingPathComponent("pages/index.html"))
    try writeManagedAsset(propertyId: "cover", fileName: "a b.png", bytes: "cover-content")
    let manifestURL = ClientPaths.userAssetsURL.appendingPathComponent("2001/manifest.json")
    var manifest = try XCTUnwrap(try JSONSerialization.jsonObject(
      with: Data(contentsOf: manifestURL)) as? [String: Any])
    var entries = try XCTUnwrap(manifest["properties"] as? [String: Any])
    entries["empty"] = ["kind": "directory", "sourcePath": "/old/empty",
      "truncated": false, "migratedLegacyPaths": [], "assets": []] as [String: Any]
    manifest["properties"] = entries
    try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
    var record = scene(propertiesJSON:
      #"{"cover":{"type":"file","value":"/old/a b.png"},"empty":{"type":"directory","value":"/old/empty"},"color":{"type":"color","value":"1 0 0"}}"#)
    record.displayId = 1
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [record] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" })
    try service.start()
    service.setEnabled(true)
    await waitFor("web excluded from lock screen") { !service.isBusy }
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertEqual(try selectedProvider("Desktop"), "display-one-desktop")
    service.setScreenSaverEnabled(true)
    await waitFor("web saver selected") { !service.isBusy }
    XCTAssertTrue(service.screenSaverEnabled)
    XCTAssertFalse(service.isEnabled)
    let configuration = try publishedConfiguration()
    let published = try XCTUnwrap(configuration.scenes.first)
    XCTAssertEqual(published.webEntryFile, "pages/index.html")
    let rootURL = exchange.appendingPathComponent(published.projectPath).deletingLastPathComponent()
    XCTAssertEqual(try String(contentsOf: rootURL.appendingPathComponent("pages/index.html"),
      encoding: .utf8), "<html><body>local</body></html>")
    let properties = try XCTUnwrap(try JSONSerialization.jsonObject(
      with: Data(try XCTUnwrap(published.propertiesJSON).utf8)) as? [String: [String: Any]])
    let value = try XCTUnwrap(properties["cover"]?["value"] as? String)
    let url = try XCTUnwrap(URL(string: value))
    XCTAssertTrue(url.isFileURL)
    XCTAssertTrue(url.path.hasPrefix(rootURL.path + "/"),
      "The web read grant must not expose other projects or their imports")
    XCTAssertEqual(try Data(contentsOf: url), Data("cover-content".utf8))
    XCTAssertEqual(properties["cover"]?["type"] as? String, "file")
    XCTAssertEqual(properties["color"]?["value"] as? String, "1 0 0")
    let emptyURL = try XCTUnwrap(URL(string: try XCTUnwrap(properties["empty"]?["value"] as? String)))
    XCTAssertTrue(emptyURL.path.hasPrefix(rootURL.path + "/"))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: emptyURL.path), [])
    XCTAssertEqual(try selectedProvider("Desktop"), "display-one-desktop")
    try await service.shutdown()
  }

  @MainActor
  func testEscapingWebEntryLeavesNativeSelectionsUntouched() async throws {
    try Data(#"{"type":"web","file":"../outside.html"}"#.utf8).write(
      to: project.appendingPathComponent("project.json"))
    try Data("outside".utf8).write(to: root.appendingPathComponent("outside.html"))
    let original = try Data(contentsOf: store)
    var record = scene()
    record.displayId = 1
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [record] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" })
    try service.start()
    service.setScreenSaverEnabled(true)
    await waitFor("rejected web entry") { !service.isBusy }
    XCTAssertFalse(service.screenSaverEnabled)
    XCTAssertNotNil(service.screenSaverError)
    XCTAssertEqual(try Data(contentsOf: store), original)
  }

  @MainActor
  func testIdleRendererFailureRestoresSelectionAndStopsAutomaticRetries() async throws {
    var record = scene()
    record.displayId = 1
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [record] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" })
    try service.start()
    service.setScreenSaverEnabled(true)
    await waitFor("saver selected") { !service.isBusy }
    XCTAssertTrue(service.screenSaverEnabled)
    let timer = try XCTUnwrap(timers.last)
    try failPublishedReadiness("native renderer could not load")
    timer.fire()
    await waitFor("failed idle renderer restored") { !service.isBusy }
    XCTAssertFalse(service.screenSaverEnabled)
    XCTAssertNotNil(service.screenSaverError)
    XCTAssertFalse(timer.isValid)
    XCTAssertEqual(try selectedProvider("Idle"), "display-one-idle")
    XCTAssertEqual(try selectedProvider("Desktop"), "display-one-desktop")
    XCTAssertTrue(try publishedConfiguration().scenes.isEmpty)
  }

  @MainActor
  func testCancellingLockActivationDoesNotCancelAnAlreadySelectedSaver() async throws {
    var record = scene()
    record.displayId = 1
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [record] },
    selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" })
    try service.start()
    service.setScreenSaverEnabled(true)
    await waitFor("saver selected") { !service.isBusy }
    service.setEnabled(true)
    await waitFor("lock waiting for its first frame") {
      service.ownsDesktopProvider && (try? self.selectedProvider("Desktop"))
        == LockScreenConfiguration.extensionIdentifier
    }
    service.setEnabled(false)
    await waitFor("lock cancelled while saver remains selected") { !service.isBusy }
    XCTAssertTrue(service.screenSaverEnabled)
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertNil(service.screenSaverError)
    let configuration = try publishedConfiguration()
    XCTAssertTrue(configuration.screenSaverEnabled)
    XCTAssertFalse(configuration.lockScreenEnabled)
    XCTAssertEqual(try selectedProvider("Idle"), LockScreenConfiguration.extensionIdentifier)
    XCTAssertEqual(try selectedProvider("Desktop"), "display-one-desktop")
    try await service.shutdown()
  }

  private func publishedConfiguration() throws -> LockScreenConfiguration {
    try JSONDecoder().decode(LockScreenConfiguration.self,
      from: Data(contentsOf: exchange.appendingPathComponent(LockScreenConfiguration.fileName)))
  }

  @MainActor
  func testConfigurationFailureRestoresSelectionWithoutWaitingForFrameTimeout() async throws {
    let bundle = root.appendingPathComponent("extension.appex")
    var record = scene()
    record.displayId = 1
    var loadFailed = false
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {
      guard let configuration = try? self.publishedConfiguration(), !configuration.scenes.isEmpty else { return }
      do {
        let invalid = ["version": 2, "revision": configuration.revision, "scenes": false] as [String: Any]
        try JSONSerialization.data(withJSONObject: invalid).write(
          to: self.exchange.appendingPathComponent(LockScreenConfiguration.fileName), options: .atomic)
        _ = try LockScreenExtensionStatus.loadConfiguration(
          exchange: self.exchange, bundleURL: bundle, reportWriteFailure: { XCTFail("\($0)") })
      } catch { loadFailed = true }
    }, scenes: { [record] }, selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" }, expectedExtensionBundle: bundle,
    runningExtensionBundles: { XCTFail("Should fail before the timeout"); return [] })
    var handedBack = false
    service.afterDeactivation = { handedBack = true }
    try service.start()
    service.setEnabled(true)
    await waitFor("configuration failure rollback", timeout: 3) { !service.isBusy }
    XCTAssertTrue(loadFailed)
    XCTAssertTrue(handedBack)
    XCTAssertFalse(service.isEnabled)
    XCTAssertFalse(service.ownsDesktopProvider)
    XCTAssertNotNil(service.errorMessage)
    XCTAssertFalse(defaults.bool(forKey: preference))
    XCTAssertEqual(try selectedProvider("Desktop"), "display-one-desktop")
    XCTAssertTrue(try publishedConfiguration().scenes.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    try await service.shutdown()
  }

  @MainActor
  func testHealthyDiagnosticStillWaitsForPixelsAndIgnoresStaleFailures() async throws {
    let bundle = root.appendingPathComponent("extension.appex")
    var record = scene()
    record.displayId = 1
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {
      _ = try? LockScreenExtensionStatus.loadConfiguration(
        exchange: self.exchange, bundleURL: bundle, reportWriteFailure: { XCTFail("\($0)") })
    }, scenes: { [record] }, selection: LockScreenWallpaperSelection(
      storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" }, expectedExtensionBundle: bundle)
    try service.start()
    service.setEnabled(true)
    await waitFor("diagnostic") {
      FileManager.default.fileExists(atPath: self.exchange.appendingPathComponent(LockScreenExtensionStatus.fileName).path)
    }
    XCTAssertTrue(service.isBusy)
    XCTAssertFalse(service.isEnabled)
    let stale = LockScreenExtensionStatus(
      revision: "old", bundlePath: "/old.appex", supportedVersion: 1, error: "old failure")
    try JSONEncoder().encode(stale).write(
      to: exchange.appendingPathComponent(LockScreenExtensionStatus.fileName), options: .atomic)
    let responder = readinessResponder()
    defer { responder.cancel() }
    await waitFor("frame readiness") { !service.isBusy }
    XCTAssertTrue(service.isEnabled)
    XCTAssertNil(service.errorMessage)
    try await service.shutdown()
  }

  @MainActor
  func testLegacyExtensionTimeoutInspectsRunningCopyAndRestoresSelection() async throws {
    var record = scene()
    record.displayId = 1
    var inspected = false
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [record] },
    selection: LockScreenWallpaperSelection(storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" }, expectedExtensionBundle: root.appendingPathComponent("intended.appex"),
    runningExtensionBundles: {
      inspected = true
      return [self.root.appendingPathComponent("old.appex")]
    }, readinessTimeout: 0)
    service.setEnabled(true)
    await waitFor("legacy timeout") { !service.isBusy }
    XCTAssertTrue(inspected)
    XCTAssertNotNil(service.errorMessage)
    XCTAssertFalse(service.isEnabled)
    XCTAssertEqual(try selectedProvider("Desktop"), "display-one-desktop")
    XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    try await service.shutdown()
  }

  @MainActor
  func testConfigurationVersionFailureAfterSaverSelectionRestoresIdle() async throws {
    let bundle = root.appendingPathComponent("extension.appex")
    var record = scene()
    record.displayId = 1
    let service = LockScreenWallpaperService(notifyConfigurationChanged: {}, scenes: { [record] },
    selection: LockScreenWallpaperSelection(storeURL: store, journalURL: journal, reload: {}),
    exchange: exchange, defaults: defaults, scheduleMonitor: scheduleMonitor,
    displayUUID: { _ in "one" }, expectedExtensionBundle: bundle)
    try service.start()
    service.setScreenSaverEnabled(true)
    await waitFor("saver selection") { !service.isBusy }
    XCTAssertTrue(service.screenSaverEnabled)
    XCTAssertThrowsError(try LockScreenExtensionStatus.loadConfiguration(
      exchange: exchange, bundleURL: bundle, supportedVersion: 1,
      reportWriteFailure: { XCTFail("\($0)") }))
    try XCTUnwrap(timers.last).fire()
    await waitFor("configuration failure after selection") { !service.isBusy }
    XCTAssertFalse(service.screenSaverEnabled)
    XCTAssertNotNil(service.screenSaverError)
    XCTAssertEqual(try selectedProvider("Idle"), "display-one-idle")
    XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    try await service.shutdown()
  }

  private func selectedProvider(_ key: String) throws -> String? {
    let value = try XCTUnwrap(try PropertyListSerialization.propertyList(
      from: Data(contentsOf: store), format: nil) as? [String: Any])
    let displays = value["Displays"] as? [String: [String: Any]]
    let selected = displays?["one"]?[key] as? [String: Any]
    let content = selected?["Content"] as? [String: Any]
    return (content?["Choices"] as? [[String: Any]])?.first?["Provider"] as? String
  }

  /// The asset revision is the one holding a `cover` directory; the project payload
  /// revision holds `project.json`.
  private func publishedAssetRevision() throws -> URL? {
    let revisions = exchange.appendingPathComponent("revisions", isDirectory: true)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: revisions.path)) ?? []
    return names.map { revisions.appendingPathComponent($0, isDirectory: true) }
      .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("cover").path) }
  }

  private func answerPublishedReadiness() throws {
    let configuration = try JSONDecoder().decode(
      LockScreenConfiguration.self,
      from: Data(contentsOf: exchange.appendingPathComponent(LockScreenConfiguration.fileName)))
    for scene in configuration.scenes {
      let readiness = LockScreenReadiness(
        revision: configuration.revision, displayID: scene.displayID, error: nil)
      try JSONEncoder().encode(readiness).write(
        to: exchange.appendingPathComponent("ready-\(scene.displayID).json"), options: .atomic)
    }
  }

  private func failPublishedReadiness(_ message: String) throws {
    let configuration = try JSONDecoder().decode(
      LockScreenConfiguration.self,
      from: Data(contentsOf: exchange.appendingPathComponent(LockScreenConfiguration.fileName)))
    for scene in configuration.scenes {
      let readiness = LockScreenReadiness(
        revision: configuration.revision, displayID: scene.displayID, error: message)
      try JSONEncoder().encode(readiness).write(
        to: exchange.appendingPathComponent("ready-\(scene.displayID).json"), options: .atomic)
    }
  }

  private func setGlobalWallpaperLinked() throws {
    let data = try Data(contentsOf: store)
    var root = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    var global = try XCTUnwrap(root["AllSpacesAndDisplays"] as? [String: Any])
    global["Type"] = "linked"
    root["AllSpacesAndDisplays"] = global
    try write(root)
  }
}
