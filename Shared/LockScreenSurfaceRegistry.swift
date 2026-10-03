import Foundation

@MainActor
protocol LockScreenSurfaceLifecycle: AnyObject {
  var isReusable: Bool { get }
  func stop()
}

/// Owns the current surface for each compositor identity, including retry generations.
@MainActor
final class LockScreenSurfaceRegistry<Surface: LockScreenSurfaceLifecycle> {
  struct Acquisition {
    let surface: Surface
    let generation: UInt64
    let isNew: Bool
  }

  private var entries: [UUID: Acquisition] = [:]
  private var generations: [UUID: UInt64] = [:]
  var values: [Surface] { entries.values.map(\.surface) }

  subscript(id: UUID) -> Surface? { entries[id]?.surface }

  func acquire(
    id: UUID, matches: (Surface) -> Bool, create: (UInt64) throws -> Surface
  ) rethrows -> Acquisition {
    if let entry = entries[id], entry.surface.isReusable, matches(entry.surface) {
      return Acquisition(surface: entry.surface, generation: entry.generation, isNew: false)
    }
    remove(id)
    let generation = (generations[id] ?? 0) &+ 1
    generations[id] = generation
    let surface = try create(generation)
    let entry = Acquisition(surface: surface, generation: generation, isNew: true)
    entries[id] = entry
    return entry
  }

  func isCurrent(id: UUID, surface: Surface, generation: UInt64) -> Bool {
    guard let entry = entries[id] else { return false }
    return entry.surface === surface && entry.generation == generation
  }

  func retireAfterFailure(_ id: UUID, surface: Surface, error: Error) {
    // Replacing content cancels old readiness while retaining a healthy context.
    guard !(error is CancellationError) || !surface.isReusable else { return }
    remove(id, matching: surface)
  }

  func remove(_ id: UUID, matching surface: Surface? = nil) {
    guard let entry = entries[id], surface == nil || entry.surface === surface else { return }
    // Remove ownership before stop invokes any pending completion callbacks.
    entries.removeValue(forKey: id)
    entry.surface.stop()
  }
}
