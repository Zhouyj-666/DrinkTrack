import Foundation

/// Snapshot of the current drinking session, sent from iPhone to Apple Watch
/// over WatchConnectivity. Dates travel as timeIntervalSince1970 so the
/// payload is a valid property-list dictionary (required by WCSession).
struct SessionSyncPayload: Equatable {
    var isSessionActive: Bool
    var startedAt: Date?
    var cupCount: Int
    var volumeML: Double
    var standardDrinks: Double
    /// In-session heart rate only. Nil when no real sample exists in this session.
    var latestHeartRate: Double?
    var latestHeartRateAt: Date?
    /// In-session SpO2 only. Nil when no real sample exists in this session.
    var latestSpO2: Double?
    var latestSpO2At: Date?
    var lastCategoryRaw: String
    var lastCategoryDisplayName: String
    var lastVolumeML: Double
    /// Short Chinese status from the phone about HealthKit / signing.
    var healthStatusText: String
    var updatedAt: Date

    static var empty: SessionSyncPayload {
        SessionSyncPayload(
            isSessionActive: false,
            startedAt: nil,
            cupCount: 0,
            volumeML: 0,
            standardDrinks: 0,
            latestHeartRate: nil,
            latestHeartRateAt: nil,
            latestSpO2: nil,
            latestSpO2At: nil,
            lastCategoryRaw: "beer",
            lastCategoryDisplayName: "啤酒",
            lastVolumeML: 330,
            healthStatusText: "还没有收到手机上的会话信息，请在手机上打开小酌场。",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    var hasRealSnapshot: Bool {
        updatedAt.timeIntervalSince1970 > 0
    }

    var presetLabel: String {
        "\(lastCategoryDisplayName) \(Int(lastVolumeML.rounded()))ml"
    }

    func plistDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "isSessionActive": isSessionActive,
            "cupCount": cupCount,
            "volumeML": volumeML,
            "standardDrinks": standardDrinks,
            "lastCategoryRaw": lastCategoryRaw,
            "lastCategoryDisplayName": lastCategoryDisplayName,
            "lastVolumeML": lastVolumeML,
            "healthStatusText": healthStatusText,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        if let startedAt { dict["startedAt"] = startedAt.timeIntervalSince1970 }
        if let latestHeartRate { dict["latestHeartRate"] = latestHeartRate }
        if let latestHeartRateAt { dict["latestHeartRateAt"] = latestHeartRateAt.timeIntervalSince1970 }
        if let latestSpO2 { dict["latestSpO2"] = latestSpO2 }
        if let latestSpO2At { dict["latestSpO2At"] = latestSpO2At.timeIntervalSince1970 }
        return dict
    }

    static func fromPlist(_ dict: [String: Any]) -> SessionSyncPayload? {
        guard let updatedAtRaw = Self.double(dict["updatedAt"]) else { return nil }
        var payload = SessionSyncPayload.empty
        payload.isSessionActive = Self.bool(dict["isSessionActive"])
        payload.startedAt = Self.date(dict["startedAt"])
        payload.cupCount = Int(Self.double(dict["cupCount"]) ?? 0)
        payload.volumeML = Self.double(dict["volumeML"]) ?? 0
        payload.standardDrinks = Self.double(dict["standardDrinks"]) ?? 0
        payload.latestHeartRate = Self.double(dict["latestHeartRate"])
        payload.latestHeartRateAt = Self.date(dict["latestHeartRateAt"])
        payload.latestSpO2 = Self.double(dict["latestSpO2"])
        payload.latestSpO2At = Self.date(dict["latestSpO2At"])
        payload.lastCategoryRaw = dict["lastCategoryRaw"] as? String ?? payload.lastCategoryRaw
        payload.lastCategoryDisplayName = dict["lastCategoryDisplayName"] as? String ?? payload.lastCategoryDisplayName
        payload.lastVolumeML = Self.double(dict["lastVolumeML"]) ?? payload.lastVolumeML
        payload.healthStatusText = dict["healthStatusText"] as? String ?? payload.healthStatusText
        payload.updatedAt = Date(timeIntervalSince1970: updatedAtRaw)
        return payload
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let interval = double(value), interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}

enum WatchCommandKey {
    static let command = "command"
    static let category = "category"
    static let volumeML = "volumeML"
    static let snapshot = "snapshot"
    static let ok = "ok"
    static let error = "error"

    static let startSession = "startSession"
    static let startQuickLog = "startQuickLog"
    static let endSession = "endSession"
    static let logDrink = "logDrink"
    static let requestSnapshot = "requestSnapshot"
}

/// Compact category list for the Watch "换一种" sheet. Display names and
/// default volumes are duplicated here so the Watch target does not have to
/// compile BrandLibrary / the full phone catalog.
enum WatchDrinkPreset: String, CaseIterable, Identifiable {
    case baijiu, beer, redWine, huangjiu, riceWine, sake, soju, spirits, cocktail, fruitWine, premix, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baijiu: return "白酒"
        case .beer: return "啤酒"
        case .redWine: return "红酒"
        case .huangjiu: return "黄酒"
        case .riceWine: return "米酒"
        case .sake: return "清酒"
        case .soju: return "烧酒"
        case .spirits: return "洋酒"
        case .cocktail: return "鸡尾酒"
        case .fruitWine: return "果酒"
        case .premix: return "预调酒"
        case .other: return "其他"
        }
    }

    /// A reasonable default pour for a one-tap Watch log, matching the phone's
    /// first preset when one exists.
    var defaultVolumeML: Double {
        switch self {
        case .baijiu: return 50
        case .beer: return 330
        case .redWine: return 150
        case .huangjiu: return 100
        case .riceWine: return 250
        case .sake: return 180
        case .soju: return 50
        case .spirits: return 30
        case .cocktail: return 200
        case .fruitWine: return 150
        case .premix: return 330
        case .other: return 100
        }
    }
}
