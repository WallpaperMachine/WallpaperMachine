import Foundation
import Observation

/// One page of a pixiv work on its way into the library.
@MainActor
@Observable
final class PixivDownload: Identifiable {
    enum Status: Equatable {
        case waiting, downloading, installing, paused, finished, cancelled
        case failed(String)
    }

    /// The wallpaper id the page is saved as, which also names the job.
    let id: String
    let work: PixivWork
    let pageIndex: Int
    fileprivate(set) var status = Status.waiting
    fileprivate(set) var bytesReceived: Int64 = 0
    fileprivate(set) var bytesExpected: Int64?
    @ObservationIgnored fileprivate var task: Task<Void, Never>?
    @ObservationIgnored fileprivate var pauseRequested = false
    @ObservationIgnored fileprivate var lastReport: ContinuousClock.Instant?
    /// Pages the store already fetched for this work, so the job need not ask pixiv again.
    @ObservationIgnored fileprivate var knownPages: [PixivPage]?

    fileprivate init(work: PixivWork, pageIndex: Int, knownPages: [PixivPage]?) {
        id = work.libraryID(page: pageIndex)
        self.work = work
        self.pageIndex = pageIndex
        self.knownPages = knownPages
    }

    var isPending: Bool {
        switch status {
        case .waiting, .downloading, .installing: true
        case .paused, .finished, .cancelled, .failed: false
        }
    }

    /// Received share of the announced size; nil until the server announced one.
    var progress: Double? {
        guard let expected = bytesExpected, expected > 0 else { return nil }
        return min(1, Double(bytesReceived) / Double(expected))
    }

    var errorMessage: String? {
        if case .failed(let message) = status { message } else { nil }
    }

    /// Byte counts arrive for every 64 KB; the panel redraws from a full snapshot, so they are
    /// published at most five times a second and always once complete.
    fileprivate func report(received: Int64, expected: Int64?) {
        let now = ContinuousClock.now
        let complete = expected.map { received >= $0 } ?? false
        if !complete, let last = lastReport, now - last < .milliseconds(200) { return }
        lastReport = now
        bytesReceived = received
        bytesExpected = expected
    }
}

/// Downloads pixiv originals into the library, a couple at a time, in the order asked for.
@MainActor
@Observable
final class PixivDownloadQueue {
    static let concurrentDownloads = 2
    private(set) var downloads: [PixivDownload] = []
    private(set) var persistenceError: String?
    @ObservationIgnored private let service: PixivService
    @ObservationIgnored private let packager: PixivWallpaperPackager
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var isShuttingDown = false

    private struct SavedDownload: Codable {
        let work: PixivWork
        let page: Int
        let knownPages: [PixivPage]?
    }
    /// Makes an installed wallpaper appear in the renderer's library; failing it fails the job,
    /// and a retry finds the files already in place.
    @ObservationIgnored var onInstalled: (@MainActor (String) async throws -> Void)?
    /// The signed-in session a job asks for its work's pages with; the images need none.
    @ObservationIgnored var session: String?

    init(service: PixivService, packager: PixivWallpaperPackager = PixivWallpaperPackager(),
         persistenceDirectory: URL? = nil) {
        self.service = service
        self.packager = packager
        directory = persistenceDirectory ?? packager.library.deletingLastPathComponent().appendingPathComponent("Downloads/Pixiv")
        if let data = try? Data(contentsOf: directory.appendingPathComponent("queue.json")),
           let saved = try? JSONDecoder().decode([SavedDownload].self, from: data) {
            var seen = Set<String>()
            for record in saved where PixivWork.isValidID(record.work.id) && record.page >= 0 && record.page < record.work.pageCount {
                let job = PixivDownload(work: record.work, pageIndex: record.page, knownPages: record.knownPages)
                guard seen.insert(job.id).inserted else { continue }
                job.status = .paused
                downloads.append(job)
            }
        }
    }

