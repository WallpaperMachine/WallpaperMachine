import Foundation

/// Every display's playlist, saved in UserDefaults, and when each display that rotates or
/// follows the day changes next. Mutations post `didChangeNotification` once; the scheduler
/// and the panel follow it.
@MainActor
final class PlaylistStore {
    static let shared = PlaylistStore()
    static let didChangeNotification = Notification.Name("WallpaperMachine.playlistsDidChange")
    private static let playlistsKey = "WallpaperMachine.playlists"
    private static let nextChangeKey = "WallpaperMachine.playlistNextChange"

    private let defaults: UserDefaults
    private(set) var playlists: [String: DisplayPlaylist]
    /// When each display changes next. Kept across launches, so a relaunch neither restarts a
    /// long interval nor skips a change that fell due while the app was closed.
    private(set) var nextChange: [String: Date]
    /// What each display has shown this shuffle round, so every wallpaper comes round before one
    /// repeats. Only for this run of the app.
    private(set) var recent: [String: [String]] = [:]
    /// Changes a rotating display to its next wallpaper now, answering false when it does not
    /// rotate. The app delegate points it at the scheduler; the panel's Change now calls it.
    var skipHandler: (@MainActor (String) -> Bool)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        playlists = (defaults.data(forKey: Self.playlistsKey))
            .flatMap { try? JSONDecoder().decode([String: DisplayPlaylist].self, from: $0) } ?? [:]
        let stored = defaults.dictionary(forKey: Self.nextChangeKey) as? [String: Double] ?? [:]
        nextChange = stored.mapValues { Date(timeIntervalSince1970: $0) }
    }

    func playlist(for display: String) -> DisplayPlaylist {
        playlists[display] ?? DisplayPlaylist()
    }

    /// Changes one display's playlist. A new mode, interval or day and night times start a
    /// fresh wait, which the scheduler dates.
    func update(_ display: String, _ change: (inout DisplayPlaylist) -> Void) {
        let before = playlist(for: display)
        var after = before
        change(&after)
        guard after != before else { return }
        playlists[display] = after
        if after.mode != before.mode || after.interval != before.interval
            || after.dayStart != before.dayStart || after.nightStart != before.nightStart
        {
            nextChange[display] = nil
        }
        if after.source != before.source || after.order != before.order { recent[display] = nil }
        persist()
    }

    /// Appends the wallpapers not already on the display's list, in the order given.
    func add(_ ids: [String], to display: String) {
        update(display) { playlist in
            for id in ids where !playlist.wallpaperIDs.contains(id) { playlist.wallpaperIDs.append(id) }
        }
    }

    func remove(_ id: String, from display: String) {
        update(display) { $0.wallpaperIDs.removeAll { $0 == id } }
    }

    /// Drops wallpapers that left the library from every list and every day or night choice.
    func forget(_ ids: [String]) {
        let gone = Set(ids)
        var changed = false
        for (display, playlist) in playlists {
            var kept = playlist
            kept.wallpaperIDs.removeAll(where: gone.contains)
            if let day = kept.dayWallpaperID, gone.contains(day) { kept.dayWallpaperID = nil }
            if let night = kept.nightWallpaperID, gone.contains(night) { kept.nightWallpaperID = nil }
            if kept != playlist {
                playlists[display] = kept
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Dates the display's next change; nil clears it. Setting the date it already has is not a
    /// change, so the scheduler can re-date on every evaluation without a feedback loop.
    func schedule(_ display: String, at date: Date?) {
        guard nextChange[display] != date else { return }
        nextChange[display] = date
        persist()
    }

    /// Remembers a pick for shuffle; see `PlaylistPlanner.remember(_:in:candidates:)`.
    func recordPick(_ id: String, on display: String, candidates: [String]) {
        recent[display] = PlaylistPlanner.remember(id, in: recent[display] ?? [], candidates: candidates)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: Self.playlistsKey)
        }
        defaults.set(nextChange.mapValues(\.timeIntervalSince1970), forKey: Self.nextChangeKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
