import Foundation

/// A successful handshake only earns back restarts after an uninterrupted stable run.
struct WebPanelRecoveryBudget {
  var maximumRestarts = 3
  var window: TimeInterval = 120
  var stableRun: TimeInterval = 60
  private var attempts: [TimeInterval] = []
  private var readyAt: TimeInterval?

  mutating func ready(at now: TimeInterval) {
    if readyAt == nil { readyAt = now }
  }

  mutating func permitRestart(at now: TimeInterval) -> Bool {
    if let readyAt, now - readyAt >= stableRun { attempts.removeAll() }
    readyAt = nil
    attempts.removeAll { now - $0 >= window }
    guard attempts.count < maximumRestarts else { return false }
    attempts.append(now)
    return true
  }

  mutating func reset() {
    readyAt = nil
    attempts.removeAll()
  }
}
