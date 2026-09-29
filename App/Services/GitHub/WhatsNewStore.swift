import Foundation

/// Records completed launch announcements and the user's permanent opt-out.
@MainActor
final class WhatsNewStore {
    struct Announcement: Equatable, Sendable {
        let currentVersion: String
        /// Older builds never recorded their version; migration must not invent one.
        let previousVersion: String?
        let releases: [AppReleaseHistory.Entry]
    }

    static let lastVersionKey = "WallpaperMachine.whatsNew.lastVersion"
    static let suppressedKey = "WallpaperMachine.whatsNew.suppressed"
    private let defaults: UserDefaults
    private let currentVersion: SemanticVersion?

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") {
        self.defaults = defaults
        self.currentVersion = SemanticVersion(currentVersion)
    }

    var isSuppressed: Bool {
        get { defaults.bool(forKey: Self.suppressedKey) }
        set { defaults.set(newValue, forKey: Self.suppressedKey) }
    }

    func announcement(history: AppReleaseHistory, existingUser: Bool) -> Announcement? {
        guard let currentVersion else { return nil }
        let previous = defaults.string(forKey: Self.lastVersionKey).flatMap(SemanticVersion.init)
        // Keep a high-water mark: a downgrade and return to the same release is not an update.
        if let previous, currentVersion <= previous { return nil }
        if isSuppressed || (previous == nil && !existingUser) {
            defaults.set(currentVersion.display, forKey: Self.lastVersionKey)
            return nil
        }
        let releases = history.entries.filter { entry in
            entry.version <= currentVersion
                && (previous.map { entry.version > $0 } ?? (entry.version == currentVersion))
        }
        guard releases.first?.version == currentVersion else { return nil }
        return Announcement(currentVersion: currentVersion.display, previousVersion: previous?.display, releases: releases)
    }

    /// Called only once the window is on screen, so an interrupted launch can retry.
    func didPresent(_ announcement: Announcement) {
        guard announcement.currentVersion == currentVersion?.display else { return }
        defaults.set(announcement.currentVersion, forKey: Self.lastVersionKey)
    }
}
