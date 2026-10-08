import AppIntents

struct WallpaperDisplayLayoutEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Display layout"
    static let defaultQuery = WallpaperDisplayLayoutQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }
}

struct WallpaperDisplayLayoutQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WallpaperDisplayLayoutEntity] {
        await all().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [WallpaperDisplayLayoutEntity] {
        await all().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [WallpaperDisplayLayoutEntity] { await all() }
    private func all() async -> [WallpaperDisplayLayoutEntity] {
        await AppAutomation.shared.availableDisplayLayouts().map { .init(id: $0.id, title: $0.title) }
    }
}

struct ApplyWallpaperDisplayLayoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Display Layout"
    static let description: IntentDescription? = IntentDescription(
        "Restores saved wallpaper choices across independent displays. All saved displays and wallpapers must be available.")
    @Parameter(title: "Display layout") var layout: WallpaperDisplayLayoutEntity
    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.applyDisplayLayout(layoutID: layout.id))
        return .result()
    }
}

struct WallpaperPlaylistEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved playlist"
    static let defaultQuery = WallpaperPlaylistQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }
}

struct WallpaperPlaylistQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WallpaperPlaylistEntity] {
        await all().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [WallpaperPlaylistEntity] {
        await all().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [WallpaperPlaylistEntity] { await all() }
    private func all() async -> [WallpaperPlaylistEntity] {
        await AppAutomation.shared.availablePlaylistPlans().map { .init(id: $0.id, title: $0.title) }
    }
}

struct WallpaperPropertyPresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wallpaper property preset"
    static let defaultQuery = WallpaperPropertyPresetQuery()
    let id: String
    let title: String
    let wallpaper: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)", subtitle: "\(wallpaper)") }
}

struct WallpaperPropertyPresetQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WallpaperPropertyPresetEntity] {
        await all().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [WallpaperPropertyPresetEntity] {
        await all().filter { $0.title.localizedCaseInsensitiveContains(string) || $0.wallpaper.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [WallpaperPropertyPresetEntity] { await all() }
    private func all() async -> [WallpaperPropertyPresetEntity] {
        await AppAutomation.shared.availablePropertyPresets().map { .init(id: $0.id, title: $0.title, wallpaper: $0.wallpaper) }
    }
}

struct ApplyWallpaperPlaylistIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Saved Playlist"
    static let description: IntentDescription? = IntentDescription(
        "Copies a saved playlist to a display. Playback starts when that display can play.")
    @Parameter(title: "Saved playlist") var playlist: WallpaperPlaylistEntity
    @Parameter(title: "Display") var display: WallpaperDisplayEntity?
    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.applyPlaylist(planID: playlist.id, display: display?.id))
        return .result()
    }
}

struct ApplyWallpaperPropertyPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Wallpaper Property Preset"
    static let description: IntentDescription? = IntentDescription(
        "Applies saved properties to their wallpaper on every display using it. Unapplied edits must be applied or reverted first.")
    @Parameter(title: "Property preset") var preset: WallpaperPropertyPresetEntity
    func perform() async throws -> some IntentResult {
        try await AppAutomation.shared.perform(.applyPreset(presetID: preset.id))
        return .result()
    }
}
