import Foundation

/// Pulls the local 6-digit friend code out of a QR payload.
/// The in-app QR encodes the digits alone; a pasted share sentence is also accepted.
enum FriendCodeParser {
    static func isValid(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }

    static func code(fromQRPayload raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValid(trimmed) { return trimmed }

        var current = ""
        var candidates: [String] = []
        for character in trimmed {
            if character.isNumber {
                current.append(character)
            } else {
                if current.count == 6 { candidates.append(current) }
                current = ""
            }
        }
        if current.count == 6 { candidates.append(current) }
        if candidates.count == 1 { return candidates[0] }
        return nil
    }
}
