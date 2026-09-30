import AppKit

/// AppKit owns the control panel and menu-bar lifecycle. A placeholder SwiftUI
/// Settings scene can create an empty window independently of that control panel.
@main
struct WallpaperEngineApp {
    @MainActor
    static func main() {
        if WallpaperImportPickerHelper.runIfRequested() { return }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
