import Darwin
import WebKit

/// WebKit output controls leave media timelines and system-audio analysis running.
@MainActor
enum WebWallpaperAudioOutput {
    struct Capabilities: Equatable, Sendable {
        var mediaVolume = false
        var pageMute = false
    }

    private static let pageReference = NSSelectorFromString("_pageForTesting")
    private static let muteSetter = NSSelectorFromString("_setPageMuted:")
    private static let muteGetter = NSSelectorFromString("_mediaMutedState")
    private static let audioMutedBit: UInt = 1
    private typealias PageReference = @convention(c) (AnyObject, Selector) -> UnsafeRawPointer?
    private typealias SetMuted = @convention(c) (AnyObject, Selector, UInt) -> Void
    private typealias GetMuted = @convention(c) (AnyObject, Selector) -> UInt
    private typealias SetMediaVolume = @convention(c) (UnsafeRawPointer, Float) -> Void
    private static let setMediaVolume: SetMediaVolume? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "WKPageSetMediaVolume") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetMediaVolume.self)
    }()

    /// Native media gain covers HTML media elements; WebAudio has only the page mute channel.
    static func apply(volume: Float, muted: Bool, to webView: WKWebView) -> Capabilities {
        var capabilities = Capabilities()
        if volume.isFinite, (0...1).contains(volume),
           let setMediaVolume, webView.responds(to: pageReference),
           let implementation = webView.method(for: pageReference) {
            let reference = unsafeBitCast(implementation, to: PageReference.self)
            if let page = reference(webView, pageReference) {
                setMediaVolume(page, muted ? 0 : volume)
                capabilities.mediaVolume = true
            }
        }
        if webView.responds(to: muteSetter), webView.responds(to: muteGetter),
           let setterImplementation = webView.method(for: muteSetter),
           let getterImplementation = webView.method(for: muteGetter) {
            let get = unsafeBitCast(getterImplementation, to: GetMuted.self)
            let set = unsafeBitCast(setterImplementation, to: SetMuted.self)
            let before = get(webView, muteGetter)
            // Preserve capture-device flags: wallpaper output is not microphone/camera capture.
            let after = muted ? before | audioMutedBit : before & ~audioMutedBit
            if after != before { set(webView, muteSetter, after) }
            capabilities.pageMute = (get(webView, muteGetter) & audioMutedBit != 0) == muted
        }
        return capabilities
    }

    static func isMuted(_ webView: WKWebView) -> Bool? {
        guard webView.responds(to: muteGetter), let implementation = webView.method(for: muteGetter) else {
            return nil
        }
        let get = unsafeBitCast(implementation, to: GetMuted.self)
        return get(webView, muteGetter) & audioMutedBit != 0
    }
}
