import Foundation

/// What a Focus filter asks of wallpapers right now, as the system last told
/// `WallpaperFocusFilter`: nothing while no Focus that carries the filter is on. Kept across
/// launches, since a Focus can outlast the app, and read again from the system at launch.
@MainActor
final class FocusFilterState {
    static let shared = FocusFilterState()
    static let didChangeNotification = Notification.Name("WallpaperMachine.focusFilterDidChange")
    private static let key = "WallpaperMachine.focusFilterAction"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The rule action in force; nil while no Focus asks for one.
    var action: AppRuleAction? {
        defaults.string(forKey: Self.key).flatMap(AppRuleAction.init(rawValue:))
    }

    func set(_ action: AppRuleAction?) {
        guard action != self.action else { return }
        if let action {
            defaults.set(action.rawValue, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
        AppLog.info("Focus filter \(action.map { "asks wallpapers to \($0.rawValue)" } ?? "cleared")")
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
