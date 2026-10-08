import Foundation
import Observation

/// Successful wallpaper switches, kept separately for each display.
@MainActor
@Observable
final class WallpaperHistoryStore {
    static let preferenceKey = "WallpaperMachine.wallpaperHistory"
    static let limit = 50

    struct Entry: Codable, Equatable {
        var past: [String] = []
        var recent: [String] = []
    }

    @ObservationIgnored private let defaults: UserDefaults?
    private(set) var entries: [String: Entry]

    /// A nil defaults store keeps history in memory, including in snapshot-only test hosts.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        let stored = defaults?.data(forKey: Self.preferenceKey)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        entries = stored.mapValues { entry in
            var seen = Set<String>()
            return Entry(past: Array(entry.past.filter { !$0.isEmpty }.suffix(Self.limit)),
                         recent: Array(entry.recent.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(Self.limit)))
        }
    }

    func previous(on display: String, current: String?, available: Set<String>) -> String? {
        entries[display]?.past.last { $0 != current && available.contains($0) }
    }

    func recent(on display: String, available: Set<String>) -> [String] {
        (entries[display]?.recent ?? []).filter(available.contains)
    }

    /// Call only after saving and confirming the new assignment. Going back consumes the
    /// visited part of the stack, so repeated Previous does not toggle between two wallpapers.
    func recordSwitch(from previous: String?, to wallpaper: String, on display: String,
                      returningToPrevious: Bool = false) {
        guard !wallpaper.isEmpty, wallpaper != previous else { return }
        var entry = entries[display] ?? Entry()
        if returningToPrevious, let index = entry.past.lastIndex(of: wallpaper) {
            entry.past.removeSubrange(index...)
        } else if let previous, !previous.isEmpty, entry.past.last != previous {
            entry.past.append(previous)
        }
        entry.past = Array(entry.past.suffix(Self.limit))
        if let previous, !previous.isEmpty, !entry.recent.contains(previous) {
            entry.recent.insert(previous, at: 0)
        }
        entry.recent.removeAll { $0 == wallpaper }
        entry.recent.insert(wallpaper, at: 0)
        entry.recent = Array(entry.recent.prefix(Self.limit))
        entries[display] = entry
        persist()
    }

    func clear(on display: String) {
        guard entries.removeValue(forKey: display) != nil else { return }
        persist()
    }

    func forget(_ ids: Set<String>) {
        var updated = entries
        for display in updated.keys {
            updated[display]?.past.removeAll(where: ids.contains)
            updated[display]?.recent.removeAll(where: ids.contains)
        }
        guard updated != entries else { return }
        entries = updated
        persist()
    }

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.preferenceKey)
    }
}
