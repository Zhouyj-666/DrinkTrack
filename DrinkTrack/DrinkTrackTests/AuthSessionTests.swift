import XCTest
import CoreData
@testable import DrinkTrack

@MainActor
final class AuthSessionTests: XCTestCase {
    private var persistence: PersistenceController!
    private var tokenStore: InMemoryTokenStore!
    private var userStore: InMemoryCachedUserStore!
    private var client: MockAuthAPIClient!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        tokenStore = InMemoryTokenStore()
        userStore = InMemoryCachedUserStore()
        client = MockAuthAPIClient()
        CurrentAccountContext.accountID = nil
    }

    override func tearDown() {
        CurrentAccountContext.accountID = nil
        super.tearDown()
    }

    func testLoginPersistsTokenTagsRecordsAndLogoutKeepsHistory() async throws {
        let context = persistence.viewContext
        let session = DrinkSessionEntity(context: context)
        session.id = UUID()
        session.startedAt = Date()
        session.status = "archived"
        try context.save()

        let user = AuthUser(id: "acct-1", email: "you@example.com", displayName: "小酌")
        client.loginHandler = { email, password in
            XCTAssertEqual(email, "you@example.com")
            XCTAssertEqual(password, "secret-123")
            return AuthSessionResponse(token: "tok-live", tokenType: "bearer", user: user)
        }

        let auth = makeSession()
        try await auth.login(email: "you@example.com", password: "secret-123")

        XCTAssertEqual(tokenStore.token, "tok-live")
        XCTAssertEqual(userStore.user?.id, "acct-1")
        XCTAssertEqual(auth.phase, .signedIn)
        XCTAssertEqual(CurrentAccountContext.accountID, "acct-1")
        XCTAssertEqual(session.value(forKey: "accountId") as? String, "acct-1")

        client.logoutHandler = { token in
            XCTAssertEqual(token, "tok-live")
        }
        await auth.logout()

        XCTAssertNil(tokenStore.token)
        XCTAssertNil(userStore.user)
        XCTAssertEqual(auth.phase, .loggedOut)
        XCTAssertNil(CurrentAccountContext.accountID)
        // History stays on the device, still tagged for a later sync hook.
        let request = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        let remaining = try context.fetch(request)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.value(forKey: "accountId") as? String, "acct-1")
    }

    func testRestoreClearsTokenOnUnauthorized() async {
        tokenStore.token = "stale"
        userStore.user = AuthUser(id: "acct-1", email: "you@example.com", displayName: "小酌")
        client.meHandler = { _ in throw AuthAPIError.unauthenticated }

        let auth = makeSession()
        await auth.restoreSession()

        XCTAssertNil(tokenStore.token)
        XCTAssertNil(userStore.user)
        XCTAssertEqual(auth.phase, .loggedOut)
        XCTAssertNil(auth.user)
    }

    func testRestoreKeepsCachedUserWhenServerIsUnreachable() async {
        tokenStore.token = "tok-live"
        userStore.user = AuthUser(id: "acct-1", email: "you@example.com", displayName: "小酌")
        client.meHandler = { _ in throw AuthAPIError.unreachable }

        let auth = makeSession()
        await auth.restoreSession()

        XCTAssertEqual(tokenStore.token, "tok-live")
        XCTAssertEqual(auth.phase, .signedInOffline)
        XCTAssertEqual(auth.user?.email, "you@example.com")
        XCTAssertEqual(CurrentAccountContext.accountID, "acct-1")
    }

    private func makeSession() -> AuthSession {
        AuthSession(
            client: client,
            tokenStore: tokenStore,
            userStore: userStore,
            contextProvider: { [persistence] in persistence?.viewContext }
        )
    }
}

final class MockAuthAPIClient: AuthAPIClientProtocol, @unchecked Sendable {
    var registerHandler: ((String, String, String?) async throws -> AuthSessionResponse)?
    var loginHandler: ((String, String) async throws -> AuthSessionResponse)?
    var logoutHandler: ((String) async throws -> Void)?
    var meHandler: ((String) async throws -> AuthUser)?

    func register(email: String, password: String, displayName: String?) async throws -> AuthSessionResponse {
        try await registerHandler!(email, password, displayName)
    }

    func login(email: String, password: String) async throws -> AuthSessionResponse {
        try await loginHandler!(email, password)
    }

    func logout(token: String) async throws {
        try await logoutHandler?(token)
    }

    func currentUser(token: String) async throws -> AuthUser {
        try await meHandler!(token)
    }
}