    @discardableResult
    private func persist() -> Bool {
        let saved = downloads.filter { $0.status != .finished && $0.status != .cancelled }.map {
            SavedDownload(work: $0.work, page: $0.pageIndex, knownPages: $0.knownPages)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("queue.json"), options: .atomic)
            persistenceError = nil
            return true
        } catch {
            persistenceError = String(localized: "Could not save the download queue: \(error.localizedDescription)")
            AppLog.warn("Could not save the pixiv download queue: \(error.localizedDescription)")
            return false
        }
    }

    private func checkpoint(for job: PixivDownload) -> URL { directory.appendingPathComponent(job.id) }

    private func discardCheckpoint(for job: PixivDownload) {
        try? FileManager.default.removeItem(at: checkpoint(for: job))
    }

    var isRunning: Bool { downloads.contains { $0.isPending } }

    func download(for id: String) -> PixivDownload? { downloads.first { $0.id == id } }

    /// Queues page `page` of `work`. A job for that page that is still pending is returned as
    /// it is; a finished, failed or cancelled one is replaced by a fresh attempt.
    @discardableResult
    func enqueue(_ work: PixivWork, page: Int, knownPages: [PixivPage]? = nil) -> PixivDownload {
        let id = work.libraryID(page: page)
        if let existing = download(for: id), existing.isPending { return existing }
        let job = PixivDownload(work: work, pageIndex: page, knownPages: knownPages)
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index] = job
        } else {
            downloads.append(job)
        }
        guard persist() else {
            job.status = .failed(persistenceError ?? String(localized: "Download could not finish"))
            return job
        }
        pump()
        return job
    }

    func cancel(_ id: String) {
        guard let job = download(for: id), job.isPending || job.status == .paused else { return }
        job.pauseRequested = false
        if let task = job.task {
            task.cancel()
        } else {
            job.status = .cancelled
            discardCheckpoint(for: job)
        }
        persist()
    }

    func pause(_ id: String) {
        guard let job = download(for: id), job.isPending else { return }
        job.pauseRequested = true
        if let task = job.task { task.cancel() }
        else { job.status = .paused }
        persist()
    }

    @discardableResult
    func resume(_ id: String) -> Bool {
        guard let job = download(for: id), job.status == .paused, job.task == nil else { return false }
        job.pauseRequested = false
        job.status = .waiting
        guard persist() else { job.status = .paused; return false }
        pump()
        return true
    }

    /// Starts a failed or cancelled job again; returns false when there is nothing to retry.
    @discardableResult
    func retry(_ id: String) -> Bool {
        guard let job = download(for: id), !job.isPending, job.status != .finished else { return false }
        enqueue(job.work, page: job.pageIndex, knownPages: job.knownPages)
        return true
    }

    /// Forgets every job that is no longer running.
    func clearFinished() {
        for job in downloads where !job.isPending && job.status != .paused { discardCheckpoint(for: job) }
        downloads.removeAll { !$0.isPending && $0.status != .paused }
        persist()
    }

    /// Pauses every job and waits until each has removed its staging folder.
    func shutdown() async {
        isShuttingDown = true
        let running = downloads.compactMap(\.task)
        for job in downloads where job.isPending { pause(job.id) }
        for task in running { await task.value }
        persist()
    }

    private func pump() {
        guard !isShuttingDown else { return }
        var running = downloads.filter { $0.task != nil }.count
        for job in downloads where job.status == .waiting && job.task == nil {
            guard running < Self.concurrentDownloads else { return }
            running += 1
            job.status = .downloading
            job.task = Task { [weak self] in
                await self?.run(job)
                job.task = nil
                self?.persist()
                self?.pump()
            }
        }
    }

    private func run(_ job: PixivDownload) async {
        do {
            let pages: [PixivPage]
            if let known = job.knownPages {
                pages = known
            } else {
                pages = try await service.pages(ofWork: job.work.id, session: session)
            }
            guard let page = pages.first(where: { $0.index == job.pageIndex }) else {
                throw PixivFailure(code: .unreadable)
            }
            job.knownPages = pages
            persist()
            let image = try await service.original(of: page, checkpoint: checkpoint(for: job)) { received, expected in
                Task { @MainActor in
                    guard job.status == .downloading else { return }
                    job.report(received: received, expected: expected)
                }
            }
            try Task.checkCancellation()
            job.status = .installing
            job.bytesReceived = Int64(image.count)
            job.bytesExpected = Int64(image.count)
            let id = try await packager.install(image, work: job.work, page: page, pageCount: pages.count)
            // Installed is installed: the library is refreshed even if the job was cancelled
            // meanwhile, so the wallpaper never sits on disk unlisted.
            try await onInstalled?(id)
            job.status = .finished
            discardCheckpoint(for: job)
            AppLog.info("pixiv \(job.work.id) page \(job.pageIndex) saved as \(id)")
        } catch is CancellationError {
            job.status = job.pauseRequested ? .paused : .cancelled
            if !job.pauseRequested { discardCheckpoint(for: job) }
        } catch {
            job.status = .failed(error.localizedDescription)
            AppLog.warn("pixiv \(job.work.id) page \(job.pageIndex) failed: \(error.localizedDescription)")
        }
    }
}
