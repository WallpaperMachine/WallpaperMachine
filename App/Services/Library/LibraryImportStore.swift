import Foundation
import Observation

/// Runs one library import at a time and keeps its progress and last report. It belongs to the
/// app rather than to the control panel's page, so an import started from the panel, from
/// Finder's Open With or from a drop on the Dock icon runs to the end whether or not the panel
/// stays open.
@MainActor
@Observable
final class LibraryImportStore {
    private(set) var isBusy = false
    private(set) var status = ""
    private(set) var report: WallpaperImportService.Report?
    /// Why the last import stopped early. The next import, or the user dismissing it, clears it.
    private(set) var failure: String?
    /// Rescans the library once the files are in. Set by the app delegate once the bridge exists;
    /// nil only in tests that never import.
    @ObservationIgnored var refreshLibrary: (@MainActor () async throws -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let importer: WallpaperImportService
    @ObservationIgnored private let library: URL

    init(importer: WallpaperImportService = WallpaperImportService(), library: URL = ClientPaths.libraryURL) {
        self.importer = importer
        self.library = library
    }

    /// Starts importing `sources`. Throws when an import is already running; an empty list
    /// starts nothing.
    func start(_ sources: [URL], duplicates: WallpaperImportService.DuplicatePolicy) throws {
        guard task == nil else {
            throw WallpaperActionError(message: String(localized: "An import is already running."))
        }
        guard !sources.isEmpty else { return }
        isBusy = true
        failure = nil
        report = nil
        status = String(localized: "Preparing import…")
        task = Task { [weak self] in await self?.run(sources, duplicates: duplicates) }
    }

    func cancel() {
        guard let task else { return }
        task.cancel()
        status = String(localized: "Cancelling…")
    }

    func shutdown() async {
        guard let running = task else { return }
        running.cancel()
        await running.value
    }

    func dismissFailure() { failure = nil }

    private func run(_ sources: [URL], duplicates: WallpaperImportService.DuplicatePolicy) async {
        defer {
            task = nil
            isBusy = false
        }
        do {
            let report = try await importer.importItems(sources, into: library, duplicates: duplicates) {
                [weak self] status in
                guard let self else { return }
                await MainActor.run { self.status = status }
            }
            self.report = report
            if let refreshLibrary {
                // Its own task, so cancelling the import cannot also abandon the rescan that
                // makes what did arrive appear.
                try await Task { @MainActor in try await refreshLibrary() }.value
            }
            status = report.cancelled ? String(localized: "Import cancelled") : String(localized: "Import complete")
        } catch {
            failure = error.localizedDescription
            status = String(localized: "Import could not finish")
        }
    }
}
