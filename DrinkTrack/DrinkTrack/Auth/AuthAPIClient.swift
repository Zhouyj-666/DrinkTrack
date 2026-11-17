import Foundation

protocol AuthAPIClientProtocol: Sendable {
    func register(email: String, password: String, displayName: String?) async throws -> AuthSessionResponse
    func login(email: String, password: String) async throws -> AuthSessionResponse
    func logout(token: String) async throws
    func currentUser(token: String) async throws -> AuthUser
}

/// Talks to the in-repo FastAPI service. The base URL is read from AuthAPIConfiguration
/// at request time so the user can change the LAN address without restarting.
struct AuthAPIClient: AuthAPIClientProtocol {
    var session: URLSession
    var baseURLProvider: @Sendable () -> URL?

    init(
        session: URLSession = .shared,
        baseURLProvider: @escaping @Sendable () -> URL? = { AuthAPIConfiguration.baseURL }
    ) {
        self.session = session
        self.baseURLProvider = baseURLProvider
    }

    func register(email: String, password: String, displayName: String?) async throws -> AuthSessionResponse {
        var body: [String: String] = [
            "email": email,
            "password": password
        ]
        if let displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { body["display_name"] = trimmed }
        }
        return try await post(
            "v1/auth/register",
            body: body,
            token: nil,
            decode: AuthSessionResponse.self,
            timeout: AuthRequestTimeout.interactive
        )
    }

    func login(email: String, password: String) async throws -> AuthSessionResponse {
        try await post(
            "v1/auth/login",
            body: ["email": email, "password": password],
            token: nil,
            decode: AuthSessionResponse.self,
            timeout: AuthRequestTimeout.interactive
        )
    }

    func logout(token: String) async throws {
        _ = try await send(
            path: "v1/auth/logout",
            method: "POST",
            body: nil,
            token: token,
            timeout: AuthRequestTimeout.interactive
        )
    }

    func currentUser(token: String) async throws -> AuthUser {
        let data = try await send(
            path: "v1/auth/me",
            method: "GET",
            body: nil,
            token: token,
            timeout: AuthRequestTimeout.sessionRestore
        )
        return try decode(AuthUser.self, from: data)
    }

    private func post<T: Decodable>(
        _ path: String,
        body: [String: String],
        token: String?,
        decode type: T.Type,
        timeout: TimeInterval
    ) async throws -> T {
        let data = try await send(path: path, method: "POST", body: body, token: token, timeout: timeout)
        return try self.decode(type, from: data)
    }

    private func makeURL(path: String) throws -> URL {
        guard let root = baseURLProvider() else { throw AuthAPIError.invalidBaseURL }
        let raw = root.absoluteString
        let slashed = raw.hasSuffix("/") ? raw : raw + "/"
        guard let base = URL(string: slashed),
              let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw AuthAPIError.invalidBaseURL
        }
        return url
    }

    private func send(
        path: String,
        method: String,
        body: [String: String]?,
        token: String?,
        timeout: TimeInterval
    ) async throws -> Data {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthAPIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw AuthAPIError.unexpected }
        if (200...299).contains(http.statusCode) { return data }
        let payload = try? AuthJSON.decoder.decode(AuthAPIErrorPayload.self, from: data)
        throw AuthAPIError.from(statusCode: http.statusCode, payload: payload)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try AuthJSON.decoder.decode(type, from: data)
        } catch {
            throw AuthAPIError.unexpected
        }
    }
}
