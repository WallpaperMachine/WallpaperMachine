import Foundation

@MainActor
extension WebPanelController {
  func wallpaperAutomationSnapshot() -> [String: Any] {
    let null = NSNull()
    func target(_ value: WallpaperAutomationTarget?) -> Any {
      value.map { ["kind": $0.kind.rawValue, "id": $0.id] } as Any? ?? null
    }
    var displays: [String: Any] = [:]
    for display in store.settingsSnapshot.displays {
      let value = automations.configuration(for: display.displayId)
      let physical = spaces.physicalDisplay(display.displayId, title: display.title)
      let desktops = physical.flatMap { spaces.displays[$0] }
      let blocked = store.lockScreenWallpaper?.isRequested == true || store.lockScreenWallpaper?.ownsDesktopProvider == true
      displays[display.displayId] = [
        "mode": value.mode.rawValue,
        "light": target(value.light), "dark": target(value.dark),
        "rules": value.rules.map { rule in
          ["id": rule.id, "weekdays": rule.weekdays.sorted(), "event": rule.event.rawValue,
           "minute": rule.minute, "offset": rule.offset, "target": target(rule.target)] as [String: Any]
        },
        "next": automations.next[display.displayId].map { $0.date.timeIntervalSince1970 * 1000 } as Any? ?? null,
        "nextTarget": target(automations.next[display.displayId]?.target),
        "focused": automations.focusedDisplays.contains(display.displayId),
        "error": automations.errors[display.displayId] as Any? ?? null,
        "spacesAvailable": spaces.available && desktops != nil && !blocked,
        "spacesBlocked": blocked,
        "currentSpace": desktops?.current as Any? ?? null,
        "spaces": (desktops?.spaces ?? []).map { ["id": $0.id, "number": $0.number, "target": target(value.spaces[$0.id])] as [String: Any] },
        "missingSpaces": desktops.map { info in value.spaces.keys.filter { id in !info.spaces.contains { $0.id == id } }.sorted().map {
          ["id": $0, "target": target(value.spaces[$0])] as [String: Any]
        }} ?? [],
      ]
    }
    return ["displays": displays,
      "location": automations.location.map { ["latitude": $0.latitude, "longitude": $0.longitude] } as Any? ?? null,
      "error": automations.loadError as Any? ?? null]
  }

  func performWallpaperAutomation(_ action: String, request: WebPanelRequest) throws -> Bool {
    switch action {
    case "automationMode":
      let display = try playlistDisplay(request)
      guard let mode = DisplayWallpaperAutomation.Mode(rawValue: try request.string("value")) else { throw WebPanelRequest.invalid }
      if mode == .spaces { _ = try requireSpaceInformation(display) }
      try automations.update(display) { $0.mode = mode }
    case "automationSpace":
      let display = try playlistDisplay(request)
      let id = try request.string("spaceID")
      let target = try automationTarget(request.body["target"], optional: true)
      if target != nil {
        let info = try requireSpaceInformation(display)
        guard info.spaces.contains(where: { $0.id == id }) else { throw WebPanelRequest.invalid }
      } else if automations.configuration(for: display).spaces[id] == nil { throw WebPanelRequest.invalid }
      try automations.update(display) { $0.spaces[id] = target }
    case "automationRefreshSpaces": spaces.refresh()
    case "automationAppearance":
      let display = try playlistDisplay(request)
      let key = try request.string("key")
      guard key == "light" || key == "dark" else { throw WebPanelRequest.invalid }
      let target = try automationTarget(request.body["target"], optional: true)
      try automations.update(display) { if key == "light" { $0.light = target } else { $0.dark = target } }
    case "automationRuleSave":
      let display = try playlistDisplay(request)
      guard let raw = request.body["rule"] as? [String: Any] else { throw WebPanelRequest.invalid }
      let fields = WebPanelRequest(raw)
      guard let event = WallpaperAutomationRule.Event(rawValue: try fields.string("event")),
            let rawDays = raw["weekdays"] as? [Any], rawDays.count <= 7,
            let target = try automationTarget(raw["target"], optional: false) else { throw WebPanelRequest.invalid }
      let days = try rawDays.map { value -> Int in
        let day = try WebPanelRequest(["day": value]).number("day", range: 1...7)
        guard day == day.rounded() else { throw WebPanelRequest.invalid }
        return Int(day)
      }
      let minute = try fields.number("minute", range: 0...1439)
      let offset = try fields.number("offset", range: -180...180)
      guard Set(days).count == days.count, minute == minute.rounded(), offset == offset.rounded() else { throw WebPanelRequest.invalid }
      var rule = WallpaperAutomationRule(weekdays: Set(days), event: event,
        minute: Int(minute), offset: Int(offset), target: target)
      if let id = raw["id"] as? String, !id.isEmpty {
        guard automations.configuration(for: display).rules.contains(where: { $0.id == id }) else { throw WebPanelRequest.invalid }
        rule.id = id
      }
      try automations.saveRule(rule, on: display)
    case "automationRuleRemove":
      try automations.removeRule(request.string("id"), from: playlistDisplay(request))
    case "automationLocation":
      let location = WallpaperSolarLocation(latitude: try request.number("latitude", range: -90...90), longitude: try request.number("longitude", range: -180...180))
      try automations.setLocation(location)
    case "automationClearLocation": try automations.setLocation(nil)
    case "automationRetry": automations.retry(try playlistDisplay(request))
    default: return false
    }
    return true
  }

  private func automationTarget(_ raw: Any?, optional: Bool) throws -> WallpaperAutomationTarget? {
    if optional, raw == nil || raw is NSNull { return nil }
    guard let fields = raw as? [String: Any] else { throw WebPanelRequest.invalid }
    let request = WebPanelRequest(fields)
    guard let kind = WallpaperAutomationTarget.Kind(rawValue: try request.string("kind")) else { throw WebPanelRequest.invalid }
    let id = try request.string("id")
    switch kind {
    case .wallpaper:
      guard store.librarySnapshot.wallpapers.contains(where: { $0.id == id && $0.supported }) else { throw WebPanelRequest.invalid }
    case .playlist:
      guard playlists.plan(id: id) != nil else { throw LibraryOrganizationError.missingPlan }
    }
    return .init(kind: kind, id: id)
  }

  private func requireSpaceInformation(_ display: String) throws -> WallpaperDisplaySpaces {
    guard store.lockScreenWallpaper?.isRequested != true, store.lockScreenWallpaper?.ownsDesktopProvider != true else {
      throw WallpaperActionError(message: String(localized: "Turn off animated lock-screen wallpaper before using Space-based wallpaper choices."))
    }
    guard let row = store.settingsSnapshot.displays.first(where: { $0.displayId == display }),
          let physical = spaces.physicalDisplay(display, title: row.title), spaces.available,
          let info = spaces.displays[physical] else {
      throw WallpaperActionError(message: String(localized: "Desktop Space information is unavailable. Refresh Spaces or choose another automatic mode."))
    }
    return info
  }
}
