import Foundation

/// Public account fields returned by the v1 auth API.
struct AuthUser: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let email: String
    let displayName: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case createdAt = "created_at"
    }

    init(id: String, email: String, displayName: String, createdAt: Date? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid.uuidString.lowercased()
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        createdAt = Self.decodeDate(container)
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>) -> Date? {
        if let date = try? container.decode(Date.self, forKey: .createdAt) {
            return date
        }
        guard let raw = try? container.decode(String.self, forKey: .createdAt) else { return nil }
        return AuthJSON.date(from: raw)
    }
}

struct AuthSessionResponse: Decodable, Equatable {
    let token: String
    let tokenType: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case token
        case tokenType = "token_type"
        case user
    }
}

struct AuthAPIErrorPayload: Decodable, Equatable {
    let code: String
    let message: String
}

enum AuthAPIError: Error, Equatable {
    case invalidBaseURL
    case invalidEmail
    case weakPassword
    case emailTaken
    case invalidCredentials
    case unauthenticated
    case server(message: String)
    case unreachable
    case unexpected

    /// Copy the screens can show. Prefer the server's Chinese `message` when we have one.
    var userMessage: String {
        switch self {
        case .invalidBaseURL:
            return "服务器地址无效，请检查开发服务器设置。"
        case .invalidEmail:
            return "邮箱格式不正确"
        case .weakPassword:
            return "密码至少 8 位"
        case .emailTaken:
            return "该邮箱已注册"
        case .invalidCredentials:
            return "邮箱或密码不正确"
        case .unauthenticated:
            return "登录已过期，请重新登录"
        case .server(let message):
            return message
        case .unreachable:
            return "连不上服务器。请确认电脑上的服务已启动，并且手机和电脑在同一 Wi-Fi。真机请把开发服务器地址改成电脑的局域网 IP。"
        case .unexpected:
            return "出了点问题，请稍后再试。"
        }
    }

    static func from(statusCode: Int, payload: AuthAPIErrorPayload?) -> AuthAPIError {
        if let payload {
            switch payload.code {
            case "invalid_email": return .invalidEmail
            case "weak_password": return .weakPassword
            case "email_taken": return .emailTaken
            case "invalid_credentials": return .invalidCredentials
            case "unauthenticated": return .unauthenticated
            default:
                if payload.message.isEmpty { return .unexpected }
                return .server(message: payload.message)
            }
        }
        if statusCode == 401 { return .unauthenticated }
        if (500...599).contains(statusCode) { return .unexpected }
        return .unexpected
    }
}

enum AuthJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let date = try? container.decode(Date.self) {
                return date
            }
            let raw = try container.decode(String.self)
            if let date = date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(raw)")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func date(from raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }
}
