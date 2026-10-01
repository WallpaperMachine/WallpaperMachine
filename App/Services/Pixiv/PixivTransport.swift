import Foundation

/// The network seam for pixiv: JSON from `www.pixiv.net` and images from `i.pximg.net`, which
/// answers 403 to any request that does not name pixiv as its referrer. Injected so tests never
/// reach the network.
protocol PixivTransport: Sendable {
    /// The body of a 2xx answer; any other status throws `PixivFailure.Code.status`. `session`
    /// is the signed-in account's `PHPSESSID`, or nil to ask anonymously.
    func data(from url: URL, session: String?) async throws -> Data

    /// An image of at most `limit` bytes, reporting bytes received so far and the size the
    /// server announced, when it announced one.
    func image(
        from url: URL, limit: Int, progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> Data
}

struct URLSessionPixivTransport: PixivTransport {
    static let referer = "https://www.pixiv.net/"

    // Ephemeral and cookie-free: nothing pixiv sets is kept, and the one cookie that is sent, the
    // account's session, is added by hand to the requests that may carry it and taken off any
    // redirect that leaves pixiv's site.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }()

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "WallpaperMachine/\(version ?? "1.0") (macOS; pixiv browser)"
    }()

    static func request(_ url: URL, accept: String, session: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let session, PixivService.isSessionValue(session), mayCarrySession(url) {
            request.setValue("PHPSESSID=\(session)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    /// The session signs in to pixiv's site only: never to its image host, never elsewhere.
    static func mayCarrySession(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "www.pixiv.net" && url.port == nil && url.user == nil
            && url.password == nil
    }

    /// The request a redirect continues with: the session stays behind unless the new address
    /// is pixiv's site again.
    static func redirected(_ request: URLRequest) -> URLRequest {
        var request = request
        if !mayCarrySession(request.url) { request.setValue(nil, forHTTPHeaderField: "Cookie") }
        return request
    }

    func data(from url: URL, session: String?) async throws -> Data {
        let (data, response) = try await Self.perform {
            try await Self.session.data(for: Self.request(url, accept: "application/json", session: session))
        }
        try Self.check(response)
        return data
    }

    func image(
        from url: URL, limit: Int, progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> Data {
        let request = Self.request(url, accept: "image/avif,image/webp,image/png,image/jpeg,image/gif,*/*;q=0.5")
        let (bytes, response) = try await Self.perform { try await Self.session.bytes(for: request) }
        try Self.check(response)
        let expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        let megabytes = limit / (1024 * 1024)
        if let expected, expected > Int64(limit) { throw PixivFailure(code: .tooLarge(megabytes: megabytes)) }
        var data = Data()
        data.reserveCapacity(Int(min(expected ?? 0, Int64(limit))))
        progress(0, expected)
        try await Self.perform {
            for try await byte in bytes {
                data.append(byte)
                guard data.count.isMultiple(of: 65_536) else { continue }
                try Task.checkCancellation()
                guard data.count <= limit else { throw PixivFailure(code: .tooLarge(megabytes: megabytes)) }
                progress(Int64(data.count), expected)
            }
        }
        try Task.checkCancellation()
        guard data.count <= limit else { throw PixivFailure(code: .tooLarge(megabytes: megabytes)) }
        progress(Int64(data.count), expected)
        return data
    }

    /// A transport failure becomes a `PixivFailure`; cancellation stays a cancellation.
    private static func perform<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw PixivFailure(code: .network(error.localizedDescription))
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw PixivFailure(code: .unreadable) }
        guard (200..<300).contains(http.statusCode) else {
            // Do not log URLs, headers or bodies: they can reveal searches or the session cookie.
            AppLog.warn("pixiv request failed: HTTP \(http.statusCode)")
            throw PixivFailure(code: .status(http.statusCode))
        }
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(URLSessionPixivTransport.redirected(request))
    }
}

/// Feeds pixiv thumbnails to a `WorkshopThumbnailCache`, which keeps them on disk exactly as it
/// keeps Workshop previews; only the fetch differs, since `i.pximg.net` needs the referrer.
struct PixivThumbnailFetcher: WorkshopThumbnailFetching {
    /// pixiv's own renditions stay well under this; anything larger is not a thumbnail.
    static let byteLimit = 8 * 1024 * 1024
    private let transport: any PixivTransport

    init(transport: any PixivTransport = URLSessionPixivTransport()) { self.transport = transport }

    func fetch(_ url: URL) async throws -> Data {
        guard PixivService.isImageURL(url) else { throw PixivFailure(code: .unreadable) }
        return try await transport.image(from: url, limit: Self.byteLimit) { _, _ in }
    }
}
