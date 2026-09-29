import Foundation

/// Reports the rule actions that conditions of the whole Mac ask for: Low Power Mode and a hot
/// Mac, each as the user chose under Playback, and whatever a Focus filter set. They join the
/// app rules' actions in `WallpaperPresentationPolicy`, so they pause, mute or stop wallpapers
/// the same way and never change the user's own Play/Pause. Only notifications are observed;
/// nothing is polled.
@MainActor
final class SystemConditionMonitor {
    var onChange: (@MainActor () -> Void)?
    private(set) var actions: Set<AppRuleAction> = []

    private let preferences: PlaybackPreferences
    private let focus: FocusFilterState
    private let systemCenter: NotificationCenter
    private let preferencesCenter: NotificationCenter
    private let isLowPowerModeEnabled: @MainActor () -> Bool
    private let thermalState: @MainActor () -> ProcessInfo.ThermalState
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(
        preferences: PlaybackPreferences,
        focus: FocusFilterState,
        systemCenter: NotificationCenter = .default,
        preferencesCenter: NotificationCenter = .default,
        isLowPowerModeEnabled: (@MainActor () -> Bool)? = nil,
        thermalState: (@MainActor () -> ProcessInfo.ThermalState)? = nil
    ) {
        self.preferences = preferences
        self.focus = focus
        self.systemCenter = systemCenter
        self.preferencesCenter = preferencesCenter
        self.isLowPowerModeEnabled = isLowPowerModeEnabled ?? { ProcessInfo.processInfo.isLowPowerModeEnabled }
        self.thermalState = thermalState ?? { ProcessInfo.processInfo.thermalState }
    }

    /// Serious and critical are the states in which macOS itself starts throttling.
    static func isHot(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }

    func start() {
        guard observers.isEmpty else {
            recompute()
            return
        }
        // ProcessInfo posts both on whichever thread noticed the change.
        let sources: [(NotificationCenter, Notification.Name, AnyObject?)] = [
            (systemCenter, .NSProcessInfoPowerStateDidChange, nil),
            (systemCenter, ProcessInfo.thermalStateDidChangeNotification, nil),
            (preferencesCenter, PlaybackPreferences.didChangeNotification, preferences),
            (preferencesCenter, FocusFilterState.didChangeNotification, focus),
        ]
        for (center, name, object) in sources {
            observers.append((center, center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recompute() }
            }))
        }
        recompute()
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        publish([])
    }

    private func recompute() {
        guard !observers.isEmpty else { return }
        var next = Set<AppRuleAction>()
        if isLowPowerModeEnabled(), let action = preferences.lowPowerModeAction.ruleAction {
            next.insert(action)
        }
        if Self.isHot(thermalState()), let action = preferences.thermalAction.ruleAction {
            next.insert(action)
        }
        if let action = focus.action { next.insert(action) }
        publish(next)
    }

    private func publish(_ next: Set<AppRuleAction>) {
        guard next != actions else { return }
        actions = next
        AppLog.info("system conditions ask wallpapers to \(next.isEmpty ? "run" : next.map(\.rawValue).sorted().joined(separator: ", "))")
        onChange?()
    }
}
