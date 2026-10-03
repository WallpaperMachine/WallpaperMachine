import XCTest

@testable import WallpaperMachine

@MainActor
final class LockScreenSurfaceRegistryTests: XCTestCase {
  private final class Surface: LockScreenSurfaceLifecycle {
    let display: UInt32
    var stopped = false
    var failed = false
    var startCount = 0
    var onStop: (() -> Void)?
    var isReusable: Bool { !stopped && !failed }

    init(display: UInt32 = 1) { self.display = display }
    func start() {
      guard isReusable else { return }
      startCount += 1
    }
    func stop() {
      stopped = true
      onStop?()
    }
  }

  func testFailedAndStoppedSurfacesAreReplacedOnTheSameIdentity() {
    for stopped in [false, true] {
      let registry = LockScreenSurfaceRegistry<Surface>()
      let id = UUID()
      let initial = registry.acquire(id: id, matches: { _ in true }) { _ in Surface() }
      initial.surface.start()
      if stopped { initial.surface.stop() } else { initial.surface.failed = true }

      let retry = registry.acquire(id: id, matches: { _ in true }) { _ in Surface() }
      retry.surface.start()

      XCTAssertFalse(retry.surface === initial.surface)
      XCTAssertTrue(retry.isNew)
      XCTAssertGreaterThan(retry.generation, initial.generation)
      XCTAssertEqual(retry.surface.startCount, 1)
      XCTAssertTrue(initial.surface.stopped)
      XCTAssertTrue(registry[id] === retry.surface)
    }
  }

  func testHealthySameIdentityIsReusedButChangedDisplayGetsANewSurface() {
    let registry = LockScreenSurfaceRegistry<Surface>()
    let id = UUID()
    let initial = registry.acquire(id: id, matches: { $0.display == 1 }) { _ in Surface() }
    let update = registry.acquire(id: id, matches: { $0.display == 1 }) { _ in
      XCTFail("A healthy surface should be reused")
      return Surface()
    }
    XCTAssertTrue(update.surface === initial.surface)
    XCTAssertEqual(update.generation, initial.generation)
    XCTAssertFalse(update.isNew)

    let changed = registry.acquire(id: id, matches: { $0.display == 2 }) { _ in Surface(display: 2) }
    XCTAssertTrue(initial.surface.stopped)
    XCTAssertEqual(changed.surface.display, 2)
    XCTAssertTrue(changed.isNew)
  }

  func testLateCompletionCannotRemoveOrAcknowledgeAReplacement() {
    let registry = LockScreenSurfaceRegistry<Surface>()
    let id = UUID()
    let initial = registry.acquire(id: id, matches: { _ in true }) { _ in Surface() }
    registry.remove(id, matching: initial.surface)
    let retry = registry.acquire(id: id, matches: { _ in true }) { _ in Surface() }

    XCTAssertFalse(registry.isCurrent(id: id, surface: initial.surface, generation: initial.generation))
    registry.remove(id, matching: initial.surface)
    XCTAssertTrue(registry.isCurrent(id: id, surface: retry.surface, generation: retry.generation))
    XCTAssertFalse(retry.surface.stopped)
    XCTAssertTrue(registry[id] === retry.surface)
  }

  func testRemovalDropsOwnershipBeforeStopInvokesPendingCallbacks() {
    let registry = LockScreenSurfaceRegistry<Surface>()
    let id = UUID()
    let initial = registry.acquire(id: id, matches: { _ in true }) { _ in Surface() }
    var callbackSawCurrent = true
    initial.surface.onStop = {
      callbackSawCurrent = registry.isCurrent(
        id: id, surface: initial.surface, generation: initial.generation)
    }
    registry.remove(id)
    initial.surface.onStop = nil
    XCTAssertFalse(callbackSawCurrent)
    XCTAssertNil(registry[id])
  }

  func testReplacingContentCancellationKeepsTheHealthyContextButStoppedCancellationRetiresIt() {
    let registry = LockScreenSurfaceRegistry<Surface>()
    let id = UUID()
    let initial = registry.acquire(id: id, matches: { _ in true }) { _ in Surface() }
    registry.retireAfterFailure(id, surface: initial.surface, error: CancellationError())
    XCTAssertTrue(registry[id] === initial.surface)
    XCTAssertFalse(initial.surface.stopped)

    initial.surface.stop()
    registry.retireAfterFailure(id, surface: initial.surface, error: CancellationError())
    XCTAssertNil(registry[id])
    let retry = registry.acquire(id: id, matches: { _ in true }) { _ in Surface() }
    XCTAssertTrue(retry.isNew)
    XCTAssertFalse(retry.surface.stopped)
  }
}
