import Foundation
import Security

/// Keeps the pixiv session between launches. Injected so tests never touch the keychain.
protocol PixivSessionStoring: Sendable {
    /// The saved session; nil when there is none or it cannot be read.
    func load() -> String?
    func save(_ session: String) throws
    func remove()
}

/// The session as a generic password in the user's login keychain. Releases share one
/// designated requirement, so an update reads what the version before it saved; a locally
/// built, ad-hoc signed app is a different app to the keychain, and macOS asks once whether
/// it may read the item.
struct KeychainPixivSessionStore: PixivSessionStoring {
    static let service = "app.wallpapermachine.pixiv"
    static let account = "session"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound { AppLog.warn("pixiv sign-in could not be read from the keychain (\(status))") }
            return nil
        }
        guard let data = item as? Data, let session = String(data: data, encoding: .utf8),
            PixivService.isSessionValue(session)
        else { return nil }
        return session
    }

    func save(_ session: String) throws {
        let data = Data(session.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecSuccess {
            // Missing, or saved by a build this one may not change: start over.
            if status != errSecItemNotFound { SecItemDelete(query as CFDictionary) }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "WallpaperMachine pixiv sign-in"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            AppLog.warn("pixiv sign-in could not be saved in the keychain (\(status))")
            throw PixivFailure(code: .notSaved)
        }
    }

    func remove() {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            AppLog.warn("pixiv sign-in could not be removed from the keychain (\(status))")
        }
    }
}
