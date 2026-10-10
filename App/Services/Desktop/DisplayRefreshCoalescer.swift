import Foundation

/// Runs one display refresh at a time, and none while the displays are as the
/// last successful refresh read them. macOS posts screen-parameter changes in
/// bursts: an XDR display posts one per frame while its EDR headroom ramps, as
/// a menu-bar banner, HDR content or a brightness change moves it, and none of
/// those change anything the renderer reads. Each refresh is a full round trip
/// through the bridge that republishes every snapshot and re-renders the
/// control panel, so a change that leaves the configuration as it was is
/// dropped, and the changes that arrive while one runs are answered by a
/// single refresh after it.
@MainActor
final class DisplayRefreshCoalescer {
    private let configuration: @MainActor () -> DisplayConfiguration
    private let refresh: @MainActor () async -> Bool
    private var running = false
    private var pending = false
    private var coalesced = 0
    /// What the last refresh read, kept only when it succeeded; a failed one is retried
    /// on the next change even if the displays look the same.
    private var refreshed: DisplayConfiguration?

    /// `refresh` reports whether it succeeded.
    init(configuration: @escaping @MainActor () -> DisplayConfiguration = DisplayConfiguration.current,
         refresh: @escaping @MainActor () async -> Bool) {
        self.configuration = configuration
        self.refresh = refresh
    }

    func request() {
        guard !running else {
            pending = true
            coalesced += 1
            return
        }
        guard isChanged(configuration()) else { return }
        running = true
        Task { await drain() }
    }

    private func drain() async {
        repeat {
            pending = false
            let current = configuration()
            if isChanged(current) {
                refreshed = await refresh() ? current : nil
            }
        } while pending
        running = false
        if coalesced > 0 {
            AppLog.info("display refresh: \(coalesced) screen changes arrived during a refresh and were merged")
            coalesced = 0
        }
    }

    private func isChanged(_ current: DisplayConfiguration) -> Bool {
        current != refreshed
    }
}
