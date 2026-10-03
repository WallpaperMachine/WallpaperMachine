import AVFoundation
import AppKit

/// What the host needs from one display's surface.
///
/// The real implementation is a desktop window owning the platform player.
/// Keeping it behind this boundary is what lets the host's routing, fallback
/// and suspension rules be checked without opening a window: the desktop is
/// not available to an automated run, and a test that ordered a
/// desktop-level window onto the screen would be doing exactly that.
@MainActor
protocol NativeVideoSurface: AnyObject {
    var posterLayer: CALayer? { get }
    func setScreenFrame(_ frame: NSRect)
    func setVolume(_ volume: Float, muted: Bool)
    func setScaling(_ mode: BridgeScalingMode)
    func setUserPaused(_ paused: Bool)
    func setPresentationSuspended(_ suspended: Bool)
    var isPlaying: Bool { get }
    var isReadyForDisplay: Bool { get }
    var onReadyForDisplay: (@MainActor () -> Void)? { get set }
    func posterImage() async -> CGImage?
    /// Called when the platform player fails to prepare or play the asset.
    ///
    /// Metadata loading succeeding says nothing about whether playback will:
    /// a track can be readable and still fail to decode, and the failure only
    /// surfaces on `AVPlayerItem.status`. Without this the wallpaper stays
    /// native-selected with the scene engine excluded, so the display shows a
    /// black rectangle for as long as it is assigned. The argument is the
    /// surface's own generation, so a failure from a surface that has since
    /// been replaced cannot condemn its successor.
    var onPreparationFailure: (@MainActor (UInt64, String) -> Void)? { get set }
    /// Puts the surface on the desktop. Separate from construction so the
    /// caller decides when a surface becomes visible.
    func present()
    func stop()
}

/// One desktop window playing a plain local video with the platform player.
///
/// The window is a sibling of the renderer's Metal window and the web
/// wallpaper window, and is discovered by the same class-name lookup, so the
/// presentation policy and the desktop poster sync see it without special
/// cases.
@objc(MWENativeVideoDesktopWindow)
final class NativeVideoWallpaperWindow: NSWindow {
    let player: NativeVideoPlayer
    private var scalingMode: BridgeScalingMode = .fill

    init(frame: NSRect, player: NativeVideoPlayer) {
        self.player = player
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        isMovable = false
        isRestorable = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        // Hiding the app hides the panel, never the desktop it decorates.
        canHide = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .black
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.autoresizesSubviews = true
        contentView = container
        player.attach(to: container)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension NativeVideoWallpaperWindow: NativeVideoSurface {
    var posterLayer: CALayer? { contentView?.layer }
    func setScreenFrame(_ frame: NSRect) {
        if self.frame != frame { setFrame(frame, display: false) }
    }
    func setVolume(_ volume: Float, muted: Bool) { player.setVolume(volume, muted: muted) }
    func setScaling(_ mode: BridgeScalingMode) {
        scalingMode = mode
        player.setScaling(mode)
    }
    func setUserPaused(_ paused: Bool) { player.setUserPaused(paused) }
    func setPresentationSuspended(_ suspended: Bool) {
        player.setPresentationSuspended(suspended)
    }
    var isPlaying: Bool { player.isPlaying }
    var isReadyForDisplay: Bool { player.isReadyForDisplay }
    var onReadyForDisplay: (@MainActor () -> Void)? {
        get { player.onReadyForDisplay }
        set { player.onReadyForDisplay = newValue }
    }
    func posterImage() async -> CGImage? {
        guard let image = await player.posterImage() else { return nil }
        return Self.fittedPoster(image, pixelSize: CGSize(
            width: frame.width * backingScaleFactor, height: frame.height * backingScaleFactor),
            stretching: scalingMode == .stretch)
    }

    /// The desktop picture API stretches the supplied poster. Bake the same crop as
    /// AVPlayerLayer into it first, so other Spaces do not stretch an uncropped clip.
    static func fittedPoster(_ image: CGImage, pixelSize: CGSize, stretching: Bool) -> CGImage? {
        guard pixelSize.width.isFinite, pixelSize.height.isFinite,
              pixelSize.width > 0, pixelSize.height > 0,
              pixelSize.width <= 16_384, pixelSize.height <= 16_384 else { return nil }
        let width = Int(pixelSize.width.rounded(.up)), height = Int(pixelSize.height.rounded(.up))
        guard width * height <= 32 * 1024 * 1024,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let size = CGSize(width: width, height: height)
        let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let drawn = stretching ? size : CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(image, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
        return context.makeImage()
    }
    /// Forwarded straight to the player, which is what observes
    /// `AVPlayerItem.status` and knows its own surface generation.
    var onPreparationFailure: (@MainActor (UInt64, String) -> Void)? {
        get { player.onPreparationFailure }
        set { player.onPreparationFailure = newValue }
    }
    func present() { orderFrontRegardless() }
    func stop() {
        player.stop()
        orderOut(nil)
        close()
    }
}
