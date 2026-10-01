import AppKit

/// AppKit owns the control panel and menu-bar lifecycle. A placeholder SwiftUI
/// Settings scene can create an empty window independently of that control panel.
@main
struct WallpaperEngineApp {
    @MainActor
    static func main() {
        if WallpaperImportPickerHelper.runIfRequested() { return }
        if NSClassFromString("XCTestCase") == nil {
            do {
                if let report = try WallpaperBackupService.applyPendingRestore() {
                    AppLog.info("startup: restored \(report.restoredPaths.count) backup resources")
                    for warning in report.warnings { AppLog.warn("backup restore: \(warning)") }
                }
            } catch {
                AppLog.error("startup backup restore failed: \(error.localizedDescription)")
            }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
