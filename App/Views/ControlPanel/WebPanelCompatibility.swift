import Foundation

@MainActor
extension WebPanelController {
  func performCompatibility(_ action: String, request: WebPanelRequest) async throws -> Bool {
    guard action == "compatibilityCheck" else { return false }
    let id = try wallpaperID(request)
    let displayID = try request.string("displayID")
    guard store.wallpaperOptionsSnapshot?.wallpaperId == id else {
      throw WallpaperActionError(message: String(localized: "Wallpaper settings are unavailable. Refresh Library and retry."))
    }
    guard id == store.appSnapshot.selectedWallpaperId,
          displayID == navigation.targetDisplayID,
          let context = compatibilityContext(),
          context.wallpaperID == id, context.displayID == displayID,
          context.targetAvailable else { throw WebPanelRequest.invalid }
    await compatibility.check(context, retry: true)
    return true
  }

  func trackCompatibilityDependencies() {
    _ = compatibility.checking
    _ = compatibility.checks
    _ = compatibility.context
  }

  /// Filesystem work is explicit, never a side effect of building a page snapshot.
  /// Live reports deliberately stay outside the cache: preferences are not backend evidence.
  func compatibilitySnapshot() -> [String: Any] {
    let context = compatibilityContext()
    compatibility.select(context)
    guard let context else { return ["wallpaperCompatibility": NSNull()] }
    var payload: [String: Any] = [
      "wallpaperID": context.wallpaperID, "displayID": context.displayID,
      "checking": compatibility.checking,
      "checks": compatibility.checks.map {
        ["id": $0.id, "status": $0.status.rawValue, "title": $0.title, "detail": $0.detail]
      },
    ]
    let settings = store.settingsSnapshot
    let displayTitle = settings.displays.first { $0.displayId == context.displayID }?.title ?? ""
    let physicalID = ResolvedDisplayTitles.liveDisplayID(context.displayID, title: displayTitle)
    if let report = settings.videoBackends.first(where: {
      $0.wallpaperId == context.wallpaperID && $0.displayId == physicalID
    }) {
      payload["backend"] = report.backend
      payload["reason"] = report.fallbackReason
    } else if let report = settings.sceneRenderers.first(where: {
      $0.wallpaperId == context.wallpaperID && $0.displayId == physicalID
    }) {
      payload["backend"] = report.backend
      payload["reason"] = report.fallbackReason
    }
    // Absence of a report is unavailable evidence, not an inferred Compatibility backend.
    return ["wallpaperCompatibility": payload]
  }

  private func compatibilityContext() -> WallpaperCompatibilityContext? {
    guard let id = store.appSnapshot.selectedWallpaperId,
          let entry = store.librarySnapshot.wallpapers.first(where: { $0.id == id }) else { return nil }
    let settings = store.settingsSnapshot
    let displayID = navigation.targetDisplayID
    let display = settings.displays.first { $0.displayId == displayID }
    let available = display?.enabled == true && display?.mode == .standalone
    let options = store.wallpaperOptionsSnapshot.flatMap { $0.wallpaperId == id ? $0 : nil }
    let configuration = options?.displayConfigurations.first { $0.displayId == displayID }
    var fps = min(configuration?.targetFps ?? display?.targetFps ?? 0, display?.maxFps ?? 0)
    // Native admission is a mirror-group decision. Do not certify a 60 FPS
    // source when a 30 FPS mirror requires the whole group to fall back.
    for mirror in settings.displays where mirror.enabled && mirror.mode == .mirror
      && mirror.selectedMirrorTarget == displayID {
      fps = min(fps, min(mirror.targetFps, mirror.maxFps))
    }
    if let cap = settings.frameRateCap { fps = min(fps, max(1, cap)) }
    let kind: WallpaperCompatibilityContext.Kind
    switch entry.kind {
    case .projectScene: kind = .scene
    case .video: kind = .video
    case .webpage: kind = .web
    case .unknown: kind = .unknown
    }
    // Reading the configured path is cheap; selecting/probing a usable assets
    // folder happens on the service actor, not through ClientPaths.assetsURL here.
    let assetsConfiguration = ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_ASSETS_ROOT"]
      ?? ClientPreferences.defaults.string(forKey: "WallpaperMachineAssetsPath") ?? ""
    return .init(wallpaperID: id, displayID: displayID, kind: kind, supported: entry.supported,
                 targetFPS: fps, targetAvailable: available && options != nil && fps > 0,
                 videoBackend: settings.videoBackend, sceneRenderer: settings.sceneRenderer,
                 libraryRevision: store.libraryRefreshRevision, assetsConfiguration: assetsConfiguration)
  }
}
