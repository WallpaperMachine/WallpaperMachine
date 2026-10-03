import Foundation

/// Reads pixiv's web endpoints: the illustration rankings, tag search, a work's page list and
/// who is signed in. A request carries the session of the account the user signed in to on
/// pixiv's own page when the caller passes one, and is anonymous otherwise; nothing here ever
/// sees a password.
///
/// pixiv's JSON is loose about types (counts arrive as numbers or strings, a content-type field
/// as an object or an empty list), so it is read field by field rather than decoded into
/// strict types, and a malformed entry is dropped instead of failing its whole page.
actor PixivService {
    static let rankingPageSize = 50
    static let searchPageSize = 60
    /// Signed-in members can page deeper; anonymous search stops at page 10 and rankings at 10.
    static let maxPages = 1000
    /// The largest original accepted; pixiv caps uploads well below this.
    static let originalByteLimit = 64 * 1024 * 1024
    private static let host = "www.pixiv.net"

    private let transport: any PixivTransport
    private let minimumInterval: Duration
    private let clock = ContinuousClock()
    private var nextRequest: ContinuousClock.Instant?

    /// `minimumInterval` spaces out the JSON requests this app sends, so paging quickly through
    /// a ranking never looks like a scraper to pixiv. Images are not paced.
    init(transport: any PixivTransport = URLSessionPixivTransport(), minimumInterval: Duration = .milliseconds(350)) {
        self.transport = transport
        self.minimumInterval = minimumInterval
    }

    /// The account `session` signs in to; nil when pixiv says it signs no one in.
    func account(session: String) async throws -> PixivAccount? {
        guard Self.isSessionValue(session) else { return nil }
        let status = try Self.decodeStatus(try await json(Self.statusURL, session: session))
        guard status.signedIn else { return nil }
        guard let id = status.id ?? Self.userID(fromSession: session) else { throw PixivFailure(code: .unreadable) }
        var name = status.name
        if name?.isEmpty ?? true {
            name = try? Self.decodeUserName(try await json(Self.userURL(id: id), session: session))
        }
        return PixivAccount(id: id, name: name ?? id, showsR18: status.viewingRestriction.map { $0 >= 1 })
    }

    func page(_ number: Int, of listing: PixivListing, session: String? = nil) async throws -> PixivResultPage {
        let page = max(1, number)
        switch listing {
        case .ranking(let ranking):
            do {
                return try Self.decodeRanking(
                    try await json(Self.rankingURL(ranking, page: page), session: session), requestedPage: page,
                    r18: ranking.isR18)
            } catch let failure as PixivFailure where failure.code == .status(403) && ranking.isR18 {
                // pixiv refuses its R-18 rankings to a visitor it does not know to be an adult.
                throw PixivFailure(code: session == nil ? .signedOut : .r18Hidden)
            }
        case .search:
            guard let url = Self.searchURL(listing, page: page) else { throw PixivFailure(code: .unreadable) }
            return try Self.decodeSearch(try await json(url, session: session), requestedPage: page)
        }
    }

    func pages(ofWork id: String, session: String? = nil) async throws -> [PixivPage] {
        guard PixivWork.isValidID(id) else { throw PixivFailure(code: .unreadable) }
        return try Self.decodePages(try await json(Self.pagesURL(workID: id), session: session))
    }

    /// The original of `page`, streamed with progress.
    func original(
        of page: PixivPage, checkpoint: URL? = nil,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> Data {
        guard Self.isImageURL(page.originalURL) else { throw PixivFailure(code: .unreadable) }
        if let checkpoint {
            return try await transport.image(from: page.originalURL, limit: Self.originalByteLimit,
                                             checkpoint: checkpoint, progress: progress)
        }
        return try await transport.image(from: page.originalURL, limit: Self.originalByteLimit, progress: progress)
    }

    private func json(_ url: URL, session: String?) async throws -> Data {
        let now = clock.now
        let slot = max(now, nextRequest ?? now)
        nextRequest = slot + minimumInterval
        if slot > now { try await clock.sleep(until: slot) }
        try Task.checkCancellation()
        return try await transport.data(from: url, session: session)
    }

    // MARK: - Addresses

    static func rankingURL(_ ranking: PixivRanking, page: Int) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/ranking.php"
        components.queryItems = [
            URLQueryItem(name: "mode", value: ranking.rawValue),
            URLQueryItem(name: "content", value: "illust"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "p", value: String(max(1, page))),
        ]
        return components.url!
    }

    /// pixiv's own tag search for illustrations, of the ages `mode` asks for. Orientation and
    /// minimum size go to pixiv as its `ratio` / `wlt` / `hlt` filters; with no orientation both
    /// sides must reach the short side and `PixivQuery.admits` checks the long one.
    static func searchURL(_ listing: PixivListing, page: Int) -> URL? {
        guard case .search(let text, let order, let orientation, let minimumSize, let hidesAI, let mode) = listing,
            !text.isEmpty, text.count <= 256
        else { return nil }
        // A tag may contain "/", "+", "?" or "#", so the path segment is encoded by hand.
        var segment = CharacterSet.urlPathAllowed
        segment.remove(charactersIn: "/;+")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: segment) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.percentEncodedPath = "/ajax/search/illustrations/" + encoded
        var items = [
            URLQueryItem(name: "word", value: text),
            URLQueryItem(name: "order", value: order.rawValue),
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "p", value: String(max(1, page))),
            URLQueryItem(name: "s_mode", value: "s_tag"),
            URLQueryItem(name: "type", value: "illust"),
        ]
        switch orientation {
        case .any: break
        case .landscape: items.append(URLQueryItem(name: "ratio", value: "0.5"))
        case .portrait: items.append(URLQueryItem(name: "ratio", value: "-0.5"))
        }
        if let sides = minimumSize.sides {
            let (width, height) =
                switch orientation {
                case .any: (sides.short, sides.short)
                case .landscape: (sides.long, sides.short)
                case .portrait: (sides.short, sides.long)
                }
            items.append(URLQueryItem(name: "wlt", value: String(width)))
            items.append(URLQueryItem(name: "hlt", value: String(height)))
        }
        if hidesAI { items.append(URLQueryItem(name: "ai_type", value: "1")) }
        components.queryItems = items
        // URLComponents leaves "+" alone in queries, where pixiv would read it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    static func pagesURL(workID: String) -> URL {
        URL(string: "https://\(host)/ajax/illust/\(workID)/pages")!
    }

    /// Whether anyone is signed in, and who: the status pixiv's mobile site reads.
    static let statusURL = URL(string: "https://www.pixiv.net/touch/ajax/user/self/status")!

    static func userURL(id: String) -> URL {
        URL(string: "https://\(host)/ajax/user/\(id)?full=0")!
    }

    /// A signed-in `PHPSESSID`: the account id, an underscore and a random token. Anything else
    /// is refused before it could reach a request header.
    static func isSessionValue(_ value: String) -> Bool {
        let parts = value.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2, PixivWork.isValidID(String(parts[0])), (10...128).contains(parts[1].utf8.count)
        else { return false }
        return parts[1].utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) }
    }

    static func userID(fromSession value: String) -> String? {
        isSessionValue(value) ? value.split(separator: "_").first.map(String.init) : nil
    }

    /// Images are only ever fetched from pixiv's image host, over HTTPS.
    static func isImageURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "i.pximg.net" && url.user == nil && url.password == nil
            && url.port == nil
    }

    // MARK: - Decoding

    /// Who a status answer says is signed in. pixiv sends the flags and numbers either as JSON
    /// values or as strings; `user_x_restrict` is the account's viewing restriction (0 all
    /// ages, 1 R-18, 2 R-18G too) and may be absent.
    static func decodeStatus(_ data: Data) throws -> (signedIn: Bool, id: String?, name: String?, viewingRestriction: Int?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["error"] as? Bool != true, let body = root["body"] as? [String: Any],
            let status = body["user_status"] as? [String: Any]
        else { throw PixivFailure(code: .unreadable) }
        let signedIn = (status["is_logged_in"] as? Bool) ?? (integer(status["is_logged_in"]) == 1)
        let id = (status["user_id"] as? String) ?? integer(status["user_id"]).map(String.init)
        return (
            signedIn, id.flatMap { PixivWork.isValidID($0) ? $0 : nil }, status["user_name"] as? String,
            integer(status["user_x_restrict"])
        )
    }

    static func decodeUserName(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["error"] as? Bool != true, let body = root["body"] as? [String: Any],
            let name = body["name"] as? String, !name.isEmpty
        else { throw PixivFailure(code: .unreadable) }
        return name
    }

    /// Every entry of an R-18 ranking is rated Mature, whatever its content flags say.
    static func decodeRanking(_ data: Data, requestedPage: Int, r18: Bool = false) throws -> PixivResultPage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["contents"] as? [[String: Any]]
        else { throw PixivFailure(code: .unreadable) }
        let page = integer(root["page"]) ?? requestedPage
        let total = max(integer(root["rank_total"]) ?? 0, rows.count)
        var totalPages = max(page, (total + rankingPageSize - 1) / rankingPageSize)
        // `next` is the following page's number, or false on the last page.
        if let next = integer(root["next"]), next > page { totalPages = max(totalPages, next) }
        return PixivResultPage(
            works: unique(rows.compactMap { rankingWork($0, r18: r18) }), page: page,
            totalPages: min(maxPages, totalPages), totalCount: total)
    }

    static func decodeSearch(_ data: Data, requestedPage: Int) throws -> PixivResultPage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["error"] as? Bool != true, let body = root["body"] as? [String: Any],
            let block = (body["illust"] ?? body["illustManga"]) as? [String: Any],
            let rows = block["data"] as? [[String: Any]]
        else { throw PixivFailure(code: .unreadable) }
        let total = max(0, integer(block["total"]) ?? rows.count)
        let lastPage = integer(block["lastPage"]) ?? requestedPage
        return PixivResultPage(
            works: unique(rows.compactMap(searchWork)), page: requestedPage,
            totalPages: min(maxPages, max(1, lastPage)), totalCount: total)
    }

    static func decodePages(_ data: Data) throws -> [PixivPage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["error"] as? Bool != true, let rows = root["body"] as? [[String: Any]]
        else { throw PixivFailure(code: .unreadable) }
        // Members-only works answer with every address set to null.
        let pages = rows.enumerated().compactMap { index, row -> PixivPage? in
            guard let urls = row["urls"] as? [String: Any],
                let original = imageURL(urls["original"]),
                let width = integer(row["width"]), let height = integer(row["height"]),
                width > 0, height > 0
            else { return nil }
            return PixivPage(
                index: index, width: width, height: height,
                previewURL: imageURL(urls["small"]) ?? imageURL(urls["regular"]), originalURL: original)
        }
        guard pages.count == rows.count, !pages.isEmpty else {
            throw PixivFailure(code: rows.isEmpty ? .unreadable : .membersOnly)
        }
        return pages
    }

    /// A ranking entry. A slot pixiv withholds from anonymous visitors (`mask_reason`) carries
    /// a placeholder image and no title, and anything but a still illustration is skipped.
    /// `is_masked` only means pixiv's site blurs the thumbnail as sensitive; the work is real.
    private static func rankingWork(_ row: [String: Any], r18: Bool) -> PixivWork? {
        guard (row["mask_reason"] as? String)?.isEmpty ?? true, integer(row["illust_type"]) == 0,
            let id = integer(row["illust_id"]).map(String.init), PixivWork.isValidID(id),
            let thumbnail = imageURL(row["url"]),
            let width = integer(row["width"]), let height = integer(row["height"]), width > 0, height > 0
        else { return nil }
        // An object in most entries, a list in a few, and an empty list when pixiv has no rating.
        let contentType =
            row["illust_content_type"] as? [String: Any]
            ?? (row["illust_content_type"] as? [[String: Any]])?.first
        return PixivWork(
            id: id, title: row["title"] as? String ?? "",
            authorID: integer(row["user_id"]).map(String.init) ?? "",
            authorName: row["user_name"] as? String ?? "", thumbnailURL: thumbnail,
            width: width, height: height, pageCount: max(1, integer(row["illust_page_count"]) ?? 1),
            rating: PixivRating(
                xRestrict: r18 ? (contentType?["grotesque"] as? Bool == true ? 2 : 1) : 0, sanityLevel: nil,
                sexual: integer(contentType?["sexual"]), sensitive: row["is_masked"] as? Bool == true),
            aiGenerated: nil, tags: strings(row["tags"]), rank: integer(row["rank"]))
    }

    private static func searchWork(_ row: [String: Any]) -> PixivWork? {
        guard integer(row["illustType"]) == 0,
            let id = (row["id"] as? String) ?? integer(row["id"]).map(String.init), PixivWork.isValidID(id),
            let thumbnail = imageURL(row["url"]),
            let width = integer(row["width"]), let height = integer(row["height"]), width > 0, height > 0
        else { return nil }
        return PixivWork(
            id: id, title: row["title"] as? String ?? "",
            authorID: (row["userId"] as? String) ?? integer(row["userId"]).map(String.init) ?? "",
            authorName: row["userName"] as? String ?? "", thumbnailURL: thumbnail,
            width: width, height: height, pageCount: max(1, integer(row["pageCount"]) ?? 1),
            rating: PixivRating(
                xRestrict: integer(row["xRestrict"]) ?? 0, sanityLevel: integer(row["sl"]), sexual: nil,
                sensitive: row["isMasked"] as? Bool == true),
            aiGenerated: integer(row["aiType"]).map { $0 == 2 }, tags: strings(row["tags"]), rank: nil)
    }

    /// pixiv repeats an entry when a work moves between two requests for neighbouring pages.
    private static func unique(_ works: [PixivWork]) -> [PixivWork] {
        var seen = Set<String>()
        return works.filter { seen.insert($0.id).inserted }
    }

    /// A whole number pixiv sent either as a JSON number or as a decimal string. JSON booleans
    /// read as 0 and 1, which is harmless: the one boolean among these fields is `next`, and
    /// its `false` means there is no next page.
    static func integer(_ value: Any?) -> Int? {
        switch value {
        case let text as String:
            return Int(text)
        case let number as NSNumber:
            let double = number.doubleValue
            guard double.isFinite, double == double.rounded(), abs(double) < 1e15 else { return nil }
            return Int(double)
        default:
            return nil
        }
    }

    private static func strings(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
    }

    private static func imageURL(_ value: Any?) -> URL? {
        guard let text = value as? String, let url = URL(string: text), isImageURL(url) else { return nil }
        return url
    }
}
