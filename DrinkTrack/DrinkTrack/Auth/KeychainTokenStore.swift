import Foundation
import Security

protocol TokenStore: AnyObject {
    func saveToken(_ token: String) throws
    func loadToken() -> String?
    func clearToken() throws
}

protocol CachedUserStore: AnyObject {
    func saveUser(_ user: AuthUser) throws
    func loadUser() -> AuthUser?
    func clearUser() throws
}

/// Session token + cached account profile in the Keychain, never UserDefaults.
/// Uses `AfterFirstUnlockThisDeviceOnly` so the token is not synced to iCloud
/// and is not available before first device unlock.
final class KeychainTokenStore: TokenStore, CachedUserStore {
    static let shared = KeychainTokenStore()

    private let service: String
    private let tokenAccount = "sessionToken"
    private let userAccount = "cachedUser"

    init(service: String = "com.drinktrack.app.auth") {
        self.service = service
    }

    func saveToken(_ token: String) throws {
        try saveData(Data(token.utf8), account: tokenAccount)
    }

    func loadToken() -> String? {
        guard let data = loadData(account: tokenAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clearToken() throws {
        try delete(account: tokenAccount)
    }

    func saveUser(_ user: AuthUser) throws {
        let data = try AuthJSON.encoder.encode(user)
        try saveData(data, account: userAccount)
    }

    func loadUser() -> AuthUser? {
        guard let data = loadData(account: userAccount) else { return nil }
        return try? AuthJSON.decoder.decode(AuthUser.self, from: data)
    }

    func clearUser() throws {
        try delete(account: userAccount)
    }

    /// Clears both the token and the cached profile.
    func clearAll() throws {
        try clearToken()
        try clearUser()
    }

    // MARK: - Keychain primitives

    private func saveData(_ data: Data, account: String) throws {
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandled(status)
        }
    }

    private func loadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unhandled(status)
        }
    }
}

enum KeychainStoreError: Error {
    case unhandled(OSStatus)
}

/// In-memory stores for unit tests. Never used in the running app.
final class InMemoryTokenStore: TokenStore {
    var token: String?

    func saveToken(_ token: String) throws { self.token = token }
    func loadToken() -> String? { token }
    func clearToken() throws { token = nil }
}

final class InMemoryCachedUserStore: CachedUserStore {
    var user: AuthUser?

    func saveUser(_ user: AuthUser) throws { self.user = user }
    func loadUser() -> AuthUser? { user }
    func clearUser() throws { user = nil }
}
