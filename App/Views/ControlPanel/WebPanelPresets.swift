import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension WebPanelController {
  /// Called inside the incumbent command queue, so the validated edit/apply sequence is indivisible.
  func performPresets(_ action: String, request: WebPanelRequest) async throws -> Bool {
    switch action {
    case "wallpaperPresetSave":
      let id = try wallpaperID(request)
      let options = try await store.wallpaperOptionsSnapshotAsync(wallpaperId: id)
      let pending = store.editorState.hasPendingEdits(wallpaperID: id) || store.isWallpaperEditInProgress(id: id)
      _ = try await presets.save(name: request.string("name"), options: options, hasPendingEdits: pending)
      presets.status = String(localized: "Saved the applied wallpaper properties.")
    case "wallpaperPresetRename":
      try presets.rename(id: request.string("presetID"), name: request.string("name"))
    case "wallpaperPresetDelete":
      let preset = try presets.preset(id: request.string("presetID"))
      let options = try await store.wallpaperOptionsSnapshotAsync(wallpaperId: preset.wallpaperID)
      try presets.requireClean(options, hasPendingEdits: store.editorState.hasPendingEdits(wallpaperID: preset.wallpaperID)
        || store.isWallpaperEditInProgress(id: preset.wallpaperID))
      try await presets.delete(id: preset.id, preservingPaths: WallpaperPresetStore.resourcePaths(options))
    case "wallpaperPresetApply":
      let id = try wallpaperID(request)
      let preset = try presets.preset(id: request.string("presetID"))
      let options = try await store.wallpaperOptionsSnapshotAsync(wallpaperId: id)
      try await presets.apply(preset, options: options, bridge: store, userInitiated: true)
      presets.status = String(localized: "Property preset applied.")
    case "wallpaperPresetExport":
      let id = try wallpaperID(request)
      let preset = try presets.preset(id: request.string("presetID"))
      guard preset.wallpaperID == id else { throw WebPanelRequest.invalid }
      let data = try await presets.exportDocument(id: preset.id)
      let name = "wallpaper-properties.json"
      let url: URL?
      if let choose = presets.chooseExportFile { url = await choose(name) }
      else {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Property Preset")
        panel.message = String(localized: "Managed assets up to 32 MB are bundled. External file references are not portable.")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name
        url = await choose(panel) ? panel.url : nil
      }
      guard let url else { return true }
      try await Task.detached(priority: .utility) { try data.write(to: url, options: .atomic) }.value
      presets.status = String(localized: "Property preset exported. External file references require choosing the files again after import.")
    case "wallpaperPresetImport":
      let id = try wallpaperID(request)
      let url: URL?
      if let choose = presets.chooseImportFile { url = await choose() }
      else {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Property Preset")
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        url = await choose(panel) ? panel.url : nil
      }
      guard let url else { return true }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let data = try await Task.detached(priority: .utility) {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= WallpaperPresetStore.maximumDocumentBytes else {
          throw WebPanelRequest.invalid
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= WallpaperPresetStore.maximumDocumentBytes else { throw WebPanelRequest.invalid }
        return data
      }.value
      let options = try await store.wallpaperOptionsSnapshotAsync(wallpaperId: id)
      _ = try await presets.importDocument(data, options: options)
      presets.status = String(localized: "Property preset imported. Apply it to change this wallpaper.")
    default: return false
    }
    return true
  }

  func wallpaperPresetsSnapshot() -> [String: Any] {
    guard let id = store.appSnapshot.selectedWallpaperId,
          store.librarySnapshot.wallpapers.contains(where: { $0.id == id }) else {
      return ["wallpaperID": NSNull(), "items": [], "canSave": false]
    }
    let options = store.wallpaperOptionsSnapshot.flatMap { $0.wallpaperId == id ? $0 : nil }
    let clean = options?.supported == true && options?.dirty == false
      && !store.editorState.hasPendingEdits(wallpaperID: id) && !store.isWallpaperEditInProgress(id: id)
      && !store.commands.isBusy && store.activatingWallpaperID == nil && store.applyingWallpaperID == nil
    return [
      "wallpaperID": id,
      "items": presets.presets(wallpaperID: id).map { ["id": $0.id, "name": $0.name] },
      "canSave": clean && presets.error == nil,
      "status": presets.status as Any? ?? NSNull(),
      "error": presets.error as Any? ?? NSNull(),
    ]
  }
}
