import Foundation

/// Configurable API root. Debug/dev default is a local server, never a fake production host.
enum AuthAPIConfiguration {
    static let defaultBaseURLString = "http://127.0.0.1:8000"
    private static let storageKey = "authAPIBaseURL"

    /// The URL the client will call. An empty preference falls back to the local default.
    static var baseURLString: String {
        get {
            let stored = UserDefaults.standard.string(forKey: storageKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty { return stored }
            return defaultBaseURLString
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: storageKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: storageKey)
            }
        }
    }

    static var baseURL: URL? {
        var raw = baseURLString
        if raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw)
    }
}
