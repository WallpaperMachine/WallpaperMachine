import AppIntents

/// An installed wallpaper as the Shortcuts app lists and chooses it.
struct WallpaperEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wallpaper"
    static let defaultQuery = WallpaperQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

/// The installed wallpapers that can play, in library order.
struct WallpaperQuery: EntityStringQuery {
    func entities(for identifiers: [WallpaperEntity.ID]) async throws -> [WallpaperEntity] {
        await Self.all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [WallpaperEntity] {
        await Self.all().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [WallpaperEntity] {
        await Self.all()
    }

    private static func all() async -> [WallpaperEntity] {
        await AppAutomation.shared.availableWallpapers().map { WallpaperEntity(id: $0.id, title: $0.title) }
    }
}

struct PauseWallpapersIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Wallpapers"
    static let description: IntentDescription? = IntentDescription("Pauses every wallpaper, as Pause in the menu bar does.")

    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.pause)
        return .result()
    }
}

struct ResumeWallpapersIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Wallpapers"
    static let description: IntentDescription? = IntentDescription("Plays every wallpaper again after a pause.")

    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.play)
        return .result()
    }
}

struct ToggleWallpaperPlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause Wallpapers"
    static let description: IntentDescription? = IntentDescription("Pauses wallpapers that are playing, and plays them when paused.")

    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.togglePlayback)
        return .result()
    }
}

struct NextWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Wallpaper"
    static let description: IntentDescription? = IntentDescription(
        "Changes the target display to its next wallpaper: its playlist's next when it rotates, otherwise the next one in your library.")

    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.next(display: nil))
        return .result()
    }
}

struct ApplyWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Wallpaper"
    static let description: IntentDescription? = IntentDescription("Applies an installed wallpaper to the target display.")

    @Parameter(title: "Wallpaper")
    var wallpaper: WallpaperEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$wallpaper)")
    }

    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.apply(wallpaperID: wallpaper.id, display: nil))
        return .result()
    }
}

struct OpenControlPanelIntent: AppIntent {
    static let title: LocalizedStringResource = "Open WallpaperMachine"
    static let description: IntentDescription? = IntentDescription("Opens the control panel.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.open(page: nil))
        return .result()
    }
}

/// The actions Siri and Spotlight offer without the user building a shortcut first.
struct WallpaperMachineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleWallpaperPlaybackIntent(),
            phrases: ["Play or pause \(.applicationName)", "Play or pause wallpapers in \(.applicationName)"],
            shortTitle: "Play or Pause", systemImageName: "playpause")
        AppShortcut(
            intent: NextWallpaperIntent(),
            phrases: ["Next wallpaper in \(.applicationName)", "Change wallpaper with \(.applicationName)"],
            shortTitle: "Next Wallpaper", systemImageName: "forward")
        AppShortcut(
            intent: ApplyWallpaperIntent(),
            phrases: ["Apply a wallpaper with \(.applicationName)"],
            shortTitle: "Apply Wallpaper", systemImageName: "photo.on.rectangle")
    }
}
