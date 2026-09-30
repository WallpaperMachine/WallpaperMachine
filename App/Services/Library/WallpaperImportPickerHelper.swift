import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

/// A fresh AppKit process owns the localized system controls and returns only the selection.
@MainActor
final class WallpaperImportPickerHelper: NSObject, NSApplicationDelegate {
    static let argument = "--wallpaper-import-picker"
    private let panel: NSOpenPanel
    private var presented = false
    private var finished = false

    private init(allowedContentTypes: [UTType]) {
        panel = WallpaperImportPicker.makePanel(allowedContentTypes: allowedContentTypes)
        super.init()
    }

    /// This branch runs before AppDelegate; it never starts wallpapers or accesses the library.
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument) else { return false }
        guard arguments.indices.contains(index + 2) else { exit(EXIT_FAILURE) }
        let types = arguments[index + 1].split(separator: ",").compactMap { UTType(String($0)) }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.appearance = NSAppearance(named: NSAppearance.Name(arguments[index + 2]))
        let helper = WallpaperImportPickerHelper(allowedContentTypes: types)
        application.delegate = helper
        withExtendedLifetime(helper) { application.run() }
        FileHandle.standardInput.readabilityHandler = nil
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    guard let self, !self.finished else { return }
                    if data.isEmpty {
                        // EOF is also delivered if the parent exits without its normal cleanup.
                        if self.presented { self.panel.cancel(nil) }
                        else { self.finish(.cancel) }
                    } else if data == Data([1]), !self.presented {
                        self.present()
                    } else {
                        exit(EXIT_FAILURE)
                    }
                }
            }
        }
        do {
            // The parent yields activation and replies before the native window is ordered in.
            try FileHandle.standardOutput.write(contentsOf: Data([1]))
        } catch {
            exit(EXIT_FAILURE)
        }
    }

    private func present() {
        presented = true
        NSApp.activate()
        panel.begin { [self] response in finish(response) }
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        guard !finished else { return }
        guard response == .OK || response == .cancel else { exit(EXIT_FAILURE) }
        finished = true
        FileHandle.standardInput.readabilityHandler = nil
        do {
            let urls: [URL]? = response == .OK ? panel.urls : nil
            let data = try JSONEncoder().encode(urls)
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch {
            exit(EXIT_FAILURE)
        }
        NSApp.stop(nil)
        NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 0, data1: 0, data2: 0)!, atStart: false)
    }
}
