import AppIntents

/// What wallpapers do while a Focus that carries `WallpaperFocusFilter` is on.
enum FocusWallpaperAction: String, AppEnum {
    case keepRunning, mute, pause, stop, wallpaper, playlist

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wallpaper playback"
    static let caseDisplayRepresentations: [FocusWallpaperAction: DisplayRepresentation] = [
        .keepRunning: "Keep running",
        .mute: "Mute",
        .pause: "Pause",
        .stop: "Stop (free memory)",
        .wallpaper: "Use wallpaper",
        .playlist: "Use saved playlist",
    ]

    /// The rule action it asks for, the same way an app rule's does; nil while it keeps running.
    var ruleAction: AppRuleAction? {
        switch self {
        case .keepRunning, .wallpaper, .playlist: nil
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
        "Pause, mute or stop wallpapers, or temporarily use a wallpaper or saved playlist while this Focus is on.")

    @Parameter(title: "Wallpapers", default: .keepRunning)
    var action: FocusWallpaperAction

    @Parameter(title: "Wallpaper") var wallpaper: WallpaperEntity?
    @Parameter(title: "Saved playlist") var playlist: WallpaperPlaylistEntity?
    @Parameter(title: "Display") var display: WallpaperDisplayEntity?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Wallpapers", subtitle: FocusWallpaperAction.caseDisplayRepresentations[action]?.title)
    }

    func perform() async throws -> some IntentResult {
        let rule = action.ruleAction
        let selection = try wallpaperSelection()
        await MainActor.run { FocusFilterState.shared.set(rule, selection: selection) }
        return .result()
    }

    /// Reads the filter the system has in force, for a Focus that turned on or off while the
    /// app was not running. A system with no Focus using it answers the default, Keep running.
    static func refreshState() async {
        do {
            let filter = try await current
            let rule = filter.action.ruleAction
            let selection = try filter.wallpaperSelection()
            await MainActor.run { FocusFilterState.shared.set(rule, selection: selection) }
        } catch {
            AppLog.info("Focus filter state could not be read: \(error.localizedDescription)")
        }
    }

    func wallpaperSelection() throws -> FocusWallpaperSelection? {
        let target: WallpaperAutomationTarget
        switch action {
        case .wallpaper:
            guard let wallpaper else { throw AutomationError(message: String(localized: "Choose a wallpaper for this Focus filter.")) }
            target = .init(kind: .wallpaper, id: wallpaper.id)
        case .playlist:
            guard let playlist else { throw AutomationError(message: String(localized: "Choose a saved playlist for this Focus filter.")) }
            target = .init(kind: .playlist, id: playlist.id)
        default: return nil
        }
        return .init(target: target, displayID: display?.id)
    }
}
