import AppIntents

/// What wallpapers do while a Focus that carries `WallpaperFocusFilter` is on.
enum FocusWallpaperAction: String, AppEnum {
    case keepRunning, mute, pause, stop

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wallpaper playback"
    static let caseDisplayRepresentations: [FocusWallpaperAction: DisplayRepresentation] = [
        .keepRunning: "Keep running",
        .mute: "Mute",
        .pause: "Pause",
        .stop: "Stop (free memory)",
    ]

    /// The rule action it asks for, the same way an app rule's does; nil while it keeps running.
    var ruleAction: AppRuleAction? {
        switch self {
        case .keepRunning: nil
        case .mute: .mute
        case .pause: .pause
        case .stop: .stop
        }
    }
}

/// A Focus filter. In System Settings → Focus, any Focus can add WallpaperMachine's filter to
/// pause, mute or stop wallpapers while it is on. The system performs the filter with the chosen
/// values when the Focus turns on, and with the default values when it turns off, which is why
/// Keep running is the default rather than the most useful choice.
struct WallpaperFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Wallpapers"
    static let description: IntentDescription? = IntentDescription(
        "Pause, mute or stop wallpapers while this Focus is on.")

    @Parameter(title: "Wallpapers", default: .keepRunning)
    var action: FocusWallpaperAction

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Wallpapers", subtitle: FocusWallpaperAction.caseDisplayRepresentations[action]?.title)
    }

    func perform() async throws -> some IntentResult {
        let rule = action.ruleAction
        await MainActor.run { FocusFilterState.shared.set(rule) }
        return .result()
    }

    /// Reads the filter the system has in force, for a Focus that turned on or off while the
    /// app was not running. A system with no Focus using it answers the default, Keep running.
    static func refreshState() async {
        do {
            let rule = try await current.action.ruleAction
            await MainActor.run { FocusFilterState.shared.set(rule) }
        } catch {
            AppLog.info("Focus filter state could not be read: \(error.localizedDescription)")
        }
    }
}
