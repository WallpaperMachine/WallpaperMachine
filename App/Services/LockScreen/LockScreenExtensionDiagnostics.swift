import Darwin
import Foundation

enum LockScreenExtensionDiagnostics {
  static let differentCopyMessage = String(localized: "macOS is still loading the wallpaper renderer from another copy of WallpaperMachine. Close other running copies, then retry in this app.")

  static func failure(
    status: LockScreenExtensionStatus, revision: String, expectedBundle: URL
  ) -> LockScreenWallpaperFailure? {
    guard status.revision == revision else { return nil }
    if !isSameBundle(URL(fileURLWithPath: status.bundlePath), expectedBundle) {
      return LockScreenWallpaperFailure(message: differentCopyMessage, reason: .differentExtensionCopy)
    }
    if status.supportedVersion != LockScreenConfiguration.supportedVersion {
      return LockScreenWallpaperFailure(message: String(localized: "The app and the lock-screen renderer use incompatible configuration versions. Quit other copies of WallpaperMachine and reopen the intended app, then retry."))
    }
    if let error = status.error {
      return LockScreenWallpaperFailure(message: String(localized: "The lock-screen renderer could not load its configuration: \(error)"))
    }
    return nil
  }

  static func isSameBundle(_ first: URL, _ second: URL) -> Bool {
    // URL equality also compares directory hints/trailing slashes.
    first.resolvingSymlinksInPath().standardizedFileURL.path
      == second.resolvingSymlinksInPath().standardizedFileURL.path
  }

  /// Legacy extensions cannot send diagnostics. Inspect only this user's extension processes
  /// after a timeout; an old process still exiting during activation is not itself a failure.
  static func runningExtensionBundles() -> [URL] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
    let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
    guard count > 0 else { return [] }
    return pids.prefix(Int(count)).compactMap { pid in
      var info = proc_bsdinfo()
      guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
        == MemoryLayout.size(ofValue: info), info.pbi_uid == getuid()
      else { return nil }
      var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
      guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
      let executable = URL(fileURLWithPath: String(cString: path))
      guard executable.lastPathComponent == "WallpaperMachineExtension" else { return nil }
      let bundle = executable.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
      guard Bundle(url: bundle)?.bundleIdentifier == LockScreenConfiguration.extensionIdentifier
      else { return nil }
      return bundle.resolvingSymlinksInPath().standardizedFileURL
    }
  }
}
