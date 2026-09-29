import AppKit
import WebKit

/// pixiv's own sign-in page in a window of its own. The page runs in a private website data
/// store that disappears with the window, and the app reads exactly one thing from it: the
/// `PHPSESSID` cookie pixiv sets on `.pixiv.net` once someone has signed in. The password,
/// and anything else typed into the page, stays between the page and pixiv.
@MainActor
final class PixivSignInWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
    WKHTTPCookieStoreObserver
{
    static let signInURL = URL(
        string: "https://accounts.pixiv.net/login?return_to=https%3A%2F%2Fwww.pixiv.net%2F&source=pc&view_type=page")!
    private static var current: PixivSignInWindowController?

    private let webView: WKWebView
    private var continuation: CheckedContinuation<String?, Never>?

    /// Opens the window and answers the session pixiv set, or nil once the window closes
    /// without one. While a window is open, another call only brings it forward and answers
    /// nil at once, so a caller must not start a second sign-in; `PixivStore.signIn` never does.
    static func obtainSession() async -> String? {
        if let current {
            current.showWindow(nil)
            return nil
        }
        let controller = PixivSignInWindowController()
        current = controller
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                controller.continuation = continuation
                controller.showWindow(nil)
                controller.webView.load(URLRequest(url: signInURL))
            }
        } onCancel: {
            Task { @MainActor in controller.finish(nil) }
        }
    }

    /// Brings an open sign-in window forward; does nothing when none is open.
    static func bringToFront() { current?.showWindow(nil) }

    private init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let size = NSSize(width: 480, height: 720)
        webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = String(localized: "Sign in to pixiv")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 380, height: 520)
        window.contentView = webView
        window.center()
        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        configuration.websiteDataStore.httpCookieStore.add(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Answers the waiting caller once, then closes the window and lets the page's data go.
    private func finish(_ session: String?) {
        guard let continuation else { return }
        self.continuation = nil
        if Self.current === self { Self.current = nil }
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        webView.stopLoading()
        window?.delegate = nil
        close()
        continuation.resume(returning: session)
    }

    private func lookForSession() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard continuation != nil,
            let session = cookies.first(where: {
                $0.name == "PHPSESSID" && ["pixiv.net", ".pixiv.net", "www.pixiv.net"].contains($0.domain)
                    && PixivService.isSessionValue($0.value)
            })?.value
        else { return }
        finish(session)
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in await self.lookForSession() }
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    // Anything but HTTPS (an app link, a mail address) goes nowhere; the window is for signing in.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        return scheme == "https" || scheme == "about" ? .allow : .cancel
    }

    // A page that opens a window of its own continues in this one instead.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.request.url?.scheme?.lowercased() == "https" { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window?.subtitle = ""
        Task { await lookForSession() }
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        showFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showFailure(error)
    }

    /// A load the page itself replaced, or one refused above, is not a failure worth showing.
    private func showFailure(_ error: Error) {
        let error = error as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain", error.code == 102 { return }
        window?.subtitle = error.localizedDescription
    }
}
