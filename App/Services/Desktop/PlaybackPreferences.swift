import Foundation

enum DisplaySleepAction: String, Codable, CaseIterable, Sendable {
    case pause
    case stop
}

enum OtherAudioAction: String, Codable, CaseIterable, Sendable {
    case keepRunning
    case mute
    case pause
}

/// What a wallpaper does while other windows cover its display's working area.
enum DesktopCoveredAction: String, Codable, CaseIterable, Sendable {
    case pause
    case keepRunning
}

/// What wallpapers do while a condition of the whole Mac holds: Low Power Mode, or macOS
/// reporting it hot.
enum SystemConditionAction: String, Codable, CaseIterable, Sendable {
    case keepRunning
    case pause
    case stop

    /// The rule action it contributes, the same way an app rule's does; nil while it keeps running.
    var ruleAction: AppRuleAction? {
        switch self {
        case .keepRunning: nil
        case .pause: .pause
        case .stop: .stop
        }
    }
}

enum AppRuleCondition: String, Codable, CaseIterable, Sendable {
    case running
    case frontmost
}

enum AppRuleAction: String, Codable, CaseIterable, Sendable {
    case pause
    case mute
    case stop
}

struct AppRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var bundleIdentifier: String
    var name: String
    var condition: AppRuleCondition
    var action: AppRuleAction
}

/// UserDefaults-backed playback rules for display sleep, other-app audio, a
/// covered desktop, Low Power Mode, a hot Mac and per-app pause, mute and stop. Mutations post
/// `didChangeNotification` once.
@MainActor
final class PlaybackPreferences {
    static let didChangeNotification = Notification.Name("WallpaperMachine.playbackPreferencesDidChange")
    static let shared = PlaybackPreferences()

    struct UnknownRule: LocalizedError, Equatable {
        var errorDescription: String? {
            String(localized: "That app rule no longer exists.")
        }
    }

    private static let displaySleepKey = "WallpaperMachine.displaySleepAction"
    private static let otherAudioKey = "WallpaperMachine.otherAudioAction"
    private static let desktopCoveredKey = "WallpaperMachine.desktopCoveredAction"
    private static let appRulesKey = "WallpaperMachine.appRules"
    private static let lowPowerModeKey = "WallpaperMachine.lowPowerModeAction"
    private static let thermalKey = "WallpaperMachine.thermalAction"
    private static let periodicDesktopPictureKey = "WallpaperMachine.refreshDesktopPicturePeriodically"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = ClientPreferences.defaults) {
        self.defaults = defaults
        appRules = Self.loadRules(from: defaults)
    }

    var displaySleepAction: DisplaySleepAction {
        get { storedEnum(Self.displaySleepKey, default: .pause) }
        set { store(newValue.rawValue, forKey: Self.displaySleepKey) }
    }

    var otherAudioAction: OtherAudioAction {
        get { storedEnum(Self.otherAudioKey, default: .keepRunning) }
        set { store(newValue.rawValue, forKey: Self.otherAudioKey) }
    }

    var desktopCoveredAction: DesktopCoveredAction {
        get { storedEnum(Self.desktopCoveredKey, default: .pause) }
        set { store(newValue.rawValue, forKey: Self.desktopCoveredKey) }
    }

    /// Off until chosen, like battery: Low Power Mode alone never changes playback.
    var lowPowerModeAction: SystemConditionAction {
        get { storedEnum(Self.lowPowerModeKey, default: .keepRunning) }
        set { store(newValue.rawValue, forKey: Self.lowPowerModeKey) }
    }

    /// Applies while macOS reports the thermal state as serious or critical.
    var thermalAction: SystemConditionAction {
        get { storedEnum(Self.thermalKey, default: .keepRunning) }
        set { store(newValue.rawValue, forKey: Self.thermalKey) }
    }

    /// Off by default: the still picture Mission Control shows is otherwise
    /// taken again only when a wallpaper starts, changes or resumes.
    var refreshesDesktopPicturePeriodically: Bool {
        get { defaults.bool(forKey: Self.periodicDesktopPictureKey) }
        set {
            defaults.set(newValue, forKey: Self.periodicDesktopPictureKey)
            postChange()
        }
    }

    private(set) var appRules: [AppRule]

    @discardableResult
    func addRule(bundleIdentifier: String, name: String) -> AppRule {
        if let existing = appRules.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return existing
        }
        let rule = AppRule(
            id: UUID(),
            bundleIdentifier: bundleIdentifier,
            name: name,
            condition: .running,
            action: .pause)
        appRules.append(rule)
        persistRules()
        return rule
    }

    func updateRule(id: UUID, condition: AppRuleCondition) throws {
        guard let index = appRules.firstIndex(where: { $0.id == id }) else { throw UnknownRule() }
        appRules[index].condition = condition
        persistRules()
    }

    func updateRule(id: UUID, action: AppRuleAction) throws {
        guard let index = appRules.firstIndex(where: { $0.id == id }) else { throw UnknownRule() }
        appRules[index].action = action
        persistRules()
    }

    func removeRule(id: UUID) {
        let count = appRules.count
        appRules.removeAll { $0.id == id }
        guard appRules.count != count else { return }
        persistRules()
    }

    private func storedEnum<T: RawRepresentable>(_ key: String, default fallback: T) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else { return fallback }
        return value
    }

    private func store(_ raw: String, forKey key: String) {
        defaults.set(raw, forKey: key)
        postChange()
    }

    private func persistRules() {
        guard let data = try? JSONEncoder().encode(appRules) else { return }
        defaults.set(data, forKey: Self.appRulesKey)
        postChange()
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func loadRules(from defaults: UserDefaults) -> [AppRule] {
        guard let data = defaults.data(forKey: appRulesKey),
              let decoded = try? JSONDecoder().decode([AppRule].self, from: data) else { return [] }
        return decoded
    }
}
