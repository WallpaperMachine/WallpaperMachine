import Foundation

/// Changes wallpapers on the displays whose playlist rotates or follows the day.
///
/// One timer waits for the earliest change. A change only happens while wallpapers are
/// playing and presenting: one that falls due while the user has paused, the screen is locked
/// or the displays sleep waits, and happens once, when `evaluate()` next finds playback
/// running. The app delegate calls `evaluate()` when playback or presentation changes, so
/// nothing is polled. Every switch runs through the display's command slot, the same one the
/// panel and the menu bar use, so the latest request for a display wins.
@MainActor
final class PlaylistScheduler {
    /// Runs one switch on `display` through its command slot. `choose` names the wallpaper when
    /// the switch's turn comes, or nil to skip it. Answers the wallpaper applied, or nil when
    /// nothing was: a newer request replaced this one, or there was nothing to choose.
    typealias Activate = @MainActor (_ display: String, _ choose: @MainActor () -> String?) async throws -> String?

    private let store: PlaylistStore
    private let collections: WallpaperCollectionStore
    private let displays: @MainActor () -> [String]
    private let library: @MainActor () -> [String]
    private let favorites: @MainActor () -> Set<String>
    private let current: @MainActor (String) -> String?
    private let isRunning: @MainActor (String) -> Bool
    private let activate: Activate
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    private let center: NotificationCenter
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var observers: [NSObjectProtocol] = []
    private var timer: Task<Void, Never>?
    private var armedFor: Date?
    private var inFlight = Set<String>()
    /// Displays someone asked to move along while the timer's own change was waiting its turn:
    /// that change then runs as asked for, even if the display paused meanwhile.
    private var requestedWhileInFlight = Set<String>()
    /// The day or night period each display was last brought into line with, and the playlist
    /// it was brought into line under: a wallpaper the user applies by hand stays until the next
    /// period, and choosing a different day or night wallpaper applies at once.
    private var settledPeriods: [String: (period: Date, revision: UInt64)] = [:]
    private var random = SystemRandomNumberGenerator()

