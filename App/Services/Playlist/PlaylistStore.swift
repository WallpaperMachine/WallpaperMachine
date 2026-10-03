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
    static let plansKey = "WallpaperMachine.playlistPlans"

    private let defaults: UserDefaults
    private(set) var playlists: [String: DisplayPlaylist]
    private(set) var plans: [PlaylistPlan]
    /// When each display changes next. Kept across launches, so a relaunch neither restarts a
    /// long interval nor skips a change that fell due while the app was closed.
    private(set) var nextChange: [String: Date]
    /// What each display has shown this shuffle round, so every wallpaper comes round before one
    /// repeats. Only for this run of the app.
    private(set) var recent: [String: [String]] = [:]
    private(set) var revisions: [String: UInt64] = [:]
    /// Changes a rotating display to its next wallpaper now, answering false when it does not
    /// rotate. The app delegate points it at the scheduler; the panel's Change now calls it.
    var skipHandler: (@MainActor (String) -> Bool)?

    init(defaults: UserDefaults = ClientPreferences.defaults) {
        self.defaults = defaults
        playlists = (defaults.data(forKey: Self.playlistsKey))
            .flatMap { try? JSONDecoder().decode([String: DisplayPlaylist].self, from: $0) } ?? [:]
        plans = defaults.data(forKey: Self.plansKey)
            .flatMap { try? JSONDecoder().decode([PlaylistPlan].self, from: $0) } ?? []
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
        after.planID = nil
        revisions[display, default: 0] &+= 1
        playlists[display] = after
        if after.mode != before.mode || after.interval != before.interval
            || after.dayStart != before.dayStart || after.nightStart != before.nightStart
        {
            nextChange[display] = nil
        }
        if after.source != before.source || after.collectionID != before.collectionID || after.order != before.order {
            recent[display] = nil
        }
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
                revisions[display, default: 0] &+= 1
                changed = true
            }
        }
        for index in plans.indices {
            let before = plans[index].playlist
            plans[index].playlist.wallpaperIDs.removeAll(where: gone.contains)
            if let day = before.dayWallpaperID, gone.contains(day) { plans[index].playlist.dayWallpaperID = nil }
            if let night = before.nightWallpaperID, gone.contains(night) { plans[index].playlist.nightWallpaperID = nil }
            changed = changed || plans[index].playlist != before
        }
        for display in recent.keys {
            recent[display]?.removeAll(where: gone.contains)
        }
        if changed { persist(plansChanged: true) }
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

    func plan(id: String) -> PlaylistPlan? {
        plans.first { $0.id == id }
    }

    @discardableResult
    func savePlan(from display: String, name: String) throws -> PlaylistPlan {
        var playlist = playlist(for: display)
        playlist.planID = nil
        let plan = PlaylistPlan(id: UUID().uuidString, name: try WallpaperCollectionStore.validatedName(name), playlist: playlist)
        let updated = plans + [plan]
        let data = try JSONEncoder().encode(updated)
        plans = updated
        defaults.set(data, forKey: Self.plansKey)
        persist()
        return plan
    }

    func renamePlan(_ id: String, name: String) throws {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { throw LibraryOrganizationError.missingPlan }
        let name = try WallpaperCollectionStore.validatedName(name)
        guard plans[index].name != name else { return }
        var updated = plans
        updated[index].name = name
        let data = try JSONEncoder().encode(updated)
        plans = updated
        defaults.set(data, forKey: Self.plansKey)
        persist()
    }

    /// Deleting a plan never stops its active display copies; they become independent.
    func deletePlan(_ id: String) throws {
        guard plan(id: id) != nil else { throw LibraryOrganizationError.missingPlan }
        let updated = plans.filter { $0.id != id }
        let data = try JSONEncoder().encode(updated)
        plans = updated
        defaults.set(data, forKey: Self.plansKey)
        for display in playlists.keys where playlists[display]?.planID == id {
            playlists[display]?.planID = nil
        }
        persist()
    }

    /// Copies the plan, not display pause state. Rotation becomes due once; day/night is
    /// reconciled by its existing phase rules when presentation is running again.
    func applyPlan(_ id: String, to display: String) throws {
        guard let plan = plan(id: id) else { throw LibraryOrganizationError.missingPlan }
        var playlist = plan.playlist
        playlist.planID = id
        revisions[display, default: 0] &+= 1
        playlists[display] = playlist
        recent[display] = nil
        nextChange[display] = playlist.mode == .rotate ? .distantPast : nil
        persist()
    }

    /// A removed collection leaves an empty explicit list, never an all-library rotation.
    func forgetCollection(_ id: String) {
        var changed = false
        func detach(_ playlist: inout DisplayPlaylist) {
            guard playlist.collectionID == id else { return }
            playlist.collectionID = nil
            if playlist.source == .collection {
                playlist.source = .list
                playlist.wallpaperIDs = []
            }
            changed = true
        }
        for display in playlists.keys where playlists[display]?.collectionID == id {
            var playlist = playlists[display]!
            detach(&playlist)
            revisions[display, default: 0] &+= 1
            playlists[display] = playlist
            recent[display] = nil
        }
        for index in plans.indices { detach(&plans[index].playlist) }
        if changed { persist(plansChanged: true) }
    }

    private func persist(plansChanged: Bool = false) {
        if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: Self.playlistsKey)
        }
        if plansChanged, let data = try? JSONEncoder().encode(plans) {
            defaults.set(data, forKey: Self.plansKey)
        }
        defaults.set(nextChange.mapValues(\.timeIntervalSince1970), forKey: Self.nextChangeKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
