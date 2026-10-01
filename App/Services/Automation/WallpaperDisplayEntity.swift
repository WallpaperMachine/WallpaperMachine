import AppIntents

/// A connected independent display, using the same stable id as the panel and URL commands.
struct WallpaperDisplayEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Display"
    static let defaultQuery = WallpaperDisplayQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct WallpaperDisplayQuery: EntityStringQuery {
    func entities(for identifiers: [WallpaperDisplayEntity.ID]) async throws -> [WallpaperDisplayEntity] {
        await Self.all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [WallpaperDisplayEntity] {
        await Self.all().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [WallpaperDisplayEntity] {
        await Self.all()
    }

    private static func all() async -> [WallpaperDisplayEntity] {
        await AppAutomation.shared.availableDisplays().map { WallpaperDisplayEntity(id: $0.id, title: $0.title) }
    }
}
