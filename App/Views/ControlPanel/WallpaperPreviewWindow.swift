import AppKit

/// A regular, non-restored utility window; all playback belongs to its private session.
@MainActor
final class WallpaperPreviewWindowController: NSWindowController, NSWindowDelegate {
    let session: WallpaperPreviewSession
    var onClosed: (() -> Void)?
    private let container = NSView()
    private let playButton = NSButton()
    private let muteButton = NSButton()
    private let reloadButton = NSButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var screensAwake = true
    private var unlocked = true
    private var sessionActive = true

    init(session: WallpaperPreviewSession) {
        self.session = session
        super.init(window: nil)
        session.onSurface = { [weak self] view in self?.attach(view) }
        session.onChange = { [weak self] in self?.render() }
    }

    required init?(coder: NSCoder) { nil }

    func present(_ selection: WallpaperPreviewSession.Selection) {
        if window == nil { makeWindow() }
        session.open(selection)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateVisibility()
    }

    /// Pure sizing rule so small and rotated displays can be checked without opening a window.
    static func contentSize(visibleSize: CGSize) -> CGSize {
        let width = max(1, min(1000, visibleSize.width - 40))
        let height = max(1, min(width * 9 / 16 + 96, visibleSize.height - 80))
        return CGSize(width: width, height: height)
    }

    private func makeWindow() {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let size = Self.contentSize(visibleSize: visible)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        self.window = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.acceptsMouseMovedEvents = true
        window.title = String(localized: "Wallpaper Preview")
        window.contentMinSize = CGSize(width: min(480, size.width), height: min(320, size.height))
        window.center()
        window.contentView = makeContentView(size: size)
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observe(.default, name: name)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, name: NSWorkspace.screensDidSleepNotification) { $0.screensAwake = false }
        observe(workspace, name: NSWorkspace.screensDidWakeNotification) { $0.screensAwake = true }
        observe(workspace, name: NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        observe(workspace, name: NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        observe(DistributedNotificationCenter.default(), name: .init("com.apple.screenIsLocked")) { $0.unlocked = false }
        observe(DistributedNotificationCenter.default(), name: .init("com.apple.screenIsUnlocked")) { $0.unlocked = true }
        render()
    }

    /// Builds ordinary views only; layout tests never create or order an NSWindow.
    func makeContentView(size: CGSize) -> NSView {
        let root = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)

        for (button, action) in [(playButton, #selector(togglePause)), (muteButton, #selector(toggleMute)), (reloadButton, #selector(reload))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.setContentHuggingPriority(.required, for: .horizontal)
        }
        reloadButton.title = String(localized: "Reload preview")
        reloadButton.toolTip = String(localized: "Reload with the current wallpaper options.")
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        progress.setContentHuggingPriority(.required, for: .horizontal)
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.isSelectable = true
        status.identifier = NSUserInterfaceItemIdentifier("preview-status")
        status.translatesAutoresizingMaskIntoConstraints = false
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setAccessibilityElement(true)
        let controls = NSStackView(views: [playButton, muteButton, reloadButton, NSView(), progress])
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.distribution = .fill
        controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false
        let note = NSTextField(wrappingLabelWithString: String(localized: "Preview does not change your desktop. Audio response and media information are unavailable here."))
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)
        root.addSubview(status)
        root.addSubview(note)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -12),
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            controls.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            status.bottomAnchor.constraint(equalTo: note.topAnchor, constant: -6),
            note.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            note.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            note.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        render()
        return root
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name,
                         change: @escaping @MainActor (WallpaperPreviewWindowController) -> Void = { _ in }) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(self)
                self.updateVisibility()
            }
        }
        observers.append((center, token))
    }

    private func attach(_ view: NSView?) {
        for child in container.subviews { child.removeFromSuperview() }
        guard let view else { return }
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    private func render() {
        window?.title = session.title.isEmpty ? String(localized: "Wallpaper Preview")
            : String(localized: "Preview — \(session.title)")
        playButton.title = session.userPaused ? String(localized: "Play") : String(localized: "Pause")
        playButton.toolTip = session.userPaused ? String(localized: "Play preview") : String(localized: "Pause preview")
        playButton.setAccessibilityLabel(playButton.toolTip)
        playButton.isEnabled = session.phase == .playing || session.phase == .paused
        muteButton.title = session.muted ? String(localized: "Unmute") : String(localized: "Mute")
        muteButton.toolTip = session.muted ? String(localized: "Turn preview sound on") : String(localized: "Mute preview")
        muteButton.setAccessibilityLabel(muteButton.toolTip)
        muteButton.isEnabled = session.surface != nil
        reloadButton.isEnabled = session.selection != nil
        switch session.phase {
        case .closed: status.stringValue = ""
        case .loading: status.stringValue = String(localized: "Loading preview…")
        case .playing: status.stringValue = String(localized: "Playing preview")
        case .paused: status.stringValue = String(localized: "Preview paused")
        case .failed(let message): status.stringValue = message
        }
        status.toolTip = status.stringValue
        if session.phase == .loading { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }

    @objc private func togglePause() { session.togglePause() }
    @objc private func toggleMute() { session.toggleMute() }
    @objc private func reload() { session.reload() }

    private func updateVisibility() {
        guard let window else { session.setVisible(false); return }
        session.setVisible(screensAwake && unlocked && sessionActive && window.isVisible && !window.isMiniaturized && !NSApp.isHidden
            && window.occlusionState.contains(.visible))
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { session.setVisible(false) }
    func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }
    func windowWillClose(_ notification: Notification) {
        session.close()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        onClosed?()
    }
}
