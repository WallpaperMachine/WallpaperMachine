import Observation

/// Runs the user's commands one at a time, in the order they arrive.
///
/// A command given while another runs waits its turn instead of failing: being busy is a
/// state the panel shows, never an error. Commands that share a `slot` want only their
/// latest request carried out — switching wallpapers, selecting one to inspect — so a
/// newer one in the same slot drops any that are still waiting and joins the back of the
/// line. The one already running always finishes.
@MainActor
@Observable
final class UserCommandQueue {
    struct Waiting: Equatable {
        let slot: String?
        /// What the waiting command acts on, for the panel to mark; nil when unknown.
        let subject: String?
    }

    private struct Waiter {
        let slot: String?
        let subject: String?
        let continuation: CheckedContinuation<Bool, Never>
    }

    private(set) var isBusy = false
    private var waiters: [Waiter] = []

    /// Commands waiting behind the running one, oldest first.
    var waiting: [Waiting] { waiters.map { Waiting(slot: $0.slot, subject: $0.subject) } }

    func hasWaiting(slot: String) -> Bool { waiters.contains { $0.slot == slot } }

    /// Runs `operation` once every earlier command has finished. Returns false without
    /// running it when a newer command in the same `slot` replaced it while it waited.
    @discardableResult
    func run(
        slot: String? = nil, subject: String? = nil,
        _ operation: @MainActor () async throws -> Void
    ) async rethrows -> Bool {
        if let slot { supersede(slot: slot) }
        if isBusy {
            let admitted = await withCheckedContinuation { continuation in
                waiters.append(Waiter(slot: slot, subject: subject, continuation: continuation))
            }
            // The finishing command handed `isBusy` over without clearing it.
            guard admitted else { return false }
        } else {
            isBusy = true
        }
        defer { advance() }
        try await operation()
        return true
    }

    private func supersede(slot: String) {
        let replaced = waiters.filter { $0.slot == slot }
        guard !replaced.isEmpty else { return }
        waiters.removeAll { $0.slot == slot }
        for waiter in replaced { waiter.continuation.resume(returning: false) }
    }

    private func advance() {
        guard !waiters.isEmpty else {
            isBusy = false
            return
        }
        waiters.removeFirst().continuation.resume(returning: true)
    }
}
