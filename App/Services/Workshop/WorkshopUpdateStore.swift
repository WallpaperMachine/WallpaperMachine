import Foundation
import Observation

/// Which installed Workshop wallpapers their authors have changed since they were installed.
///
/// A wallpaper counts as installed from the moment this app finished downloading it. One it did
/// not download (imported, or downloaded before installs were recorded) counts from when its
/// `project.json` was last written, which for an import is when it was copied in, so an import
/// that was already out of date is not caught. Steam's public details endpoint says when each
/// item last changed; it needs no sign-in, and only the items' ids are sent.
@MainActor
@Observable
final class WorkshopUpdateStore {
    /// Installed items with a newer version on the Workshop, with Steam's current details.
    private(set) var available: [String: WorkshopItem] = [:]
    private(set) var isChecking = false
    private(set) var lastChecked: Date?
    private(set) var errorMessage: String?
    /// Whether the app checks by itself, at most once a day. On unless turned off.
    var checksAutomatically: Bool {
        didSet { defaults.set(checksAutomatically, forKey: Self.automaticKey) }
    }

    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// Steam's clock and this Mac's may disagree a little; a change within this of the install
    /// is the version that was installed.
    nonisolated static let tolerance: TimeInterval = 60
    private static let installedKey = "WallpaperMachine.workshopInstalledAt"
    private static let availableKey = "WallpaperMachine.workshopUpdates"
    private static let lastCheckedKey = "WallpaperMachine.workshopUpdatesCheckedAt"
    private static let automaticKey = "WallpaperMachine.workshopUpdateChecks"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: @Sendable ([String]) async throws -> [WorkshopItem]
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var installedAt: [String: Date]
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        fetch: @escaping @Sendable ([String]) async throws -> [WorkshopItem] = { try await WorkshopService().details(ids: $0) },
        now: (@MainActor () -> Date)? = nil
    ) {
        self.defaults = defaults
        self.fetch = fetch
        self.now = now ?? { Date() }
        checksAutomatically = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        installedAt = (defaults.dictionary(forKey: Self.installedKey) as? [String: Double] ?? [:])
            .mapValues(Date.init(timeIntervalSince1970:))
        available = (defaults.data(forKey: Self.availableKey))
            .flatMap { try? JSONDecoder().decode([WorkshopItem].self, from: $0) }
            .map { Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) } ?? [:]
        lastChecked = (defaults.object(forKey: Self.lastCheckedKey) as? Double).map(Date.init(timeIntervalSince1970:))
    }

    /// Workshop ids are numbers; anything else in the library came from somewhere else.
    nonisolated static func isWorkshopID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && $0.isNumber } && UInt64(id) != nil
    }

    /// Checks `installed` (the library's wallpaper ids) against the Workshop, unless a check is
    /// already running. `library` is where their folders are.
    func check(installed: [String], library: URL) {
        guard task == nil else { return }
        let ids = installed.filter(Self.isWorkshopID)
        let recorded = installedAt
        let fetch = fetch
        isChecking = true
        errorMessage = nil
        task = Task { [weak self] in
            do {
                // Reading each project.json's date is file-system work; it stays off the main actor.
                let local = await Task.detached(priority: .utility) {
                    Self.localVersions(ids, recorded: recorded, library: library)
                }.value
                let remote = ids.isEmpty ? [] : try await fetch(ids)
                self?.finish(Self.outdated(remote: remote, local: local))
            } catch {
                self?.fail(error)
            }
        }
    }

    /// Checks when automatic checks are on and the last check is a day old.
    func checkIfDue(installed: [String], library: URL) {
        guard checksAutomatically else { return }
        if let lastChecked, now().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        check(installed: installed, library: library)
    }

    /// Records that `id` was just downloaded, which makes it current.
    func recordInstalled(_ id: String) {
        installedAt[id] = now()
        available[id] = nil
        persist()
    }

    /// Drops wallpapers that left the library.
    func forget(_ ids: [String]) {
        for id in ids {
            installedAt[id] = nil
            available[id] = nil
        }
        persist()
    }

    /// The items whose Workshop version is newer than the one installed.
    nonisolated static func outdated(remote: [WorkshopItem], local: [String: Date]) -> [String: WorkshopItem] {
        var outdated: [String: WorkshopItem] = [:]
        for item in remote {
            guard let changed = item.timeUpdated, let installed = local[item.id],
                  changed > installed.addingTimeInterval(tolerance) else { continue }
            outdated[item.id] = item
        }
        return outdated
    }

    /// When each installed item was installed: recorded downloads first, then the date its
    /// `project.json` was last written. An item with neither is left out and never flagged.
    nonisolated static func localVersions(_ ids: [String], recorded: [String: Date], library: URL) -> [String: Date] {
        var versions: [String: Date] = [:]
        for id in ids {
            if let date = recorded[id] {
                versions[id] = date
            } else if let date = try? library.appendingPathComponent(id).appendingPathComponent("project.json")
                .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            {
                versions[id] = date
            }
        }
        return versions
    }

    private func finish(_ outdated: [String: WorkshopItem]) {
        available = outdated
        lastChecked = now()
        isChecking = false
        task = nil
        AppLog.info("Workshop update check: \(outdated.count) of the installed items have updates")
        persist()
    }

    private func fail(_ error: Error) {
        errorMessage = String(localized: "Couldn’t check the Workshop for updates: \(error.localizedDescription)")
        isChecking = false
        task = nil
        AppLog.warn("Workshop update check failed: \(error.localizedDescription)")
    }

    private func persist() {
        defaults.set(installedAt.mapValues(\.timeIntervalSince1970), forKey: Self.installedKey)
        if let data = try? JSONEncoder().encode(available.values.sorted { $0.id < $1.id }) {
            defaults.set(data, forKey: Self.availableKey)
        }
        if let lastChecked {
            defaults.set(lastChecked.timeIntervalSince1970, forKey: Self.lastCheckedKey)
        }
    }
}
