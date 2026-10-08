import AppKit
import Dispatch
import Foundation
import UniformTypeIdentifiers

/// Presents Import in the chosen language while keeping the main app running.
@MainActor
final class WallpaperImportPicker {
    private let bundle: Bundle
    private var panel: NSOpenPanel?
    private var helper: HelperProcess?
    var isPresenting: Bool { panel != nil || helper != nil }

    init(bundle: Bundle = .main) { self.bundle = bundle }

    func choose(for window: NSWindow, language: String, allowedContentTypes: [UTType]) async throws -> [URL]? {
        guard !isPresenting else { throw Failure.alreadyPresenting }
        guard !Task.isCancelled else { return nil }
        if bundle.preferredLocalizations.first == language {
            let panel = Self.makePanel(allowedContentTypes: allowedContentTypes)
            self.panel = panel
            defer { self.panel = nil }
            return await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .OK ? panel.urls : nil)
                }
            }
        }

        guard let executable = bundle.executableURL else { throw Failure.unavailable }
        let appearance = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        let helper = HelperProcess(executableURL: executable, arguments: [
            WallpaperImportPickerHelper.argument,
            allowedContentTypes.map(\.identifier).joined(separator: ","), appearance.rawValue,
            "-AppleLanguages", "(\(language))",
        ])
        self.helper = helper
        defer { self.helper = nil }
        do {
            let data = try await helper.run { pid in
                guard let application = NSRunningApplication(processIdentifier: pid) else {
                    throw Failure.unavailable
                }
                // The child waits until we yield activation before showing its window.
                NSApp.yieldActivation(to: application)
            }
            try Task.checkCancellation()
            guard !helper.isCancelled else { return nil }
            let urls = try JSONDecoder().decode([URL]?.self, from: data)
            if window.isVisible, !window.isMiniaturized {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
            return urls
        } catch is CancellationError {
            return nil
        }
    }

    func cancel() {
        panel?.cancel(nil)
        helper?.cancel()
    }

    static func makePanel(allowedContentTypes: [UTType]) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Wallpapers")
        panel.message = String(localized:
            "Choose videos, images, HTML files, project folders or a Steam library. Your original files are kept.")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.allowedContentTypes = allowedContentTypes
        return panel
    }

    enum Failure: LocalizedError {
        case alreadyPresenting, unavailable, unexpectedOutput, exited(Int32)

        var errorDescription: String? {
            switch self {
            case .alreadyPresenting: String(localized: "An import is already running.")
            default: String(localized: "The import file picker could not open.")
            }
        }
    }

    /// Owns one child, its activation handshake, and the pipe that closes on parent exit.
    final class HelperProcess: @unchecked Sendable {
        private let process = Process()
        private let output = Pipe()
        private let parentConnection = Pipe()
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool { lock.withLock { cancelled } }

        init(executableURL: URL, arguments: [String]) {
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardInput = parentConnection
            process.standardOutput = output
        }

        func run(onReady: @escaping @MainActor @Sendable (Int32) throws -> Void) async throws -> Data {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    // Pipe reads can wait for the entire picker session. Keep them off the
                    // cooperative executor, and keep Process launch/wait on one worker.
                    DispatchQueue.global(qos: .userInitiated).async { [self] in
                        continuation.resume(with: Result { try runBlocking(onReady: onReady) })
                    }
                }
            } onCancel: {
                self.cancel()
            }
        }

        private func runBlocking(onReady: @escaping @MainActor @Sendable (Int32) throws -> Void) throws -> Data {
            defer {
                try? parentConnection.fileHandleForWriting.close()
                try? output.fileHandleForReading.close()
            }
            try lock.withLock {
                guard !cancelled else { throw CancellationError() }
                try process.run()
            }
            let data: Data
            do {
                let ready = try output.fileHandleForReading.read(upToCount: 1)
                if isCancelled { throw CancellationError() }
                guard ready == Data([1]) else { throw Failure.unexpectedOutput }
                // The async caller has yielded; only this blocking worker waits for the
                // main-actor activation handshake. No async hop moves the process waiter.
                try DispatchQueue.main.sync {
                    try MainActor.assumeIsolated {
                        if isCancelled { throw CancellationError() }
                        try onReady(process.processIdentifier)
                    }
                }
                if isCancelled { throw CancellationError() }
                try parentConnection.fileHandleForWriting.write(contentsOf: Data([1]))
                data = try output.fileHandleForReading.readToEnd() ?? Data()
            } catch {
                cancel()
                process.waitUntilExit()
                throw error
            }
            process.waitUntilExit()
            if isCancelled { throw CancellationError() }
            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                throw Failure.exited(process.terminationStatus)
            }
            return data
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                if process.isRunning { process.terminate() }
            }
        }
    }
}
