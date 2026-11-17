import XCTest
@testable import DrinkTrack

final class FriendCodeParserTests: XCTestCase {
    func testExtractsBareSixDigitCode() {
        XCTAssertEqual(FriendCodeParser.code(fromQRPayload: "123456"), "123456")
        XCTAssertTrue(FriendCodeParser.isValid("123456"))
    }

    func testAcceptsLeadingZeros() {
        XCTAssertEqual(FriendCodeParser.code(fromQRPayload: "000123"), "000123")
    }

    func testRejectsWrongLengthOrLetters() {
        XCTAssertNil(FriendCodeParser.code(fromQRPayload: "12345"))
        XCTAssertNil(FriendCodeParser.code(fromQRPayload: "1234567"))
        XCTAssertNil(FriendCodeParser.code(fromQRPayload: "12ab56"))
        XCTAssertFalse(FriendCodeParser.isValid("12345"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(FriendCodeParser.code(fromQRPayload: "  654321\n"), "654321")
    }

    func testExtractsCodeFromShareSentence() {
        let payload = "我的小酌场好友码是 123456。本版本先把码存到手机上，设备之间的动态互通还在后续。"
        XCTAssertEqual(FriendCodeParser.code(fromQRPayload: payload), "123456")
    }

    func testRejectsAmbiguousMultipleCodes() {
        XCTAssertNil(FriendCodeParser.code(fromQRPayload: "111111 and 222222"))
    }
}
