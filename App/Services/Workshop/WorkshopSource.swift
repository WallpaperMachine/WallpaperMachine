import Foundation

/// Where Discover's tiles come from.
enum WorkshopSource: Equatable, Sendable {
    /// The Workshop's wallpapers, searched, filtered and sorted by Steam.
    case browse
    /// The Workshop's collections, searched and sorted by Steam.
    case collections
    /// The wallpapers in one collection, in the collection's own order.
    case collection(id: String, title: String)
    /// One author's wallpapers.
    case creator(id: String, name: String)
    /// The wallpapers the signed-in Steam account subscribes to.
    case subscriptions

    /// Whether Steam searches and sorts it; the others are shown in their own order.
    var isSearchable: Bool {
        switch self {
        case .browse, .collections: true
        default: false
        }
    }

    /// The name the panel knows it by.
    var key: String {
        switch self {
        case .browse: "browse"
        case .collections: "collections"
        case .collection: "collection"
        case .creator: "creator"
        case .subscriptions: "subscriptions"
        }
    }

    /// The collection's or author's Workshop id; nil for the lists.
    var id: String? {
        switch self {
        case .collection(let id, _), .creator(let id, _): id
        default: nil
        }
    }

    /// The collection's title or the author's name, as it was when opened.
    var name: String? {
        switch self {
        case .collection(_, let title): title
        case .creator(_, let name): name
        default: nil
        }
    }
}

/// A signed-in Steam Community session, taken from Steam's own sign-in page. Kept in memory for
/// this run of the app only, never written anywhere, and sent to steamcommunity.com alone, to
/// read the list of the account's subscriptions.
struct SteamWebSession: Equatable, Sendable {
    /// The account's SteamID64, which the cookie starts with.
    let steamID: String
    /// The `steamLoginSecure` cookie's value, exactly as Steam set it.
    let cookie: String

    /// Reads a `steamLoginSecure` value, `<SteamID64>||<token>` with the bars percent-encoded or
    /// not; anything else is not a session.
    init?(cookie value: String) {
        let decoded = value.replacingOccurrences(of: "%7C", with: "|", options: .caseInsensitive)
        let parts = decoded.components(separatedBy: "||")
        guard parts.count == 2, let id = parts.first, Self.isSteamID(id),
              let token = parts.last, token.count >= 16, value.count <= 4096,
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
        else { return nil }
        steamID = id
        cookie = value
    }

    /// Whether `id` has the form of a SteamID64: 17 ASCII digits.
    static func isSteamID(_ id: String) -> Bool {
        id.count == 17 && id.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// Steam answered with its sign-in page: the session ended or was never there.
struct SteamSignInRequired: LocalizedError {
    var errorDescription: String? {
        String(localized: "Steam asked you to sign in again. Sign in to Steam to see your subscriptions.")
    }
}
