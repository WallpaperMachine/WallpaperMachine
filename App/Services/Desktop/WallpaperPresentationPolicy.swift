import AppKit

/// Visibility of the wallpaper surface on one display.
struct WallpaperSurfaceVisibility: Equatable, Sendable {
    let displayID: UInt32
    let isVisible: Bool
}

/// Strongest global presentation wins: `.unloaded` > `.suspended` > `.running`.
enum GlobalPresentation: Comparable, Sendable {
    case running
    case suspended
    case unloaded

    private var rank: Int {
        switch self {
        case .running: 0
        case .suspended: 1
        case .unloaded: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    var logLabel: String {
        switch self {
        case .running: "resumed"
        case .suspended: "suspended"
        case .unloaded: "unloaded"
        }
    }
}

/// Suspends wallpaper presentation per display while no pixel from that display
/// can reach the user, or, unless the user chose to keep it running, while
/// other windows cover that display's working area; and globally only for
/// conditions that really do cover every screen. Suspension never changes the
/// user's Play/Pause choice: the bridge composes this signal with the playback
/// state and restores playback when it clears.
///
/// The split matters for power: a window covering the wallpaper on one display
/// must stop that display's decoding and rendering, and must not stop a display
/// the user is still looking at. Display sleep, session lock, app rules and
/// other-app audio can also suspend or unload every display, and mute wallpaper
/// audio, without touching that choice.
@MainActor
final class WallpaperPresentationPolicy {
    typealias ApplyCompletion = @MainActor (Result<Void, Error>) -> Void

    private let workspaceCenter: NotificationCenter
    private let lockCenter: NotificationCenter
    private let windowCenter: NotificationCenter
    private let surfaces: @MainActor () -> [WallpaperSurfaceVisibility]
    private let isSessionLocked: @MainActor () -> Bool
    private let displaySleepAction: @MainActor () -> DisplaySleepAction
    private let appRuleActions: @MainActor () -> Set<AppRuleAction>
    private let otherAudioActive: @MainActor () -> Bool
    private let otherAudioAction: @MainActor () -> OtherAudioAction
    private let desktopCoveredAction: @MainActor () -> DesktopCoveredAction
    private let coveredDisplays: @MainActor () -> Set<UInt32>
    /// Owned only when neither surfaces nor coverage were injected.
    private let probes: WallpaperCoverageProbes?
    private let occlusionSettleDelay: Duration
    private let counters: RuntimeCounters
    private let applyGlobal: @MainActor (GlobalPresentation, @escaping ApplyCompletion) -> Void
    private let applyAudio: @MainActor (Bool, @escaping ApplyCompletion) -> Void
    private let applyDisplay: @MainActor (UInt32, Bool, @escaping ApplyCompletion) -> Void

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var displaysAsleep = false
    private var settle: Task<Void, Never>?
    private var appliedGlobal: GlobalPresentation? = .running
    private var appliedAudio: Bool? = false
    /// Acknowledged state per display. A display with no entry has never been
    /// told anything, so it is presenting.
    private var appliedDisplays: [UInt32: Bool] = [:]
    /// Displays whose decision still has to reach the renderer, including one
    /// whose delivery failed; a later evaluation retries it.
    private var pendingDisplays: Set<UInt32> = []
    private var deliveryInFlight = false
    /// Conditions under which no display at all can present, and how hard.
    private(set) var globalPresentation: GlobalPresentation = .running
    /// Wallpaper audio held down by a mute rule or other-app audio.
    private(set) var isAudioSuppressed = false
    /// Displays suspended on their own, by occlusion or a covered working area.
    private(set) var suspendedDisplayIDs: Set<UInt32> = []

    /// True when presentation is suspended or unloaded. Occlusion of one display
    /// does not set this.
    var isSuspended: Bool { globalPresentation != .running }

    /// Closures are optional so their `@MainActor` defaults are built inside
    /// this (already `@MainActor`) initializer rather than in a default-argument
    /// expression evaluated in the caller's isolation.
    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        lockCenter: NotificationCenter = DistributedNotificationCenter.default(),
        windowCenter: NotificationCenter = .default,
        surfaces: (@MainActor () -> [WallpaperSurfaceVisibility])? = nil,
        isSessionLocked: (@MainActor () -> Bool)? = nil,
        displaySleepAction: (@MainActor () -> DisplaySleepAction)? = nil,
        appRuleActions: (@MainActor () -> Set<AppRuleAction>)? = nil,
        otherAudioActive: (@MainActor () -> Bool)? = nil,
        otherAudioAction: (@MainActor () -> OtherAudioAction)? = nil,
        desktopCoveredAction: (@MainActor () -> DesktopCoveredAction)? = nil,
        coveredDisplays: (@MainActor () -> Set<UInt32>)? = nil,
        occlusionSettleDelay: Duration = .seconds(1),
        counters: RuntimeCounters? = nil,
        applyGlobal: @escaping @MainActor (GlobalPresentation, @escaping ApplyCompletion) -> Void,
        applyAudio: (@MainActor (Bool, @escaping ApplyCompletion) -> Void)? = nil,
        applyDisplay: @escaping @MainActor (UInt32, Bool, @escaping ApplyCompletion) -> Void
    ) {
        self.workspaceCenter = workspaceCenter
        self.lockCenter = lockCenter
        self.windowCenter = windowCenter
        self.surfaces = surfaces ?? { Self.systemSurfaces() }
        self.isSessionLocked = isSessionLocked ?? { Self.sessionIsLocked() }
        self.displaySleepAction = displaySleepAction ?? { .pause }
        self.appRuleActions = appRuleActions ?? { [] }
        self.otherAudioActive = otherAudioActive ?? { false }
        self.otherAudioAction = otherAudioAction ?? { .keepRunning }
        self.desktopCoveredAction = desktopCoveredAction ?? { .keepRunning }
        if let coveredDisplays {
            self.coveredDisplays = coveredDisplays
            probes = nil
        } else if surfaces == nil {
            let probes = WallpaperCoverageProbes()
            self.coveredDisplays = { probes.coveredDisplayIDs() }
            self.probes = probes
        } else {
            self.coveredDisplays = { [] }
            probes = nil
        }
        self.occlusionSettleDelay = occlusionSettleDelay
        self.counters = counters ?? .shared
        self.applyGlobal = applyGlobal
        self.applyAudio = applyAudio ?? { _, completion in completion(.success(())) }
        self.applyDisplay = applyDisplay
    }

    func start() {
        guard observers.isEmpty else { return }
        for (name, asleep) in [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
        ] {
            observers.append((workspaceCenter, workspaceCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.displaysAsleep = asleep
                    self?.evaluate()
                }
            }))
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append((lockCenter, lockCenter.addObserver(
                forName: .init(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }))
        }
        // object: nil — the control panel appearing over the desktop is exactly
        // what changes a wallpaper window's occlusion, and evaluate() recomputes
        // from every wallpaper window anyway.
        observers.append((windowCenter, windowCenter.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }))
        // A resolution change or the Dock appearing moves the working area the
        // coverage probes measure.
        observers.append((windowCenter, windowCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }))
        evaluate()
    }

    func stop() {
        settle?.cancel()
        settle = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        probes?.removeAll()
        displaysAsleep = false
        // Teardown must never leave a surface suspended or muted.
        pendingDisplays.formUnion(suspendedDisplayIDs)
        suspendedDisplayIDs.removeAll()
        globalPresentation = .running
        isAudioSuppressed = false
        deliverPending()
    }

    /// Every window kind that hosts wallpaper pixels: the renderer's Metal
    /// window, the web wallpaper window, and the native video window. A backend
    /// missing from this list is invisible to occlusion tracking, so its
    /// display would never be suspended or resumed.
    static let wallpaperWindowClassNames = [
        "MWEWallpaperDesktopWindow",
        "MWEWebWallpaperDesktopWindow",
        "MWENativeVideoDesktopWindow",
    ]

    static func wallpaperWindows() -> [NSWindow] {
        let types = wallpaperWindowClassNames.compactMap(NSClassFromString)
        guard !types.isEmpty else { return [] }
        return NSApp.windows.filter { window in types.contains { window.isKind(of: $0) } }
    }

    /// Wallpaper visibility grouped by display. A display counts as visible
    /// when any of its wallpaper windows is visible, so a second window that
    /// AppKit reports as occluded cannot hide a live one.
    static func systemSurfaces() -> [WallpaperSurfaceVisibility] {
        var visibility: [UInt32: Bool] = [:]
        for window in wallpaperWindows() {
            guard let screen = window.screen,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let displayID = number.uint32Value
            let visible = window.occlusionState.contains(.visible)
            visibility[displayID] = (visibility[displayID] ?? false) || visible
        }
        return visibility
            .map { WallpaperSurfaceVisibility(displayID: $0.key, isVisible: $0.value) }
            .sorted { $0.displayID < $1.displayID }
    }

    static func sessionIsLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool
            ?? false
    }

    /// Wallpaper visibility with a covered working area counted as hidden when
    /// the user chose to pause for it.
    private func currentSurfaces() -> [WallpaperSurfaceVisibility] {
        let current = surfaces()
        guard desktopCoveredAction() == .pause else { return current }
        let covered = coveredDisplays()
        guard !covered.isEmpty else { return current }
        return current.map { surface in
            covered.contains(surface.displayID)
                ? WallpaperSurfaceVisibility(displayID: surface.displayID, isVisible: false)
                : surface
        }
    }

    /// Probes exist only while a covered desktop pauses, so keeping the
    /// wallpaper running costs no extra windows.
    private func syncProbes() {
        guard let probes, !observers.isEmpty else { return }
        if desktopCoveredAction() == .pause {
            probes.sync()
        } else {
            probes.removeAll()
        }
    }

    /// Retry unacknowledged delivery even when visibility is unchanged.
    func evaluate() {
        syncProbes()
        let presentation = resolvedPresentation()
        let audio = resolvedAudioSuppressed()
        let current = currentSurfaces()
        let hidden = Set(current.filter { !$0.isVisible }.map(\.displayID))
        let known = Set(current.map(\.displayID))
        settle?.cancel()
        settle = nil

        // A display that is gone gets no decisions, but what was acknowledged
        // for it stays: the bridge and the web and video hosts keep a suspended
        // display suspended across a disconnect. When it returns visible it is
        // resumed; when it returns hidden it is still suspended and stays so.
        pendingDisplays.formIntersection(known)
        suspendedDisplayIDs.formIntersection(known)
        for displayID in known where appliedDisplays[displayID] == true
            && !suspendedDisplayIDs.contains(displayID)
        {
            if hidden.contains(displayID) {
                suspendedDisplayIDs.insert(displayID)
            } else {
                pendingDisplays.insert(displayID)
            }
        }

        if presentation != globalPresentation {
            commitPlayback(presentation: presentation, audio: audio)
            return
        }
        let audioChanged = audio != isAudioSuppressed
        if audioChanged {
            isAudioSuppressed = audio
            AppLog.info("wallpaper audio \(audio ? "suppressed" : "restored")")
        }
        // Resume instantly; delay only occlusion-driven suspension so a Space
        // switch or a Mission Control pass does not freeze a visible wallpaper.
        let revealed = suspendedDisplayIDs.subtracting(hidden)
        let newlyHidden = hidden.subtracting(suspendedDisplayIDs)
        if !revealed.isEmpty {
            suspendedDisplayIDs.subtract(revealed)
            pendingDisplays.formUnion(revealed)
            AppLog.info("presentation resumed for displays \(revealed.sorted())")
            deliverPending()
            if newlyHidden.isEmpty { return }
        }
        guard !newlyHidden.isEmpty else {
            deliverPending()
            return
        }
        guard occlusionSettleDelay > .zero else {
            commitHidden(newlyHidden)
            return
        }
        settle = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: self.occlusionSettleDelay) } catch { return }
            guard !Task.isCancelled else { return }
            let stillHidden = Set(self.currentSurfaces().filter { !$0.isVisible }.map(\.displayID))
            self.commitHidden(newlyHidden.intersection(stillHidden))
        }
        if audioChanged { deliverPending() }
    }

    private func resolvedPresentation() -> GlobalPresentation {
        var strongest = GlobalPresentation.running
        if displaysAsleep {
            strongest = max(strongest, displaySleepAction() == .stop ? .unloaded : .suspended)
        }
        if isSessionLocked() {
            strongest = max(strongest, .suspended)
        }
        let rules = appRuleActions()
        if rules.contains(.stop) {
            strongest = max(strongest, .unloaded)
        } else if rules.contains(.pause) {
            strongest = max(strongest, .suspended)
        }
        if otherAudioActive(), otherAudioAction() == .pause {
            strongest = max(strongest, .suspended)
        }
        return strongest
    }

    private func resolvedAudioSuppressed() -> Bool {
        if appRuleActions().contains(.mute) { return true }
        return otherAudioActive() && otherAudioAction() == .mute
    }

    private func commitPlayback(presentation: GlobalPresentation, audio: Bool) {
        if presentation != globalPresentation {
            globalPresentation = presentation
            AppLog.info("presentation \(presentation.logLabel)")
        }
        if audio != isAudioSuppressed {
            isAudioSuppressed = audio
            AppLog.info("wallpaper audio \(audio ? "suppressed" : "restored")")
        }
        deliverPending()
    }

    private func commitHidden(_ hidden: Set<UInt32>) {
        guard !hidden.isEmpty else {
            deliverPending()
            return
        }
        suspendedDisplayIDs.formUnion(hidden)
        pendingDisplays.formUnion(hidden)
        AppLog.info("presentation suspended for displays \(hidden.sorted())")
        deliverPending()
    }

    private func deliverPending() {
        guard !deliveryInFlight else { return }
        // The global condition is the coarser one, so it goes first. Audio
        // follows, then per-display occlusion, one acknowledgement at a time.
        if appliedGlobal != globalPresentation {
            let presentation = globalPresentation
            deliveryInFlight = true
            applyGlobal(presentation) { [self] result in
                deliveryInFlight = false
                guard case .success = result else {
                    // A failed bridge transaction may have rolled rendering
                    // back. Keep it pending for a later evaluation, and stop
                    // here: retrying now would spin on a rejecting renderer.
                    appliedGlobal = nil
                    return
                }
                appliedGlobal = presentation
                record(presentation != .running, for: RuntimeSurfaceKey(kind: .desktopScene, displayID: 0))
                // Deliveries are serialized, so the rest of the queue — and any
                // decision that changed while this one was in flight — follows
                // the acknowledgement.
                deliverPending()
            }
            return
        }
        if appliedAudio != isAudioSuppressed {
            let suppressed = isAudioSuppressed
            deliveryInFlight = true
            applyAudio(suppressed) { [self] result in
                deliveryInFlight = false
                guard case .success = result else {
                    appliedAudio = nil
                    return
                }
                appliedAudio = suppressed
                deliverPending()
            }
            return
        }
        for displayID in pendingDisplays.sorted() {
            let target = suspendedDisplayIDs.contains(displayID)
            guard appliedDisplays[displayID] != target else {
                pendingDisplays.remove(displayID)
                continue
            }
            deliveryInFlight = true
            applyDisplay(displayID, target) { [self] result in
                deliveryInFlight = false
                guard case .success = result else {
                    // Leave it pending. Retrying here would spin on a renderer
                    // that keeps rejecting the transition.
                    appliedDisplays[displayID] = nil
                    return
                }
                appliedDisplays[displayID] = target
                record(target, for: RuntimeSurfaceKey(kind: .desktopScene, displayID: displayID))
                // The decision may have changed while this one was in flight,
                // in which case the display stays pending and is sent again.
                if appliedDisplays[displayID] == suspendedDisplayIDs.contains(displayID) {
                    pendingDisplays.remove(displayID)
                }
                deliverPending()
            }
            return
        }
    }

    private func record(_ suspended: Bool, for surface: RuntimeSurfaceKey) {
        counters.record(suspended ? .presentationSuspended : .presentationResumed, for: surface)
    }
}
