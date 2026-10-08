import AppKit

@MainActor
protocol WallpaperPreviewSurface: AnyObject {
    var view: NSView { get }
    var onReady: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func start() async throws
    func setPaused(_ paused: Bool) throws
    func setMuted(_ muted: Bool) throws
    func stop()
}

/// Owns one isolated preview and fences late work when the user replaces or closes it.
@MainActor
final class WallpaperPreviewSession {
    enum Phase: Equatable { case closed, loading, playing, paused, failed(String) }
    struct Selection: Equatable, Sendable {
        let wallpaperID: String
        let displayID: String
        var textOverrides: [String: String] = [:]
    }
    typealias Load = @MainActor (Selection) async throws -> WallpaperPreviewRequest
    typealias Factory = @MainActor (WallpaperPreviewRequest, UInt64) throws -> any WallpaperPreviewSurface

    private let load: Load
    private let makeSurface: Factory
    private let sleep: @Sendable (Duration) async throws -> Void
    private(set) var phase: Phase = .closed
    private(set) var title = ""
    private(set) var selection: Selection?
    private(set) var muted = true
    private(set) var userPaused = false
    private(set) var visible = false
    private(set) var request: WallpaperPreviewRequest?
    private(set) var surface: (any WallpaperPreviewSurface)?
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var ready = false
    var onChange: (() -> Void)?
    var onSurface: ((NSView?) -> Void)?

    init(load: @escaping Load, makeSurface: @escaping Factory,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.load = load
        self.makeSurface = makeSurface
        self.sleep = sleep
    }

    func open(_ selection: Selection) {
        release()
        self.selection = selection
        title = ""
        muted = true
        userPaused = false
        phase = .loading
        onChange?()
        let ticket = generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let input = try await load(selection)
                try Task.checkCancellation()
                guard ticket == generation else { return }
                request = input
                title = input.title
                operation = nil
                onChange?()
                if visible { startSurface(ticket: ticket) }
            } catch is CancellationError {
                if ticket == generation { fail(String(localized: "Preview loading was cancelled. Try again."), ticket: ticket) }
            } catch { fail(error.localizedDescription, ticket: ticket) }
        }
    }

    func reload() {
        guard var selection else { return }
        selection.textOverrides = [:]
        open(selection)
    }

    func setVisible(_ visible: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        if visible, surface == nil, request != nil, phase == .loading {
            startSurface(ticket: generation)
        } else {
            do { try surface?.setPaused(!visible || userPaused) }
            catch { fail(error.localizedDescription, ticket: generation) }
            updatePhase()
        }
        if !visible { deadline?.cancel(); deadline = nil }
        else if !ready, surface != nil, phase == .loading { armDeadline(ticket: generation) }
    }

    func togglePause() {
        guard ready else { return }
        userPaused.toggle()
        do { try surface?.setPaused(!visible || userPaused); updatePhase() }
        catch { fail(error.localizedDescription, ticket: generation) }
    }

    func toggleMute() {
        guard surface != nil else { return }
        muted.toggle()
        do { try surface?.setMuted(muted); onChange?() }
        catch { fail(error.localizedDescription, ticket: generation) }
    }

    func close() {
        release()
        selection = nil
        title = ""
        visible = false
        phase = .closed
        onChange?()
    }

    private func startSurface(ticket: UInt64) {
        guard surface == nil, let request, ticket == generation else { return }
        do {
            let created = try makeSurface(request, ticket)
            surface = created
            created.onReady = { [weak self] in self?.didBecomeReady(ticket: ticket) }
            created.onFailure = { [weak self] message in self?.fail(message, ticket: ticket) }
            try created.setMuted(muted)
            onSurface?(created.view)
            armDeadline(ticket: ticket)
            operation = Task { [weak self, weak created] in
                guard let self, let created else { return }
                do {
                    try await created.start()
                    guard ticket == generation else { return }
                    try created.setPaused(!visible || userPaused)
                    operation = nil
                } catch is CancellationError {
                    if ticket == generation { fail(String(localized: "Preview loading was cancelled. Try again."), ticket: ticket) }
                } catch { fail(error.localizedDescription, ticket: ticket) }
            }
        } catch { fail(error.localizedDescription, ticket: ticket) }
    }

    private func didBecomeReady(ticket: UInt64) {
        guard ticket == generation, surface != nil else { return }
        deadline?.cancel()
        deadline = nil
        ready = true
        updatePhase()
    }

    private func updatePhase() {
        if ready { phase = userPaused || !visible ? .paused : .playing }
        onChange?()
    }

    private func armDeadline(ticket: UInt64) {
        deadline?.cancel()
        deadline = Task { [weak self, sleep] in
            do { try await sleep(.seconds(30)) } catch { return }
            guard let self, ticket == generation, visible, !ready else { return }
            fail(String(localized: "The preview did not become ready within 30 seconds. Try another wallpaper or reload the preview."), ticket: ticket)
        }
    }

    private func fail(_ message: String, ticket: UInt64) {
        guard ticket == generation else { return }
        let previous = request
        release()
        request = previous
        phase = .failed(message)
        onChange?()
    }

    private func release() {
        generation &+= 1
        operation?.cancel()
        operation = nil
        deadline?.cancel()
        deadline = nil
        surface?.onReady = nil
        surface?.onFailure = nil
        surface?.stop()
        surface = nil
        onSurface?(nil)
        request = nil
        ready = false
    }
}
