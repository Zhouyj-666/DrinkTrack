import Foundation

/// Small, local preferences that are not part of the Core Data profile.
/// Spend visibility and the last used drink preset live here so they survive
/// app restarts without a model migration.
enum UserPreferences {
    private static let spendTrackingKey = "spendTrackingEnabled"
    private static let lastCategoryKey = "lastDrinkCategory"
    private static let lastVolumeKey = "lastDrinkVolumeML"

    /// FR-DR-07: spend entry and the monthly spend summary are on by default.
    /// Turning this off hides amount fields and the trends spend card.
    static var spendTrackingEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: spendTrackingKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: spendTrackingKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: spendTrackingKey) }
    }

    /// Last category used when logging a drink. New users fall back to beer.
    static var lastDrinkCategory: DrinkCategory {
        get {
            if let raw = UserDefaults.standard.string(forKey: lastCategoryKey),
               let category = DrinkCategory(rawValue: raw) {
                return category
            }
            return .beer
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastCategoryKey) }
    }

    /// Last cup/volume used when logging a drink. New users fall back to 330ml.
    static var lastDrinkVolumeML: Double {
        get {
            let value = UserDefaults.standard.double(forKey: lastVolumeKey)
            return value > 0 ? value : 330
        }
        set { UserDefaults.standard.set(newValue, forKey: lastVolumeKey) }
    }

    private static let recentLocationsKey = "recentLocationNames"
    private static let shareShowsLocationKey = "shareCardShowsLocation"

    /// FR-DR-05: the last few place names the user typed or filled, newest first,
    /// offered as one-tap chips in the quick-log sheet. Stored only on device.
    static var recentLocations: [String] {
        UserDefaults.standard.stringArray(forKey: recentLocationsKey) ?? []
    }

    static func rememberLocation(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recentLocations.filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(list.prefix(6)), forKey: recentLocationsKey)
    }

    static func clearRecentLocations() {
        UserDefaults.standard.removeObject(forKey: recentLocationsKey)
    }

    /// Share cards hide the place by default; the user opts in per card.
    static var shareCardShowsLocation: Bool {
        get { UserDefaults.standard.bool(forKey: shareShowsLocationKey) }
        set { UserDefaults.standard.set(newValue, forKey: shareShowsLocationKey) }
    }

    static func rememberLastDrink(category: DrinkCategory, volumeML: Double) {
        lastDrinkCategory = category
        lastDrinkVolumeML = volumeML
    }

    /// Short label for the one-tap start button, e.g. "啤酒 330ml".
    static var oneTapPresetLabel: String {
        let volume = Int(lastDrinkVolumeML.rounded())
        return "\(lastDrinkCategory.displayName) \(volume)ml"
    }

    /// Format an amount stored in 分 (cents) as yuan for display.
    static func formatYuan(fen: Int) -> String {
        String(format: "¥%.2f", Double(fen) / 100.0)
    }

    static func parseYuanToFen(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let yuan = Double(normalized), yuan >= 0, yuan.isFinite else { return nil }
        return Int((yuan * 100).rounded())
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds)秒" }
        let minutes = seconds / 60
        let remainSeconds = seconds % 60
        if seconds < 3600 {
            return remainSeconds == 0 ? "\(minutes)分钟" : "\(minutes)分\(remainSeconds)秒"
        }
        let hours = seconds / 3600
        let remainMinutes = (seconds % 3600) / 60
        if remainMinutes == 0 { return "\(hours)小时" }
        return "\(hours)小时\(remainMinutes)分"
    }
}