    init(
        store: PlaylistStore,
        collections: WallpaperCollectionStore,
        displays: @escaping @MainActor () -> [String],
        library: @escaping @MainActor () -> [String],
        favorites: @escaping @MainActor () -> Set<String>,
        current: @escaping @MainActor (String) -> String?,
        isRunning: @escaping @MainActor (String) -> Bool,
        activate: @escaping Activate,
        now: (@MainActor () -> Date)? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        center: NotificationCenter = .default,
        // The continuous clock keeps counting while the Mac sleeps, so a change that fell due
        // during sleep happens on wake rather than an interval of awake time later.
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(max(0, seconds)))
        }
    ) {
        self.store = store
        self.collections = collections
        self.displays = displays
        self.library = library
        self.favorites = favorites
        self.current = current
        self.isRunning = isRunning
        self.activate = activate
        self.now = now ?? { Date() }
        self.calendar = calendar
        self.center = center
        self.sleep = sleep
    }

    func start() {
        guard observers.isEmpty else {
            evaluate()
            return
        }
        // A clock or time-zone change moves every day and night boundary; the store changes when
        // the user edits a playlist or a change is dated.
        let names: [(Notification.Name, AnyObject?)] = [
            (PlaylistStore.didChangeNotification, store),
            (WallpaperCollectionStore.didChangeNotification, collections),
            (.NSSystemClockDidChange, nil),
            (.NSSystemTimeZoneDidChange, nil),
        ]
        for (name, object) in names {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
        evaluate()
    }

    func stop() {
        for token in observers { center.removeObserver(token) }
        observers.removeAll()
        timer?.cancel()
        timer = nil
        armedFor = nil
    }

    /// Makes every change that is due, dates the next ones and arms the timer for the earliest.
    func evaluate() {
        guard !observers.isEmpty else { return }
        let date = now()
        var earliest: Date?
        for display in displays() {
            let playlist = store.playlist(for: display)
            let running = isRunning(display)
            switch playlist.mode {
            case .off:
                store.schedule(display, at: nil)
                settledPeriods[display] = nil
            case .rotate:
                settledPeriods[display] = nil
                guard let due = store.nextChange[display] else {
                    let next = date.addingTimeInterval(Self.seconds(playlist.interval))
                    store.schedule(display, at: next)
                    earliest = min(earliest ?? next, next)
                    continue
                }
                if due > date {
                    earliest = min(earliest ?? due, due)
                } else if running, !inFlight.contains(display) {
                    rotate(display, playlist: playlist)
                }
            case .dayNight:
                let (phase, until) = PlaylistPlanner.phase(
                    at: date, dayStart: playlist.dayStart, nightStart: playlist.nightStart, calendar: calendar)
                store.schedule(display, at: until)
                earliest = min(earliest ?? until, until)
                let settled = settledPeriods[display]
                guard settled?.period != until || settled?.revision != (store.revisions[display] ?? 0) else { continue }
                guard running, !inFlight.contains(display) else { continue }
                follow(display, phase: phase, period: until, playlist: playlist)
            }
        }
        arm(earliest)
    }

    /// Whether `skip(_:)` has a playlist wallpaper to change `display` to.
    func canSkip(_ display: String) -> Bool {
        let playlist = store.playlist(for: display)
        guard playlist.mode == .rotate else { return false }
        let candidates = candidates(for: playlist)
        return candidates.contains { $0 != current(display) }
    }

    /// Changes `display` to its playlist's next wallpaper now, whatever the timer says, and
    /// starts a fresh interval. Someone asked for it, so it happens while the display is paused
    /// or covered too, and a change already under way counts as the answer. Returns false when
    /// the display does not rotate, so the caller can fall back to the library order.
    @discardableResult
    func skip(_ display: String) -> Bool {
        let playlist = store.playlist(for: display)
        guard playlist.mode == .rotate, displays().contains(display) else { return false }
        if inFlight.contains(display) {
            requestedWhileInFlight.insert(display)
        } else {
            rotate(display, playlist: playlist, requested: true)
        }
        return true
    }

    /// A change the timer brings waits while the display cannot play; a `requested` one does not.
    private func rotate(_ display: String, playlist: DisplayPlaylist, requested: Bool = false) {
        let revision = store.revisions[display] ?? 0
        inFlight.insert(display)
        Task {
            var attempted = false
            defer {
                inFlight.remove(display)
                requestedWhileInFlight.remove(display)
                if (attempted || isRunning(display)), (store.revisions[display] ?? 0) == revision {
                    store.schedule(display, at: now().addingTimeInterval(Self.seconds(playlist.interval)))
                } else {
                    evaluate()
                }
            }
            var candidates: [String] = []
            do {
                let applied = try await activate(display) { [self] in
                    guard (store.revisions[display] ?? 0) == revision,
                        displays().contains(display),
                        requested || requestedWhileInFlight.contains(display) || isRunning(display)
                    else { return nil }
                    attempted = true
                    // Resolve membership when the command runs, not when its timer fired.
                    let latest = store.playlist(for: display)
                    candidates = self.candidates(for: latest)
                    return PlaylistPlanner.next(
                        after: current(display), in: candidates, order: latest.order,
                        recent: store.recent[display] ?? [], using: &random)
                }
                if let applied, (store.revisions[display] ?? 0) == revision {
                    store.recordPick(applied, on: display, candidates: candidates)
                    AppLog.info("playlist changed display \(display) to \(applied)")
                }
            } catch {
                // A failed command is one attempt, not a new immediate retry loop.
                attempted = true
                AppLog.warn("playlist could not change display \(display): \(error.localizedDescription)")
            }
        }
    }
    private func follow(_ display: String, phase: PlaylistPlanner.Phase, period: Date, playlist: DisplayPlaylist) {
        let revision = store.revisions[display] ?? 0
        let target = phase == .day ? playlist.dayWallpaperID : playlist.nightWallpaperID
        guard let target, library().contains(target), current(display) != target else {
            settledPeriods[display] = (period, revision)
            return
        }
        inFlight.insert(display)
        Task {
            var attempted = false
            defer {
                inFlight.remove(display)
                requestedWhileInFlight.remove(display)
                if (attempted || isRunning(display)), (store.revisions[display] ?? 0) == revision {
                    settledPeriods[display] = (period, revision)
                }
                evaluate()
            }
            do {
                let applied = try await activate(display) { [self] in
                    guard (store.revisions[display] ?? 0) == revision,
                        displays().contains(display), isRunning(display), library().contains(target),
                        PlaylistPlanner.phase(at: now(), dayStart: playlist.dayStart,
                            nightStart: playlist.nightStart, calendar: calendar).until == period
                    else { return nil }
                    attempted = true
                    return current(display) == target ? nil : target
                }
                if applied != nil {
                    AppLog.info("playlist switched display \(display) to its \(phase.rawValue) wallpaper")
                }
            } catch {
                attempted = true
                AppLog.warn("playlist could not switch display \(display) to its \(phase.rawValue) wallpaper: \(error.localizedDescription)")
            }
        }
    }

    private func candidates(for playlist: DisplayPlaylist) -> [String] {
        let ids = playlist.collectionID.flatMap { collections.collection(id: $0)?.wallpaperIDs } ?? []
        return PlaylistPlanner.candidates(
            for: playlist, library: library(), favorites: favorites(), collectionIDs: ids)
    }

    private func arm(_ date: Date?) {
        guard date != armedFor else { return }
        timer?.cancel()
        timer = nil
        armedFor = date
        guard let date else { return }
        let delay = date.timeIntervalSince(now())
        let sleep = sleep
        timer = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.armedFor = nil
            self.evaluate()
        }
    }

    static func seconds(_ minutes: Int) -> TimeInterval {
        TimeInterval(max(1, minutes) * 60)
    }
}
