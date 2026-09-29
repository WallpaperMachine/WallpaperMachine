import Foundation

/// The decisions a playlist makes, kept free of state and clocks so they can be checked
/// directly: which wallpapers a rotation may pick, which one comes next, and which half of
/// the day it is.
enum PlaylistPlanner {
    enum Phase: String, Sendable {
        case day, night
    }

    /// The wallpapers `playlist` rotates through: `library` is every playable wallpaper in
    /// library order, so a list entry or favorite that is gone or cannot play is skipped.
    static func candidates(for playlist: DisplayPlaylist, library: [String], favorites: Set<String>) -> [String] {
        switch playlist.source {
        case .all:
            return library
        case .favorites:
            return library.filter(favorites.contains)
        case .list:
            let playable = Set(library)
            var seen = Set<String>()
            return playlist.wallpaperIDs.filter { playable.contains($0) && seen.insert($0).inserted }
        }
    }

    /// The wallpaper to show after `current`, or nil when there is nothing else to show.
    ///
    /// In order, it is the one after `current`, wrapping, or the first when `current` is not in
    /// the list. Shuffled, it is a random pick that is neither `current` nor shown yet this round
    /// (`recent`, kept by `remember(_:in:candidates:)`), so every wallpaper comes round before
    /// one repeats and each round is a new order.
    static func next<Random: RandomNumberGenerator>(
        after current: String?, in candidates: [String], order: PlaylistOrder, recent: [String],
        using random: inout Random
    ) -> String? {
        let others = candidates.filter { $0 != current }
        guard !others.isEmpty else { return nil }
        switch order {
        case .sequential:
            guard let current, let index = candidates.firstIndex(of: current) else { return candidates.first }
            return candidates[(index + 1) % candidates.count]
        case .shuffle:
            let fresh = others.filter { !recent.contains($0) }
            return (fresh.isEmpty ? others : fresh).randomElement(using: &random)
        }
    }

    /// The wallpapers shown this round once `pick` is shown. A round ends when every candidate
    /// has been, and the next starts empty; `next` never picks the wallpaper on screen, so the
    /// last of one round cannot open the next.
    static func remember(_ pick: String, in recent: [String], candidates: [String]) -> [String] {
        let shown = recent.filter { $0 != pick && candidates.contains($0) } + [pick]
        return Set(candidates).isSubset(of: shown) ? [] : shown
    }

    /// Which half of the day `date` falls in, and when the other half begins. The day runs from
    /// `dayStart` up to `nightStart`; when the day would start after the night, the day is the
    /// part that wraps past midnight instead.
    static func phase(at date: Date, dayStart: Int, nightStart: Int, calendar: Calendar) -> (phase: Phase, until: Date) {
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        let isDay = dayStart <= nightStart
            ? (dayStart..<nightStart).contains(minute)
            : !(nightStart..<dayStart).contains(minute)
        let phase: Phase = isDay ? .day : .night
        let boundary = isDay ? nightStart : dayStart
        return (phase, nextOccurrence(ofMinute: boundary, after: date, calendar: calendar))
    }

    /// The first moment after `date` at `minute` past local midnight. Built from calendar
    /// components, so a day that is 23 or 25 hours long across a clock change still switches at
    /// the time on the clock.
    static func nextOccurrence(ofMinute minute: Int, after date: Date, calendar: Calendar) -> Date {
        let components = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(TimeInterval(DisplayPlaylist.minutesPerDay * 60))
    }
}
