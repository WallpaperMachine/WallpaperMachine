import Foundation

@MainActor
extension WebPanelController {
  func displayLayoutsSnapshot() -> [String: Any] {
    let current = store.displayTransferSnapshot()
    let titles = displayTitles.resolved()
    return ["error": displayLayouts.loadError as Any? ?? NSNull(), "limit": WallpaperDisplayLayoutStore.limit,
      "canSave": (try? WallpaperDisplayTransfer.capture(current)) != nil,
      "items": displayLayouts.layouts.map { layout in
        let failure: String?
        do { try WallpaperDisplayTransfer.validate(layout.assignments, in: current); failure = nil }
        catch { failure = error.localizedDescription }
        return ["id": layout.id, "name": layout.name, "unavailable": failure as Any? ?? NSNull(),
          "assignments": layout.assignments.map { value in
            ["displayID": value.displayID, "displayTitle": titles.title(value.displayTitle, displayId: value.displayID),
             "wallpaperID": value.wallpaperID,
             "wallpaperTitle": store.librarySnapshot.wallpapers.first { $0.id == value.wallpaperID }?.title ?? value.wallpaperID]
          }] as [String: Any]
      }]
  }

  func performDisplayLayouts(_ action: String, request: WebPanelRequest) async throws -> Bool {
    switch action {
    case "displayLayoutSave":
      let name = try request.string("name")
      try await store.commands.run {
        let titles = displayTitles.resolved()
        let values = try WallpaperDisplayTransfer.capture(store.displayTransferSnapshot()).map { value in
          var value = value
          value.displayTitle = titles.title(value.displayTitle, displayId: value.displayID)
          return value
        }
        try displayLayouts.save(name: name, assignments: values)
      }
    case "displayLayoutRename": try displayLayouts.rename(request.string("layoutID"), name: request.string("name"))
    case "displayLayoutDelete": try displayLayouts.delete(request.string("layoutID"))
    case "displayLayoutApply":
      let layout = try displayLayouts.layout(request.string("layoutID"))
      try await store.applyDisplayTransferAsync(.layout(layout.assignments))
    case "displayCopyWallpaper":
      try await store.applyDisplayTransferAsync(.copy(from: request.string("sourceID"), to: request.string("targetID")))
    case "displaySwapWallpapers":
      try await store.applyDisplayTransferAsync(.swap(request.string("sourceID"), request.string("targetID")))
    default: return false
    }
    return true
  }
}
