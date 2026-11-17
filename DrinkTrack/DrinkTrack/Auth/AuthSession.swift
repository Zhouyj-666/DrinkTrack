import Foundation
import CoreData
import Combine

/// Session restored from the Keychain and verified against the server.
/// The app stays usable when this is logged out; there is no launch gate.
@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    enum Phase: Equatable {
        case loggedOut
        case restoring
        case signedIn
        /// Token and cached profile are present, but /me could not be reached.
        case signedInOffline
    }

    @Published private(set) var phase: Phase = .loggedOut
    @Published private(set) var user: AuthUser?

    var isLoggedIn: Bool { user != nil }
    var accountID: String? { user?.id }

    private let client: AuthAPIClientProtocol
    private let tokenStore: TokenStore
    private let userStore: CachedUserStore
    private let contextProvider: () -> NSManagedObjectContext?

    init(
        client: AuthAPIClientProtocol = AuthAPIClient(),
        tokenStore: TokenStore = KeychainTokenStore.shared,
        userStore: CachedUserStore = KeychainTokenStore.shared,
        contextProvider: @escaping () -> NSManagedObjectContext? = { PersistenceController.shared.viewContext }
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.userStore = userStore
        self.contextProvider = contextProvider
        if let cached = userStore.loadUser(), tokenStore.loadToken() != nil {
            self.user = cached
            CurrentAccountContext.accountID = cached.id
            self.phase = .signedInOffline
        }
    }

    /// Check a stored token on launch. A 401 clears it; a network failure keeps the cached user.
    func restoreSession() async {
        guard let token = tokenStore.loadToken() else {
            clearLocalSession(keepCachedUser: false)
            return
        }
        phase = .restoring
        do {
            let fresh = try await client.currentUser(token: token)
            try? userStore.saveUser(fresh)
            applyAuthenticated(user: fresh)
            phase = .signedIn
        } catch let error as AuthAPIError where error == .unauthenticated {
            clearLocalSession(keepCachedUser: false)
        } catch {
            if let cached = userStore.loadUser() {
                applyAuthenticated(user: cached)
                phase = .signedInOffline
            } else {
                // Token exists but we have no profile and no network. Stay logged out in the UI,
                // keep the token so a later retry can recover without asking for the password again.
                phase = .loggedOut
                user = nil
                CurrentAccountContext.accountID = nil
            }
        }
    }

    func register(email: String, password: String, displayName: String?) async throws {
        let response = try await client.register(email: email, password: password, displayName: displayName)
        try accept(response)
    }

    func login(email: String, password: String) async throws {
        let response = try await client.login(email: email, password: password)
        try accept(response)
    }

    /// Always clears the local token so new records stop being attached to this account.
    /// On-device drink history is not deleted. A server revoke is best-effort.
    func logout() async {
        let token = tokenStore.loadToken()
        if let token {
            try? await client.logout(token: token)
        }
        clearLocalSession(keepCachedUser: false)
    }

    private func accept(_ response: AuthSessionResponse) throws {
        try tokenStore.saveToken(response.token)
        try userStore.saveUser(response.user)
        applyAuthenticated(user: response.user)
        phase = .signedIn
        if let context = contextProvider() {
            try? AccountRecordTagger.attachUnownedRecords(accountID: response.user.id, context: context)
        }
    }

    private func applyAuthenticated(user: AuthUser) {
        self.user = user
        CurrentAccountContext.accountID = user.id
    }

    private func clearLocalSession(keepCachedUser: Bool) {
        try? tokenStore.clearToken()
        if !keepCachedUser {
            try? userStore.clearUser()
        }
        user = keepCachedUser ? userStore.loadUser() : nil
        CurrentAccountContext.accountID = nil
        phase = .loggedOut
    }
}
