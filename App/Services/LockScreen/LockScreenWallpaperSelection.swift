import AppKit
import Darwin

struct LockScreenWallpaperFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// Journals physical-display choices and temporarily removes the global Idle
/// override that would otherwise take precedence over those screen savers.
@MainActor
final class LockScreenWallpaperSelection {
  private struct Entry: Codable, Equatable {
    var path: [String]
    var original: Data
    var created: Bool
    var observeOnly: Bool? = nil
    // Absent in pre-independent journals, which owned both native choices.
    var fields: [String]? = nil
    var typeOwned: Bool? = nil

    var ownedFields: Set<String> { Set(fields ?? ["Desktop", "Idle"]) }
  }

  private static var lastReloadSignal: Date?
  private static let globalPath = ["AllSpacesAndDisplays"]

  private let storeURL: URL
  private let journalURL: URL
  private let reload: @MainActor () throws -> Void
  private let persistJournal: @MainActor (URL, Data?) throws -> Void
  private var entries: [Entry] = []
  private var hasPersistedJournal = false
  private var restartPending = false

  convenience init(folder: URL) {
    self.init(
      storeURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/com.apple.wallpaper/Store/Index.plist"),
      journalURL: folder.appendingPathComponent("native-selection.plist"),
      reload: { try Self.reloadWallpaperAgent() })
  }

  init(
    storeURL: URL, journalURL: URL, reload: @escaping @MainActor () throws -> Void,
    persistJournal: @escaping @MainActor (URL, Data?) throws -> Void =
      LockScreenWallpaperSelection.persistJournalFile
  ) {
    self.storeURL = storeURL
    self.journalURL = journalURL
    self.reload = reload
    self.persistJournal = persistJournal
  }

  func recover() throws {
    guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
    let recovered = try PropertyListDecoder().decode([Entry].self, from: Data(contentsOf: journalURL))
    entries = recovered
    hasPersistedJournal = true
    // A crash may occur after the store write but before its service reload.
    restartPending = true
    try synchronize(desktopDisplays: [], screenSaverDisplays: [])
  }

  func checkCompatibility() throws {
    let root =
      try PropertyListSerialization.propertyList(from: Data(contentsOf: storeURL), format: nil)
      as? [String: Any]
    if let global = root?["AllSpacesAndDisplays"] as? [String: Any],
      global["Type"] as? String == "linked"
    {
      throw LockScreenWallpaperFailure(
        message:
          String(localized: "A system-wide linked wallpaper currently overrides individual displays. Turn off that wallpaper app or its all-displays setting before enabling native wallpaper animation; the existing global wallpaper was not changed.")
      )
    }
  }

