import Foundation

/// Records completed launch announcements and the user's opt-out, and gathers the bundled
/// release history Settings › About shows on request.
@MainActor
final class WhatsNewStore {
    struct Announcement: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// The first launch of a newer version: the releases since the last announced one.
            case update
            /// Asked for in Settings › About: every bundled release up to this version.
            case history
        }

        var kind = Kind.update
        let currentVersion: String
        /// Older builds never recorded their version; migration must not invent one.
        let previousVersion: String?
        let releases: [AppReleaseHistory.Entry]
        /// Bundled releases older than `releases`, which the window adds on request.
        var earlierReleases: [AppReleaseHistory.Entry] = []
    }

    static let lastVersionKey = "WallpaperMachine.whatsNew.lastVersion"
    static let suppressedKey = "WallpaperMachine.whatsNew.suppressed"
    private let defaults: UserDefaults
    private let currentVersion: SemanticVersion?

    init(defaults: UserDefaults = ClientPreferences.defaults,
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
        // Do not record this version. A bundle that lacks its notes must retry on the
        // next launch, so a later changelog can still announce it.
        guard releases.first?.version == currentVersion, let oldest = releases.last?.version else { return nil }
        return Announcement(currentVersion: currentVersion.display, previousVersion: previous?.display, releases: releases,
                            earlierReleases: history.entries.filter { $0.version < oldest })
    }

    /// Every bundled release this copy has reached, newest first; nil when there is none. Reading
    /// it records nothing, so it never stands in for the post-update announcement.
    func releaseHistory(_ history: AppReleaseHistory) -> Announcement? {
        let releases = history.entries.filter { entry in currentVersion.map { entry.version <= $0 } ?? true }
        guard let newest = releases.first else { return nil }
        return Announcement(kind: .history, currentVersion: currentVersion?.display ?? newest.version.display,
                            previousVersion: nil, releases: releases)
    }

    /// Called only once the window is on screen, so an interrupted launch can retry.
    func didPresent(_ announcement: Announcement) {
        guard announcement.kind == .update, announcement.currentVersion == currentVersion?.display else { return }
        defaults.set(announcement.currentVersion, forKey: Self.lastVersionKey)
    }
}
