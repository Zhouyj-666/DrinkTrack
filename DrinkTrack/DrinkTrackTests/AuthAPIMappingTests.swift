import XCTest
@testable import DrinkTrack

final class AuthAPIMappingTests: XCTestCase {
    func testDecodesSessionResponseWithUUIDUser() throws {
        let json = """
        {
          "token": "tok_abc",
          "token_type": "bearer",
          "user": {
            "id": "11111111-2222-3333-4444-555555555555",
            "email": "you@example.com",
            "display_name": "小酌",
            "created_at": "2026-11-17T07:00:00.000000+00:00"
          }
        }
        """.data(using: .utf8)!

        let response = try AuthJSON.decoder.decode(AuthSessionResponse.self, from: json)
        XCTAssertEqual(response.token, "tok_abc")
        XCTAssertEqual(response.tokenType, "bearer")
        XCTAssertEqual(response.user.email, "you@example.com")
        XCTAssertEqual(response.user.displayName, "小酌")
        XCTAssertEqual(response.user.id, "11111111-2222-3333-4444-555555555555")
        XCTAssertNotNil(response.user.createdAt)
    }

    func testMapsChineseErrorPayloads() throws {
        let cases: [(String, String, Int, AuthAPIError)] = [
            ("email_taken", "该邮箱已注册", 409, .emailTaken),
            ("invalid_credentials", "邮箱或密码不正确", 401, .invalidCredentials),
            ("invalid_email", "邮箱格式不正确", 422, .invalidEmail),
            ("weak_password", "密码至少 8 位", 422, .weakPassword),
            ("unauthenticated", "登录已过期，请重新登录", 401, .unauthenticated)
        ]
        for (code, message, status, expected) in cases {
            let data = """
            {"code":"\(code)","message":"\(message)"}
            """.data(using: .utf8)!
            let payload = try AuthJSON.decoder.decode(AuthAPIErrorPayload.self, from: data)
            XCTAssertEqual(payload.message, message)
            XCTAssertEqual(AuthAPIError.from(statusCode: status, payload: payload), expected)
            XCTAssertEqual(expected.userMessage, message)
        }
    }

    func testUnknownServerMessageIsPassedThrough() throws {
        let payload = AuthAPIErrorPayload(code: "rate_limited", message: "操作太频繁，请稍后再试")
        let error = AuthAPIError.from(statusCode: 429, payload: payload)
        XCTAssertEqual(error, .server(message: "操作太频繁，请稍后再试"))
        XCTAssertEqual(error.userMessage, "操作太频繁，请稍后再试")
    }

    func testUnreachableCopyIsHonestAboutLANSetup() {
        XCTAssertTrue(AuthAPIError.unreachable.userMessage.contains("局域网"))
        XCTAssertEqual(AuthAPIError.invalidBaseURL.userMessage, "服务器地址无效，请检查开发服务器设置。")
    }

    func testDefaultBaseURLIsLocalNotAFakeHost() {
        XCTAssertEqual(AuthAPIConfiguration.defaultBaseURLString, "http://127.0.0.1:8000")
        XCTAssertFalse(AuthAPIConfiguration.defaultBaseURLString.contains("production"))
        XCTAssertFalse(AuthAPIConfiguration.defaultBaseURLString.contains("https://api."))
    }

    func testDecodesFastAPIMicrosecondCreatedAt() throws {
        // Exact shape returned by the in-repo FastAPI service (6-digit frac, Z).
        let json = """
        {
          "token": "tok_live",
          "token_type": "bearer",
          "user": {
            "id": "914bf60d-f8f0-45a1-9364-165bdab434ba",
            "email": "you@example.com",
            "display_name": "probe",
            "created_at": "2026-11-17T08:26:56.276158Z"
          }
        }
        """.data(using: .utf8)!

        let response = try AuthJSON.decoder.decode(AuthSessionResponse.self, from: json)
        XCTAssertEqual(response.user.id, "914bf60d-f8f0-45a1-9364-165bdab434ba")
        XCTAssertEqual(response.user.displayName, "probe")
        XCTAssertNotNil(response.user.createdAt)
    }

    func testDateParserAcceptsPydanticAndUnixFormats() {
        XCTAssertNotNil(AuthJSON.date(from: "2026-11-17T08:26:56.276158Z"))
        XCTAssertNotNil(AuthJSON.date(from: "2026-11-17T07:00:00.000000+00:00"))
        XCTAssertNotNil(AuthJSON.date(from: "2026-11-17T07:00:00Z"))
        XCTAssertNotNil(AuthJSON.date(from: "2026-11-17T07:00:00+00:00"))
    }

    func testSessionResponseStillDecodesWhenCreatedAtMissing() throws {
        let json = """
        {
          "token": "tok_abc",
          "token_type": "bearer",
          "user": {
            "id": "11111111-2222-3333-4444-555555555555",
            "email": "you@example.com",
            "display_name": "小酌"
          }
        }
        """.data(using: .utf8)!
        let response = try AuthJSON.decoder.decode(AuthSessionResponse.self, from: json)
        XCTAssertNil(response.user.createdAt)
        XCTAssertEqual(response.user.email, "you@example.com")
    }
}
