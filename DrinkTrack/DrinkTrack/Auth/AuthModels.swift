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
        // Never decode Date.self here. AuthJSON's custom date strategy would
        // re-enter the same closure and overflow the stack.
        if let raw = try? container.decode(String.self, forKey: .createdAt) {
            return AuthJSON.date(from: raw)
        }
        if let seconds = try? container.decode(Double.self, forKey: .createdAt) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
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
            // Calling decode(Date.self) inside a custom date strategy recurses
            // into this closure and crashes with a stack overflow. Parse
            // strings (and numeric timestamps) only.
            if let raw = try? container.decode(String.self),
               let date = date(from: raw) {
                return date
            }
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let seconds = try? container.decode(Int.self) {
                return Date(timeIntervalSince1970: TimeInterval(seconds))
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date value")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Parses the date strings FastAPI/Pydantic actually emit, including
    /// microsecond precision and `+00:00` offsets.
    static func date(from raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = iso8601Date(from: trimmed, fractional: true)
            ?? iso8601Date(from: trimmed, fractional: false) {
            return date
        }
        if let normalized = normalizeISO8601(trimmed),
           let date = iso8601Date(from: normalized, fractional: true)
            ?? iso8601Date(from: normalized, fractional: false) {
            return date
        }
        return posixDate(from: trimmed)
    }

    private static func iso8601Date(from raw: String, fractional: Bool) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    /// Collapse `+00:00` to `Z` and clamp fractional seconds to milliseconds
    /// so ISO8601DateFormatter can parse FastAPI's 6-digit values.
    private static func normalizeISO8601(_ raw: String) -> String? {
        var value = raw
        if value.hasSuffix("+00:00") {
            value = String(value.dropLast(6)) + "Z"
        }
        guard let dot = value.firstIndex(of: ".") else { return value }
        let prefix = String(value[..<dot])
        let rest = String(value[value.index(after: dot)...])
        var digits = ""
        var zone = ""
        var readingDigits = true
        for character in rest {
            if readingDigits, character.isNumber {
                digits.append(character)
            } else {
                readingDigits = false
                zone.append(character)
            }
        }
        if zone == "+00:00" { zone = "Z" }
        if digits.isEmpty { return prefix + zone }
        let millis = String(digits.padding(toLength: 3, withPad: "0", startingAt: 0).prefix(3))
        return prefix + "." + millis + zone
    }

    private static func posixDate(from raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