  func synchronize(
    desktopDisplays: Set<String>, screenSaverDisplays: Set<String>, revision: String? = nil
  ) throws {
    let displays = desktopDisplays.union(screenSaverDisplays)
    if displays.isEmpty && entries.isEmpty && !restartPending { return }
    let bytes = try Data(contentsOf: storeURL)
    guard
      var root = try PropertyListSerialization.propertyList(from: bytes, format: nil)
        as? [String: Any],
      root["Displays"] is [String: Any], root["Spaces"] is [String: Any]
    else {
      throw LockScreenWallpaperFailure(
        message:
          String(localized: "This macOS wallpaper store format is unsupported. Native selection was not changed."))
    }
    var paths = displays.sorted().map { ["Displays", $0] }
    let spaces = root["Spaces"] as? [String: Any] ?? [:]
    for (space, value) in spaces.sorted(by: { $0.key < $1.key }) {
      guard let node = value as? [String: Any], node["Displays"] is [String: Any] else {
        throw LockScreenWallpaperFailure(
          message: String(localized: "This macOS Space has an unsupported wallpaper configuration."))
      }
      paths += displays.sorted().map { ["Spaces", space, "Displays", $0] }
    }
    let fallbackPaths = [["SystemDefault"]] + spaces.keys.sorted().map { ["Spaces", $0, "Default"] }
    let activeFields = Set(
      (desktopDisplays.isEmpty ? [] : ["Desktop"])
        + (screenSaverDisplays.isEmpty ? [] : ["Idle"]))
    func desiredFields(_ path: [String], observeOnly: Bool) -> Set<String> {
      if observeOnly { return fallbackPaths.contains(path) ? activeFields : [] }
      guard paths.contains(path), let display = path.last else { return [] }
      return Set(
        (desktopDisplays.contains(display) ? ["Desktop"] : [])
          + (screenSaverDisplays.contains(display) ? ["Idle"] : []))
    }
    var originals: [[String]: [String: Any]] = [:]
    for entry in entries {
      guard
        let original = try PropertyListSerialization.propertyList(from: entry.original, format: nil)
          as? [String: Any]
      else {
        throw LockScreenWallpaperFailure(
          message: String(localized: "The native wallpaper restoration journal is invalid."))
      }
      originals[entry.path] = entry.path == Self.globalPath ? original : original.filter {
        entry.ownedFields.contains($0.key) || ($0.key == "Type" && (entry.typeOwned ?? true))
      }
    }
    let journaledOriginal = { (path: [String]) in originals[path] }
    var recovery = entries
    var retained: [Entry] = []
    var changed = false
    let selection = try Self.selection(revision: revision)
    // The pre-commit journal owns the union of old and new fields. A crash at
    // either side of the atomic store write can therefore restore all of them.
    func record(_ entry: Entry, original: [String: Any]) throws {
      if let index = recovery.firstIndex(where: { $0.path == entry.path }) {
        var merged = originals[entry.path] ?? [:]
        for key in entry.ownedFields.subtracting(recovery[index].ownedFields) {
          merged[key] = original[key]
        }
        recovery[index].original = try Self.encode(merged)
        recovery[index].fields = recovery[index].ownedFields.union(entry.ownedFields).sorted()
        originals[entry.path] = merged
      } else {
        recovery.append(entry)
        originals[entry.path] = original
      }
    }
    func reconcile(_ prior: Entry?, path: [String], observeOnly: Bool) throws {
      let desired = desiredFields(path, observeOnly: observeOnly)
      let previous = prior?.ownedFields ?? []
      let existing = Self.node(root, path: path)
      if existing == nil && desired.isEmpty { return }
      if existing == nil, !observeOnly, !previous.intersection(desired).isEmpty {
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "A native wallpaper override was removed outside WallpaperMachine. Disable the affected wallpaper feature before enabling it again."))
      }
      var node = existing ?? [:]
      if !observeOnly && !desired.isEmpty && existing != nil
        && node["Type"] as? String != "individual"
      {
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "This display uses a linked or unsupported native wallpaper configuration. Choose separate desktop and screen saver wallpapers in System Settings before enabling native wallpaper animation."))
      }
      var original = prior.flatMap { originals[$0.path] } ?? [:]
      let removed = previous.subtracting(desired)
      let allPreviouslyOwned = previous.allSatisfy { Self.owns(node[$0]) }
      for key in previous.sorted() {
        if desired.contains(key) {
          if !observeOnly && !Self.owns(node[key]) {
            throw LockScreenWallpaperFailure(
              message:
                String(localized: "The system wallpaper was changed outside WallpaperMachine. Disable the affected wallpaper feature before enabling it again; external choices will be preserved."))
          }
        } else if Self.owns(node[key]) {
          node[key] = original[key]
        }
      }
      let added = desired.subtracting(previous)
      if !added.isEmpty {
        let restored = try Self.restorationOriginal(
          node, path: path, root: root, fields: added, journaled: journaledOriginal)
        for key in added { original[key] = restored[key] }
      }
      let typeOwned = prior.map { $0.typeOwned ?? true } ?? (!observeOnly && existing == nil)
      if prior == nil && typeOwned { original["Type"] = existing?["Type"] }
      if !observeOnly {
        for key in desired.sorted() {
          let current = node[key] as? [String: Any]
          let content = current?["Content"] as? [String: Any]
          let choices = content?["Choices"] as? [[String: Any]]
          let expected = (selection["Content"] as? [String: Any])?["Choices"] as? [[String: Any]]
          if added.contains(key)
            || (revision != nil
              && choices?.first?["Configuration"] as? Data
                != expected?.first?["Configuration"] as? Data)
          {
            node[key] = selection
          }
        }
        // Existing Type and all other metadata belong to the user.
        if prior == nil && typeOwned { node["Type"] = "individual" }
      }
      if desired.isEmpty && !removed.isEmpty && typeOwned && allPreviouslyOwned
        && node["Type"] as? String == "individual"
        && ["Desktop", "Idle"].allSatisfy({
          (node[$0] as? NSDictionary) == (original[$0] as? NSDictionary)
        })
      {
        node["Type"] = original["Type"]
      }
      if !desired.isEmpty {
        original = original.filter {
          desired.contains($0.key) || ($0.key == "Type" && typeOwned)
        }
        let originalData: Data
        if let prior, desired == previous {
          originalData = prior.original
        } else {
          originalData = try Self.encode(original)
        }
        let entry = Entry(
          path: path, original: originalData,
          created: prior?.created ?? (existing == nil), observeOnly: observeOnly,
          fields: desired.sorted(), typeOwned: typeOwned)
        if !added.isEmpty { try record(entry, original: original) }
        retained.append(entry)
      }
      let value: [String: Any]? =
        node.isEmpty && ((prior?.created ?? false) || existing == nil) ? nil : node
      if (existing as NSDictionary?) != (value as NSDictionary?) {
        Self.setNode(&root, path: path, value: value)
        changed = true
      }
    }
    // AllSpacesAndDisplays overrides the per-display Idle choices. Its `idle`
    // case must be removed entirely; `individual` contains both choices, so it
    // becomes `desktop`. An empty `individual` is not a valid native enum case.
    let globalEntry = entries.first { $0.path == Self.globalPath }
    let global = Self.node(root, path: Self.globalPath)
    if !screenSaverDisplays.isEmpty {
      if let globalEntry {
        guard global == nil || global?["Type"] as? String == "desktop" else {
          throw LockScreenWallpaperFailure(
            message: String(localized: "The system wallpaper was changed outside WallpaperMachine. Disable the affected wallpaper feature before enabling it again; external choices will be preserved."))
        }
        retained.append(globalEntry)
      } else {
        var replacement = global
        if let global {
          switch global["Type"] as? String {
          case "idle": replacement = nil
          case "individual":
            replacement?.removeValue(forKey: "Idle")
            replacement?["Type"] = "desktop"
          case "desktop": break
          default:
            throw LockScreenWallpaperFailure(
              message: String(localized: "This macOS wallpaper store format is unsupported. Native selection was not changed."))
          }
        }
        let original = global ?? [:]
        let entry = Entry(
          path: Self.globalPath, original: try Self.encode(original), created: false,
          fields: ["Idle"], typeOwned: false)
        try record(entry, original: original)
        retained.append(entry)
        if (global as NSDictionary?) != (replacement as NSDictionary?) {
          Self.setNode(&root, path: Self.globalPath, value: replacement)
          changed = true
        }
      }
    } else if let globalEntry,
      let original = originals[globalEntry.path],
      ["idle", "individual"].contains(original["Type"] as? String ?? ""),
      global == nil || global?["Type"] as? String == "desktop"
    {
      // A later global screen saver belongs to the user. A desktop-only edit
      // can coexist with restoring the saved Idle choice, including its Type.
      var restored = global ?? original
      restored["Idle"] = original["Idle"]
      if global == nil {
        restored.removeValue(forKey: "Desktop")
        restored["Type"] = "idle"
      } else {
        restored["Type"] = "individual"
      }
      Self.setNode(&root, path: Self.globalPath, value: restored)
      changed = true
    }
    for entry in entries where entry.path != Self.globalPath {
      try reconcile(entry, path: entry.path, observeOnly: entry.observeOnly == true)
    }
    // New Spaces may inherit copied choices just before one mode is disabled.
    // Restore only that mode, including unjournaled Defaults, while the other
    // mode and all foreign choices remain untouched.
    let oldFallbackFields = entries.filter { $0.observeOnly == true }
      .reduce(into: Set<String>()) { $0.formUnion($1.ownedFields) }
    let topEntries = entries.filter { $0.path.count == 2 && $0.path[0] == "Displays" }
    for space in spaces.keys.sorted() {
      let discovered = [(["Spaces", space, "Default"], oldFallbackFields.subtracting(activeFields))]
        + topEntries.map {
          (["Spaces", space, "Displays", $0.path[1]],
            $0.ownedFields.subtracting(desiredFields($0.path, observeOnly: false)))
        }
      for (path, fields) in discovered where !entries.contains(where: { $0.path == path }) {
        guard var node = Self.node(root, path: path) else { continue }
        let copied = fields.filter { Self.owns(node[$0]) }
        guard !copied.isEmpty else { continue }
        let original = try Self.restorationOriginal(
          node, path: path, root: root, fields: copied, journaled: journaledOriginal)
          .filter { copied.contains($0.key) }
        let entry = Entry(
          path: path, original: try Self.encode(original), created: false,
          observeOnly: path.last == "Default", fields: copied.sorted(), typeOwned: false)
        try record(entry, original: original)
        for key in copied { node[key] = original[key] }
        Self.setNode(&root, path: path, value: node)
        changed = true
      }
    }
    for path in fallbackPaths
    where !activeFields.isEmpty && !entries.contains(where: { $0.path == path }) {
      try reconcile(nil, path: path, observeOnly: true)
    }
    for path in paths where !entries.contains(where: { $0.path == path }) {
      try reconcile(nil, path: path, observeOnly: false)
    }
    if changed {
      try persistEntries(recovery)
      guard try Data(contentsOf: storeURL) == bytes else {
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "The system wallpaper changed during native selection. Please retry; no concurrent changes were overwritten."))
      }
      try Self.encode(root).write(to: storeURL, options: .atomic)
      restartPending = true
    }
    if restartPending {
      try reload()
      restartPending = false
    }
    try persistEntries(retained)
  }

  private func persistEntries(_ next: [Entry]) throws {
    guard next != entries || hasPersistedJournal != !next.isEmpty else { return }
    let data = try (next.isEmpty ? nil : PropertyListEncoder().encode(next))
    try persistJournal(journalURL, data)
    entries = next
    hasPersistedJournal = !next.isEmpty
  }

  static func persistJournalFile(_ url: URL, _ data: Data?) throws {
    if let data {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    } else if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// A fallback that macOS overwrote with a copy of this extension's selection
  /// still has its native choice in the journal, so `journaled` is consulted
  /// after the live value: a Space created after that copy, a full-screen
  /// app's included, would otherwise have no fallback left at all.
  private static func restorationOriginal(
    _ node: [String: Any], path: [String], root: [String: Any], fields: Set<String>,
    journaled: ([String]) -> [String: Any]?
  ) throws -> [String: Any] {
    var original = node
    var fallbackPaths: [[String]] = []
    if path.count == 4, path[0] == "Spaces" {
      fallbackPaths.append(["Displays", path[3]])
      fallbackPaths.append(["Spaces", path[1], "Default"])
    }
    fallbackPaths += [["SystemDefault"], ["AllSpacesAndDisplays"]]
    for key in fields.sorted() where owns(node[key]) {
      guard
        let replacement = fallbackPaths
          .filter({ $0 != path })
          .flatMap({ fallback in
            [
              Self.node(root, path: fallback)?[key] as? [String: Any],
              journaled(fallback)?[key] as? [String: Any],
            ].compactMap { $0 }
          })
          .first(where: { value in
            guard !owns(value), let content = value["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]], !choices.isEmpty
            else { return false }
            return choices.allSatisfy {
              guard let provider = $0["Provider"] as? String else { return false }
              return !provider.isEmpty && provider != LockScreenConfiguration.extensionIdentifier
            }
          })
      else {
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "A native wallpaper selection has no restoration journal or surviving system fallback. Choose a system wallpaper for this display before enabling native wallpaper animation.")
        )
      }
      original[key] = replacement
    }
    return original
  }

  private static func selection(revision: String?) throws -> [String: Any] {
    [
      "Content": [
        "Choices": [
          [
            "Provider": LockScreenConfiguration.extensionIdentifier,
            "Configuration": Data((revision.map { "current:" + $0 } ?? "current").utf8),
            "Files": [String](),
          ]
        ],
        "Shuffle": "$null", "EncodedOptionValues": try encode(["values": [String: Any]()]),
      ],
      "LastSet": Date(), "LastUse": Date(),
    ]
  }

  private static func owns(_ value: Any?) -> Bool {
    guard let selection = value as? [String: Any],
      let content = selection["Content"] as? [String: Any],
      let choices = content["Choices"] as? [[String: Any]], choices.count == 1
    else { return false }
    return choices[0]["Provider"] as? String == LockScreenConfiguration.extensionIdentifier
  }

  private static func encode(_ value: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
  }

  private static func node(_ root: [String: Any], path: [String]) -> [String: Any]? {
    var node = root
    for key in path {
      guard let child = node[key] as? [String: Any] else { return nil }
      node = child
    }
    return node
  }

  private static func setNode(_ root: inout [String: Any], path: [String], value: [String: Any]?) {
    guard let key = path.first else { return }
    if path.count == 1 {
      root[key] = value
      return
    }
    var child = root[key] as? [String: Any] ?? [:]
    setNode(&child, path: Array(path.dropFirst()), value: value)
    root[key] = child
  }

  /// Verify effective UID and the kernel-reported executable immediately before
  /// each signal. Never signal by name alone, restart Dock, or touch loginwindow.
  private static func reloadWallpaperAgent() throws {
    let expected = "/System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent"
    let capacity = proc_listallpids(nil, 0)
    guard capacity > 0 else {
      throw LockScreenWallpaperFailure(message: String(localized: "Unable to enumerate the wallpaper service."))
    }
    var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
    let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
    guard count > 0, Int(count) <= pids.count else {
      throw LockScreenWallpaperFailure(message: String(localized: "Unable to identify the wallpaper service safely."))
    }
    var found = false
    // PROC_PIDPATHINFO_MAXSIZE expands to 4*MAXPATHLEN and is not Swift-importable.
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    for pid in pids.prefix(Int(count)) where pid > 0 {
      var info = proc_bsdinfo()
      let size = Int32(MemoryLayout<proc_bsdinfo>.size)
      guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
        info.pbi_uid == getuid(), info.pbi_ruid == getuid()
      else { continue }
      let length = path.withUnsafeMutableBytes {
        proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
      }
      guard length > 0, String(cString: path) == expected else { continue }
      guard kill(pid, SIGTERM) == 0 || errno == ESRCH else {
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "macOS refused to reload the user-owned wallpaper service (errno \(errno)). The restoration journal was retained.")
        )
      }
      found = true
    }
    if found {
      lastReloadSignal = Date()
      return
    }
    // We SIGTERMed the agent moments ago and launchd has not relaunched it yet.
    // The relaunch reads the store we just wrote, so no signal is needed.
    if let last = lastReloadSignal, Date().timeIntervalSince(last) < 10 { return }
    throw LockScreenWallpaperFailure(
      message:
        String(localized: "No positively verified user-owned WallpaperAgent is running. Native selection could not be activated; its restoration journal was retained.")
    )
  }
}
