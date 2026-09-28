import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var controlPanelWindow: NSWindow?
    private let controlPanelNavigation = ControlPanelNavigation()
    private lazy var workshopStore = WorkshopStore()
    private lazy var appUpdater = AppUpdateStore()
    private var automaticUpdates: Task<Void, Never>?
    /// The version the unattended check last prompted for; "Later" holds until the next launch.
    private var promptedUpdateVersion: String?
    private var displayChangeObserver: NSObjectProtocol?
    private lazy var displayRefresh = DisplayRefreshCoalescer { [weak self] in
        guard let self else { return }
        await self.refreshDisplaysFromSystemEvent()
    }
    private var desktopWallpaperSync: DesktopWallpaperSync?
    private var desktopMediaSession: DesktopMediaSession?
    private var sceneMediaSink: SceneMediaSink?
    private var webWallpaperHost: WebWallpaperHost?
    private var nativeVideoHost: NativeVideoWallpaperHost?
    private var presentationPolicy: WallpaperPresentationPolicy?
    private var appRuleMonitor: AppRuleMonitor?
    private var otherAudioMonitor: OtherAudioMonitor?
    private var playbackPreferencesObserver: NSObjectProtocol?
    private var wallpaperEnergy: WallpaperEnergyRecorder?
    /// Last presentation the bridge accepted, so leaving unloaded clears that flag first.
    private var appliedGlobalPresentation: GlobalPresentation = .running
    private var store: BridgeStore?
    private var startupError: Error?
    private var lastError: Error?
    private var playbackSnapshotCurrent = false
    private var shutdownInProgress = false
    private var shutdownComplete = false
    private var themeSubscription: AnyCancellable?
    private var iconSubscription: AnyCancellable?
    private var diagnostics: RuntimeDiagnosticsSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests need the executable's types, not its desktop lifecycle.
        // UI tests run in a separate runner, so the real app still starts normally.
        if NSClassFromString("XCTestCase") != nil {
            NSApp.setActivationPolicy(.prohibited)
            return
        }
        themeSubscription = AppThemeStore.shared.$preferences
            .map(\.mode).removeDuplicates()
            .sink { mode in NSApp.appearance = mode.appearance }
        iconSubscription = AppThemeStore.shared.$preferences
            .map(\.icon).removeDuplicates()
            .sink { icon in
                do {
                    NSApp.applicationIconImage = try icon.image()
                } catch {
                    AppLog.error("Dock icon \(icon.rawValue) could not load: \(error.localizedDescription)")
                }
            }
        AppLog.info("startup: didFinishLaunching start")
        BridgeEnvironment.configureVulkanICDIfNeeded()
        AppLog.info("startup: vulkan icd configured")
        do {
            try ClientPaths.prepare()
            let created = try BridgeStore()
            store = created
            AppLog.attach(created.bridge)
            for line in DiagnosticEnvironment.current() { AppLog.info("environment: \(line)") }
            startupError = nil
            playbackSnapshotCurrent = false
            AppLog.info("startup: BridgeStore created")
        } catch {
            AppLog.detachToStandardError()
            AppLog.error("startup: BridgeStore FAILED: \(error.localizedDescription)")
            startupError = error
            playbackSnapshotCurrent = false
        }
        // A crash during a download leaves its staging behind, holding the whole downloaded item.
        let stagingRoot = ClientPaths.supportURL
        Task.detached(priority: .utility) {
            WorkshopDownloader.removeAbandonedStaging(in: stagingRoot)
        }

        NSApp.setActivationPolicy(.accessory)
        AppLog.info("startup: activation policy set to accessory")
        installStatusItem()
        synchronizeStatusItem()
        installDisplayChangeObserver()
        AppLog.info("startup: display change observer installed")
        installApplicationMenu()
        AppLog.info("startup: application menu installed")
        if let store {
            let lockScreen = LockScreenConfiguration.isSupportedBySystem
                ? LockScreenWallpaperService(bridge: store.bridge) : nil
            if let lockScreen {
                store.lockScreenWallpaper = lockScreen
                lockScreen.beforeActivation = { [weak self] in
                    guard let self else { return }
                    if self.desktopWallpaperSync == nil {
                        self.desktopWallpaperSync = try DesktopWallpaperSync(
                            folder: ClientPaths.supportURL.appendingPathComponent("DesktopPosters"))
                    }
                    self.desktopWallpaperSync?.suspendForNativeProvider()
                }
                lockScreen.afterDeactivation = { [weak self] in
                    self?.desktopWallpaperSync = nil
                    try self?.startDesktopWallpaperSync()
                }
            }
            let mediaScheduler = FoundationMediaTimerScheduler()
            let mediaSession = DesktopMediaSession(
                provider: FallbackSystemMediaProvider(
                    primary: AdapterSystemMediaProvider(scheduler: mediaScheduler),
                    fallback: AppleScriptMediaProvider(scheduler: mediaScheduler),
                    scheduler: mediaScheduler))
            desktopMediaSession = mediaSession
            let webHost = WebWallpaperHost(bridge: store.bridge, mediaRelay: mediaSession.relay)
            webWallpaperHost = webHost
            store.sceneMediaAvailability = { [weak mediaSession] in
                mediaSession?.availability ?? .unavailable(reason: String(localized: "Media integration has not been started."))
            }
            sceneMediaSink = SceneMediaSink(
                session: mediaSession,
                submit: { json in
                    try await store.bridge.submitSystemMediaEvent(json: json)
                },
                applyArtwork: { width, height, rgba in
                    try await store.bridge.applySystemMediaArtwork(
                        width: width, height: height, rgba: rgba)
                },
                fetchHandles: {
                    await Self.sceneMediaHandles(store: store)
                },
                nextShortcut: {
                    try await store.bridge.nextUserShortcut()
                })
            // The panel distinguishes the user's setting from what is actually
            // being delivered, which only the host knows. The provider is
            // process-wide, so a scene wallpaper can populate it too.
            store.webWallpaperDeliveryStatus = { [weak webHost] in
                webHost?.deliveryStatus ?? WebWallpaperHost.DeliveryStatus()
            }
            webHost.onError = { [weak self] message in
                self?.lastError = WallpaperActionError(message: message)
                self?.rebuildMenu()
            }
            webHost.onSurfacesChanged = { [weak self, weak lockScreen] in
                guard let self, !self.shutdownInProgress else { return }
                self.presentationPolicy?.evaluate()
                guard lockScreen?.ownsDesktopProvider != true else { return }
                do { try self.startDesktopWallpaperSync() } catch {
                    AppLog.error("Desktop poster sync could not be restarted: \(error.localizedDescription)")
                }
            }
            webHost.start()
            // The experimental native video backend. The bridge returns nothing
            // for it unless the user turned it on, so this host opens no window
            // and starts no player by default.
            let nativeVideo = NativeVideoWallpaperHost(bridge: store.bridge)
            nativeVideoHost = nativeVideo
            nativeVideo.onError = { [weak self] message in
                self?.lastError = WallpaperActionError(message: message)
                self?.rebuildMenu()
            }
            nativeVideo.onSurfacesChanged = { [weak self] in
                guard let self, !self.shutdownInProgress else { return }
                self.presentationPolicy?.evaluate()
            }
            nativeVideo.start()
            store.onSnapshotApplied = { [weak self, weak lockScreen] in
                guard let self, !self.shutdownInProgress else { return }
                // Any engine change (playback, assignment, quality) ends the interval
                // being measured; its two ends could otherwise match across it.
                self.wallpaperEnergy?.invalidate()
                // Web wallpapers live in host windows; open or close them before
                // the poster sync and the presentation policy look at the desktop.
                self.webWallpaperHost?.reconcile()
                self.sceneMediaSink?.reconcile()
                self.nativeVideoHost?.reconcile()
                self.presentationPolicy?.evaluate()
                if let lockScreen, lockScreen.isRequested, lockScreen.errorMessage == nil {
                    lockScreen.refresh()
                } else if lockScreen?.ownsDesktopProvider != true {
                    // A suspended poster sync must never outlive the native provider.
                    do { try self.startDesktopWallpaperSync() } catch {
                        self.lastError = error
                        AppLog.error("Desktop poster sync could not be restarted: \(error.localizedDescription)")
                    }
                }
            }
            let preferences = PlaybackPreferences.shared
            let appRules = AppRuleMonitor(preferences: preferences)
            let otherAudio = OtherAudioMonitor(preferences: preferences)
            appRuleMonitor = appRules
            otherAudioMonitor = otherAudio
            appRules.onChange = { [weak self] in self?.presentationPolicy?.evaluate() }
            otherAudio.onChange = { [weak self] in self?.presentationPolicy?.evaluate() }
            playbackPreferencesObserver = NotificationCenter.default.addObserver(
                forName: PlaybackPreferences.didChangeNotification, object: preferences, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncPlaybackMonitors()
                    self?.presentationPolicy?.evaluate()
                }
            }
            let policy = WallpaperPresentationPolicy(
                displaySleepAction: { preferences.displaySleepAction },
                appRuleActions: { appRules.actions },
                otherAudioActive: { otherAudio.isActive },
                otherAudioAction: { preferences.otherAudioAction },
                desktopCoveredAction: { preferences.desktopCoveredAction },
                applyGlobal: { [weak self] presentation, completion in
                    guard let self, let store = self.store,
                          !self.shutdownInProgress, !self.shutdownComplete else {
                        completion(.failure(CancellationError()))
                        return
                    }
                    let hostsSuspended = presentation != .running
                    self.webWallpaperHost?.setPresentationSuspended(hostsSuspended)
                    self.nativeVideoHost?.setPresentationSuspended(hostsSuspended)
                    let leavingUnloaded = self.appliedGlobalPresentation == .unloaded
                        && presentation != .unloaded
                    self.wallpaperEnergy?.invalidate()
                    Task {
                        do {
                            if leavingUnloaded {
                                try await store.setPresentationUnloadedAsync(false)
                            }
                            switch presentation {
                            case .running:
                                try await store.setPresentationSuspendedAsync(false)
                            case .suspended:
                                try await store.setPresentationSuspendedAsync(true)
                            case .unloaded:
                                try await store.setPresentationSuspendedAsync(true)
                                try await store.setPresentationUnloadedAsync(true)
                            }
                            self.appliedGlobalPresentation = presentation
                            // Presentation suspend commits without producing a
                            // snapshot, so nothing else would recompute who is
                            // still consuming system media. Without this the
                            // adapter process and its timeline ticker keep
                            // running for scenes that stopped presenting, until
                            // some unrelated UI change happens to apply one.
                            self.sceneMediaSink?.reconcile()
                            completion(.success(()))
                        } catch {
                            AppLog.error("presentation suspend failed: \(error.localizedDescription)")
                            completion(.failure(error))
                        }
                    }
                },
                applyAudio: { [weak self] suppressed, completion in
                    guard let self, let store = self.store,
                          !self.shutdownInProgress, !self.shutdownComplete else {
                        completion(.failure(CancellationError()))
                        return
                    }
                    Task {
                        do {
                            try await store.setAudioSuppressedAsync(suppressed)
                            completion(.success(()))
                        } catch {
                            AppLog.error("audio suppress failed: \(error.localizedDescription)")
                            completion(.failure(error))
                        }
                    }
                },
                applyDisplay: { [weak self] displayID, suspended, completion in
                    guard let self, let store = self.store,
                          !self.shutdownInProgress, !self.shutdownComplete else {
                        completion(.failure(CancellationError()))
                        return
                    }
                    self.webWallpaperHost?.setPresentationSuspended(suspended, forDisplay: displayID)
                    self.nativeVideoHost?.setPresentationSuspended(suspended, forDisplay: displayID)
                    self.wallpaperEnergy?.invalidate()
                    Task {
                        do {
                            try await store.setDisplayPresentationSuspendedAsync(
                                displayID: displayID, suspended: suspended)
                            // Same reason as the global path: a display going
                            // dark changes the effective consumer set and
                            // produces no snapshot of its own.
                            self.sceneMediaSink?.reconcile()
                            completion(.success(()))
                        } catch {
                            AppLog.error("""
                                presentation suspend for display \(displayID) failed: \
                                \(error.localizedDescription)
                                """)
                            completion(.failure(error))
                        }
                    }
                })
            presentationPolicy = policy
            syncPlaybackMonitors()
            policy.start()
            startWallpaperEnergyRecorder(store: store)
            do {
                try lockScreen?.start()
                if lockScreen?.isRequested != true { try startDesktopWallpaperSync() }
            } catch {
                lastError = error
                AppLog.error("startup: Native wallpaper recovery failed: \(error.localizedDescription)")
            }
        }
        bootstrapStore()
        AppLog.info("startup: bootstrap dispatched")
        startDiagnosticsSessionIfRequested()
        DispatchQueue.main.async { [weak self] in
            self?.showControlPanel(selection: .wallpaper)
        }
    }

    /// Rates each wallpaper's energy use from background samples while it plays alone.
    /// See `WallpaperEnergyRecorder`; `wallpaperEnergyContext()` decides when a sample
    /// can be credited.
    private func startWallpaperEnergyRecorder(store: BridgeStore) {
        let ratings = WallpaperEnergyRatings(
            file: ClientPaths.supportURL.appendingPathComponent("EnergyRatings.json"))
        store.wallpaperEnergyRatings = ratings
        let recorder = WallpaperEnergyRecorder(
            source: CoalitionEnergySource(), ratings: ratings
        ) { [weak self] in self?.wallpaperEnergyContext() }
        wallpaperEnergy = recorder
        recorder.start()
    }

    /// Nil whenever the app's energy is not one wallpaper's: playback paused or suspended
    /// (display sleep, lock, app rules, other audio, battery pause), the panel on screen
    /// with its WebKit work, or a download running SteamCMD inside the app's coalition.
    private func wallpaperEnergyContext() -> WallpaperEnergyContext? {
        guard let store, let policy = presentationPolicy, !shutdownInProgress,
              policy.globalPresentation == .running,
              store.appSnapshot.playbackState == .playing,
              !workshopStore.downloader.isRunning
        else { return nil }
        if let window = controlPanelWindow, window.isVisible, !window.isMiniaturized,
           window.occlusionState.contains(.visible) {
            return nil
        }
        let settings = store.settingsSnapshot
        let reduced = settings.batteryMode == .reducedQuality && settings.onBatteryPower
        let cap = [settings.frameRateCap, reduced ? settings.batteryTargetFps : nil]
            .compactMap { $0 }.min()
        return WallpaperEnergyContext.resolve(
            assignments: store.monitorInformationSnapshot.rows.map {
                (display: $0.displayId, wallpaper: $0.wallpaperId)
            },
            suspendedDisplays: policy.suspendedDisplayIDs,
            frameRateCap: cap, renderScale: settings.renderScale)
    }

    /// Opens a bounded diagnostic window when the environment explicitly asks
    /// for one. Absent the variable nothing is started, nothing is counted and
    /// no timer exists: the renderer's counters stay off and the in-process
    /// counters stay outside a session.
    ///
    /// `WALLPAPER_MACHINE_DIAGNOSTICS` is a duration in seconds, and
    /// `WALLPAPER_MACHINE_DIAGNOSTICS_DELAY` optionally opens the window that
    /// many seconds after launch (see `RuntimeDiagnosticsRequest`). One
    /// aggregated report is written to the log when it elapses; nothing is
    /// emitted per frame, and no screenshot, pixel readback or periodic disk
    /// write is involved.
    private func startDiagnosticsSessionIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let store, environment[RuntimeDiagnosticsRequest.durationKey] != nil else { return }
        guard let request = RuntimeDiagnosticsRequest(environment: environment) else {
            AppLog.error("""
                diagnostics not started: \(RuntimeDiagnosticsRequest.durationKey) and \
                \(RuntimeDiagnosticsRequest.delayKey) take whole seconds
                """)
            return
        }
        let session = RuntimeDiagnosticsSession(store: store)
        diagnostics = session
        Task { [weak self] in
            do {
                if request.delay > .zero {
                    try await Task.sleep(for: request.delay)
                    // Quit during the delay: there is nothing left to observe.
                    guard let self, self.diagnostics === session else { return }
                }
                try await session.start(duration: request.duration) { lines in
                    for line in lines { AppLog.info("diagnostics \(line)") }
                    self?.diagnostics = nil
                }
                AppLog.info("diagnostics session open for \(request.duration.components.seconds)s")
            } catch {
                AppLog.error("diagnostics session failed: \(error.localizedDescription)")
                self?.diagnostics = nil
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !shutdownInProgress, !shutdownComplete,
              let window = controlPanelWindow, !window.isVisible else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPlaybackMonitoring()
        wallpaperEnergy?.stop()
        wallpaperEnergy = nil
        presentationPolicy?.stop()
        presentationPolicy = nil
        desktopWallpaperSync?.stop()
        sceneMediaSink?.shutdown()
        webWallpaperHost?.shutdown()
        nativeVideoHost?.shutdown()
        if let displayChangeObserver {
            NotificationCenter.default.removeObserver(displayChangeObserver)
            self.displayChangeObserver = nil
        }
        if let diagnostics {
            self.diagnostics = nil
            Task { await diagnostics.stop() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The test host must not instantiate services against the user's app-support folder.
        if NSClassFromString("XCTestCase") != nil { return .terminateNow }
        guard !shutdownComplete else {
            return .terminateNow
        }
        guard !shutdownInProgress else {
            return .terminateCancel
        }

        shutdownInProgress = true
        desktopWallpaperSync?.suspendForNativeProvider()
        controlPanelWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)

        Task {
            do {
                try await store?.lockScreenWallpaper?.shutdown()
                stopPlaybackMonitoring()
                wallpaperEnergy?.stop()
                wallpaperEnergy = nil
                presentationPolicy?.stop()
                presentationPolicy = nil
                desktopWallpaperSync?.stop()
                desktopWallpaperSync = nil
                sceneMediaSink?.shutdown()
                sceneMediaSink = nil
                webWallpaperHost?.shutdown()
                webWallpaperHost = nil
            } catch {
                lastError = error
                shutdownInProgress = false
                presentationPolicy?.evaluate()
                rebuildMenu()
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            automaticUpdates?.cancel()
            appUpdater.cancel()
            await workshopStore.steamCMDSetup.shutdown()
            await workshopStore.downloader.shutdown()
            do {
                try await store?.shutdownAsync()
                lastError = nil
            } catch {
                lastError = error
            }

            shutdownInProgress = false
            shutdownComplete = true
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    private func syncPlaybackMonitors() {
        let preferences = PlaybackPreferences.shared
        if preferences.appRules.isEmpty {
            appRuleMonitor?.stop()
        } else {
            appRuleMonitor?.start()
        }
        if preferences.otherAudioAction == .keepRunning {
            otherAudioMonitor?.stop()
        } else {
            otherAudioMonitor?.start()
        }
    }

    private func stopPlaybackMonitoring() {
        if let playbackPreferencesObserver {
            NotificationCenter.default.removeObserver(playbackPreferencesObserver)
            self.playbackPreferencesObserver = nil
        }
        appRuleMonitor?.stop()
        otherAudioMonitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A Dock click returns to the last native section, even after releasing the page.
        showControlPanel(selection: controlPanelNavigation.selection ?? .wallpaper)
        return false
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStoreSnapshot()
        rebuildMenu(menu)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === controlPanelWindow, controlPanelNavigation.isImporting else { return true }
        // ponytail: retain the page during an import so dismantling cannot cancel it;
        // the next close releases it. Move import ownership to a store if this grows.
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === controlPanelWindow else { return frameSize }
        return ControlPanelWindow.clampedFrameSize(frameSize, for: sender)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === controlPanelWindow
        else {
            return
        }

        controlPanelWindow = nil
        // Closing releases the page and its WebKit processes; reopening builds a
        // fresh view around the existing stores and navigation.
        window.contentViewController = nil
        NSApp.setActivationPolicy(.accessory)
        rebuildMenu()
    }

    private func startDesktopWallpaperSync() throws {
        guard !shutdownInProgress else { return }
        if let sync = desktopWallpaperSync, !sync.isSuspended {
            sync.refresh()
            return
        }
        let sync = try DesktopWallpaperSync(folder: ClientPaths.supportURL.appendingPathComponent("DesktopPosters"))
        desktopWallpaperSync = sync
        sync.start()
        sync.refresh()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        let button = item.button
        let trayIcon = NSImage(named: "TrayIcon")
        if let button {
            button.image = trayIcon
                ?? NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: "WallpaperMachine")
            button.image?.isTemplate = true
        }

        AppLog.info("startup: statusItem installed: button=\(button != nil) trayIconAssetResolved=\(trayIcon != nil)")

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        rebuildMenu(menu)
    }

    /// Work around an AppKit/SwiftUI timing issue: when launched via
    /// LaunchServices (Finder double-click) in `.accessory` activation
    /// policy, a status item created in `applicationDidFinishLaunching`
    /// may be created correctly but never rendered because the SwiftUI
    /// Scene phase hasn't stabilized yet. Deferring by one runloop turn
    /// gives the Scene phase time to settle. Re-asserting the activation
    /// policy afterwards forces AppKit to re-register accessory-mode
    /// status items with the Window Server; rebuilding the menu alone
    /// only mutates `NSMenu` items and does not touch the status item's
    /// backing window, so it is insufficient by itself.
    private func synchronizeStatusItem() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.statusItem != nil else { return }
            // Re-assert the activation policy to force AppKit to
            // re-register the accessory-mode status item with the
            // Window Server after the SwiftUI Scene phase has settled.
            if self.controlPanelWindow == nil { NSApp.setActivationPolicy(.accessory) }
            self.rebuildMenu()
        }
    }

    private func installDisplayChangeObserver() {
        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.displayRefresh.request()
            }
        }
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "WallpaperMachine")
        let settings = menuItem("Settings…", action: #selector(openSettings))
        settings.keyEquivalent = ","
        applicationMenu.addItem(settings)
        applicationMenu.addItem(menuItem("Check for Updates…", action: #selector(checkForUpdates)))
        applicationMenu.addItem(.separator())
        let quit = menuItem("Quit WallpaperMachine", action: #selector(exitApplication))
        quit.keyEquivalent = "q"
        applicationMenu.addItem(quit)
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        // Command-W reaches the key window, so the panel hides exactly as its close button does.
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenu.addItem(
            withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)

        // Keep standard text editing shortcuts in search and setup fields.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "Edit"))
        let editCommands: [(String.LocalizationValue, Selector, String)] = [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ]
        for (title, action, key) in editCommands {
            editMenu.addItem(withTitle: String(localized: title), action: action, keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func rebuildMenu(_ menu: NSMenu? = nil) {
        guard let menu = menu ?? statusItem?.menu else {
            return
        }

        menu.removeAllItems()
        menu.addItem(menuItem("Control Panel", action: #selector(openControlPanel)))

        var actions: [NSMenuItem] = []
        if let store,
           playbackSnapshotCurrent,
           !store.appSnapshot.activeWallpaperIds.isEmpty
        {
            let playbackTitle: String.LocalizationValue = store.appSnapshot.playbackState == .paused ? "Play" : "Pause"
            actions.append(menuItem(playbackTitle, action: #selector(togglePlayback)))
        }
        if let store, !shutdownInProgress, !shutdownComplete,
           store.activatingWallpaperID == nil,
           store.nextWallpaperID(displayId: controlPanelNavigation.targetDisplayID) != nil
        {
            actions.append(menuItem("Next Wallpaper", action: #selector(activateNextWallpaper)))
        }
        if ScreenLock.isAvailable {
            actions.append(menuItem("Lock Screen", action: #selector(lockScreen)))
        }
        if !actions.isEmpty {
            menu.addItem(.separator())
            actions.forEach(menu.addItem)
        }

        if let item = updateMenuItem() {
            menu.addItem(.separator())
            menu.addItem(item)
        }

        if let error = startupError ?? lastError {
            menu.addItem(.separator())
            menu.addItem(disabledMenuItem(error.localizedDescription))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Exit", action: #selector(exitApplication)))
    }

    private func menuItem(_ title: String.LocalizationValue, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: title),
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    private func disabledMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openControlPanel() {
        showControlPanel(selection: .wallpaper)
    }

    @objc func openSettings() {
        showControlPanel(selection: .settings)
    }

    @objc func checkForUpdates() {
        controlPanelNavigation.revealSettingsSection(.about)
        showControlPanel(selection: .settings)
        Task { _ = await appUpdater.checkForUpdates() }
    }

    /// Checks at launch and every six hours after, because a menu-bar app can run for weeks
    /// without relaunching. `Task.sleep` follows the continuous clock, so a Mac that slept
    /// through the interval checks as soon as it wakes.
    private func startAutomaticUpdates() {
        guard automaticUpdates == nil else { return }
        automaticUpdates = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runAutomaticUpdate()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    private func runAutomaticUpdate() async {
        let state = await appUpdater.checkAndDownloadInBackground()
        rebuildMenu()
        guard !shutdownInProgress, !shutdownComplete,
              let version = state.availableVersion, version != promptedUpdateVersion else { return }
        switch state {
        case .ready:
            promptedUpdateVersion = version
            promptUpdate(
                title: String(localized: "WallpaperMachine \(version) is ready to install"),
                detail: String(localized: "It has been downloaded. WallpaperMachine quits and reopens to finish installing it."),
                confirm: String(localized: "Restart to Update"),
                confirmed: installDownloadedUpdate)
        case .available, .manual:
            promptedUpdateVersion = version
            promptUpdate(
                title: String(localized: "WallpaperMachine \(version) is available"),
                detail: String(localized: "See what's new and download it in Settings."),
                confirm: String(localized: "View Update"),
                confirmed: showUpdate)
        default:
            break
        }
    }

    /// Shown from the main run loop, not this task: a modal run inside a main-actor task would
    /// stall every other main-actor task until the alert closes.
    private func promptUpdate(title: String, detail: String, confirm: String, confirmed: @escaping () -> Void) {
        AppUpdateStore.performOnMainRunLoop { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.shutdownInProgress, !self.shutdownComplete else { return }
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = detail
                alert.addButton(withTitle: confirm)
                alert.addButton(withTitle: String(localized: "Later"))
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn, !self.shutdownInProgress else { return }
                confirmed()
            }
        }
    }

    /// "Later" leaves the update one click away in the status menu.
    private func updateMenuItem() -> NSMenuItem? {
        switch appUpdater.state {
        case .ready(_, let version):
            return menuItem("Restart to Update to \(version)", action: #selector(installDownloadedUpdate))
        case .available(_, let version), .manual(_, let version):
            return menuItem("WallpaperMachine \(version) Available…", action: #selector(showUpdate))
        default:
            return nil
        }
    }

    @objc private func installDownloadedUpdate() {
        Task {
            await appUpdater.installUpdate()
            // A failed install explains itself, and offers GitHub Releases, in About.
            if case .error = appUpdater.state { showUpdate() }
        }
    }

    @objc private func showUpdate() {
        controlPanelNavigation.revealSettingsSection(.about)
        showControlPanel(selection: .settings)
    }

    private func showControlPanel(selection: SidebarSelection) {
        controlPanelNavigation.selection = selection
        NSApp.setActivationPolicy(.regular)

        if let controlPanelWindow {
            ControlPanelWindow.constrainToScreen(controlPanelWindow)
            controlPanelWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller: NSHostingController<AnyView>
        if let store {
            controller = NSHostingController(
                rootView: AnyView(
                    ControlPanelView(
                        store: store,
                        navigation: controlPanelNavigation,
                        workshop: workshopStore,
                        updater: appUpdater
                    )
                )
            )
        } else {
            controller = NSHostingController(
                rootView: AnyView(BridgeUnavailableView(error: startupError ?? lastError))
            )
        }

        // AppKit owns this resizable window's bounds; content must accept its proposal
        // instead of promoting a long label or a split pane's ideal width to a window minimum.
        controller.sizingOptions = []
        let window = ControlPanelWindow.make(contentViewController: controller, delegate: self)
        let frameName = ControlPanelWindow.frameAutosaveName
        if !window.setFrameUsingName(frameName) { window.center() }
        ControlPanelWindow.constrainToScreen(window)
        window.setFrameAutosaveName(frameName)

        controlPanelWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePlayback() {
        guard let store,
              !shutdownInProgress,
              !shutdownComplete,
              playbackSnapshotCurrent,
              !store.appSnapshot.activeWallpaperIds.isEmpty
        else {
            return
        }

        Task {
            do {
                if store.appSnapshot.playbackState == .paused {
                    try await store.playAllAsync()
                } else {
                    try await store.pauseAllAsync()
                }
                lastError = nil
                playbackSnapshotCurrent = true
                rebuildMenu()
            } catch {
                lastError = error
                playbackSnapshotCurrent = false
                rebuildMenu()
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func activateNextWallpaper() {
        let displayId = controlPanelNavigation.targetDisplayID
        guard let store, !shutdownInProgress, !shutdownComplete,
              let id = store.nextWallpaperID(displayId: displayId)
        else {
            return
        }

        Task {
            do {
                try await store.activateWallpaperAsync(id: id, displayId: displayId)
                lastError = nil
            } catch {
                lastError = error
            }
            rebuildMenu()
        }
    }

    @objc private func lockScreen() {
        ScreenLock.lock()
    }

    @objc private func exitApplication() {
        NSApp.terminate(nil)
    }

    private func bootstrapStore() {
        AppLog.info("startup: bootstrapAsync start")
        guard let store else {
            AppLog.info("startup: bootstrapAsync skipped: store is nil")
            return
        }

        Task {
            do {
                try await store.bootstrapAsync()
                startupError = nil
                lastError = nil
                playbackSnapshotCurrent = true
                AppLog.info("startup: bootstrapAsync completed successfully")
            } catch {
                AppLog.error("startup: bootstrapAsync FAILED: \(error.localizedDescription)")
                lastError = error
                playbackSnapshotCurrent = false
            }
            rebuildMenu()
            // Also after a failed start: the update may be the fix.
            startAutomaticUpdates()
        }
    }

    private func refreshStoreSnapshot() {
        guard let store,
              !shutdownInProgress,
              !shutdownComplete
        else {
            return
        }

        Task {
            do {
                try await store.refreshAllAsync()
                lastError = nil
                playbackSnapshotCurrent = true
            } catch {
                lastError = error
                playbackSnapshotCurrent = false
            }
            rebuildMenu()
        }
    }

    private func refreshDisplaysFromSystemEvent() async {
        guard let store,
              !shutdownInProgress,
              !shutdownComplete
        else {
            return
        }

        do {
            try await store.refreshDisplaysAsync()
            lastError = nil
            playbackSnapshotCurrent = true
        } catch {
            lastError = error
            playbackSnapshotCurrent = false
        }
        rebuildMenu()
    }

    /// The applied desktop Scenes that have consented to now-playing.
    ///
    /// The bridge answers, not the library snapshot: consent is per wallpaper
    /// and the snapshot does not carry it. Nothing reads the system player
    /// while this is empty, so a user who left the setting off is never asked
    /// for Automation permission, and a handle that was not there before is a
    /// scene that still has to be told what is playing.
    private static func sceneMediaHandles(store: BridgeStore) async -> Set<UInt64> {
        do {
            return Set(try await store.bridge.systemMediaSceneHandles())
        } catch {
            AppLog.warn("Scene media consumers could not be read: \(error.localizedDescription)")
            return []
        }
    }

}

private struct BridgeUnavailableView: View {
    let error: Error?

    var body: some View {
        ContentUnavailableView(
            "Bridge Unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text(error?.localizedDescription ?? String(localized: "The rendering bridge could not be started."))
        )
        .frame(minWidth: 640, minHeight: 420)
    }
}
