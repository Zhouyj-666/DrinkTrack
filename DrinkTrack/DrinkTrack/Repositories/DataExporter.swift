import Foundation
import CoreData
import SwiftUI

/// 把本机饮酒记录导出为 JSON（完整备份）或 CSV（方便用表格打开）。
/// 导出文件写在临时目录，再交给系统分享面板，DrinkTrack 不会自行上传。
enum DataExporter {
    struct Result {
        let url: URL
        let fileName: String
    }

    enum Format: String {
        case json
        case csv
    }

    static func export(format: Format, context: NSManagedObjectContext = PersistenceController.shared.viewContext) throws -> Result {
        switch format {
        case .json: return try exportJSON(context: context)
        case .csv: return try exportCSV(context: context)
        }
    }

    // MARK: - JSON

    private static func exportJSON(context: NSManagedObjectContext) throws -> Result {
        let payload: [String: Any] = [
            "app": "DrinkTrack",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            "exportedAt": iso(Date()),
            "note": "本文件由 DrinkTrack 在本机生成。含饮酒记录、会话、可选花费和地点、本场提示和个人基础信息；不含 Apple 健康里的原始心率/血氧样本。",
            "profile": profileJSON(context: context),
            "sessions": sessionsJSON(context: context),
            "friends": friendsJSON(context: context)
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return try write(data: data, fileName: fileName(prefix: "DrinkTrack-记录", ext: "json"))
    }

    private static func profileJSON(context: NSManagedObjectContext) -> [String: Any] {
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.fetchLimit = 1
        guard let profile = try? context.fetch(request).first else { return [:] }
        var body: [String: Any] = [
            "gender": profile.gender ?? "other",
            "birthYear": Int(profile.birthYear),
            "weightKg": Int(profile.weightKg),
            "restingHeartRate": Int(profile.restingHeartRate),
            "restingHRSource": profile.restingHRSource ?? "manual",
            "friendCode": profile.friendCode ?? ""
        ]
        if let created = profile.createdAt { body["createdAt"] = iso(created) }
        return body
    }

    private static func sessionsJSON(context: NSManagedObjectContext) -> [[String: Any]] {
        let request = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkSessionEntity.startedAt, ascending: false)]
        let sessions = (try? context.fetch(request)) ?? []
        return sessions.map { session in
            let logs = ((session.logs as? Set<DrinkLogEntity>) ?? []).sorted {
                ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
            }
            var body: [String: Any] = [
                "id": session.id?.uuidString ?? "",
                "status": session.status ?? "",
                "logs": logs.map(logJSON),
                "alerts": alertsJSON(session)
            ]
            if let started = session.startedAt { body["startedAt"] = iso(started) }
            if let ended = session.endedAt { body["endedAt"] = iso(ended) }
            if let place = session.locationName, !place.isEmpty { body["locationName"] = place }
            return body
        }
    }

    private static func logJSON(_ log: DrinkLogEntity) -> [String: Any] {
        var body: [String: Any] = [
            "id": log.id?.uuidString ?? "",
            "category": log.category ?? "",
            "volumeMl": log.volumeMl,
            "standardDrinks": log.standardDrinks
        ]
        if let brand = log.brand, !brand.isEmpty { body["brand"] = brand }
        if let note = log.note, !note.isEmpty { body["note"] = note }
        if let timestamp = log.timestamp { body["timestamp"] = iso(timestamp) }
        if let place = log.value(forKey: "locationName") as? String, !place.isEmpty {
            body["locationName"] = place
        }
        if let abv = log.value(forKey: "abvPercent") as? NSNumber {
            body["abvPercent"] = abv.doubleValue
        }
        if let fen = log.value(forKey: "amountFen") as? NSNumber {
            body["amountFen"] = fen.intValue
            body["amountYuan"] = Double(fen.intValue) / 100.0
        }
        return body
    }

    private static func alertsJSON(_ session: DrinkSessionEntity) -> [[String: Any]] {
        let raw = session.value(forKey: "alertsJSON") as? String
        return AlertThresholdEngine.decode(raw).map { alert in
            var body: [String: Any] = [
                "id": alert.id.uuidString,
                "kind": alert.kind.rawValue,
                "title": alert.title,
                "reason": alert.reason,
                "triggeredAt": iso(alert.triggeredAt)
            ]
            if let value = alert.measuredValue { body["measuredValue"] = value }
            if let value = alert.thresholdValue { body["thresholdValue"] = value }
            return body
        }
    }

    private static func friendsJSON(context: NSManagedObjectContext) -> [[String: Any]] {
        let request = NSFetchRequest<FriendConnectionEntity>(entityName: "FriendConnection")
        request.sortDescriptors = [NSSortDescriptor(key: "connectedAt", ascending: false)]
        let friends = (try? context.fetch(request)) ?? []
        return friends.map { friend in
            var body: [String: Any] = [
                "displayName": friend.friendDisplayName ?? "",
                "friendCode": friend.friendCode ?? "",
                "status": friend.status ?? ""
            ]
            if let connected = friend.connectedAt { body["connectedAt"] = iso(connected) }
            return body
        }
    }

    // MARK: - CSV

    private static func exportCSV(context: NSManagedObjectContext) throws -> Result {
        let request = NSFetchRequest<DrinkLogEntity>(entityName: "DrinkLog")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkLogEntity.timestamp, ascending: false)]
        let logs = (try? context.fetch(request)) ?? []

        var lines: [String] = []
        lines.append(["时间", "酒种类", "品牌", "容量ml", "酒精度%", "标准饮品", "地点", "花费元", "备注", "会话开始", "会话状态"].joined(separator: ","))
        for log in logs {
            let category = log.category.flatMap(DrinkCategory.init(rawValue:))?.displayName ?? (log.category ?? "")
            let brand = log.brand ?? ""
            let abv = (log.value(forKey: "abvPercent") as? NSNumber).map { formatNumber($0.doubleValue) } ?? ""
            let place = (log.value(forKey: "locationName") as? String)
                ?? log.session?.locationName
                ?? ""
            let yuan: String
            if let fen = log.value(forKey: "amountFen") as? NSNumber {
                yuan = String(format: "%.2f", Double(fen.intValue) / 100.0)
            } else {
                yuan = ""
            }
            let started = log.session?.startedAt.map(iso) ?? ""
            let status = log.session?.status ?? ""
            let fields = [
                log.timestamp.map(iso) ?? "",
                category,
                brand,
                formatNumber(log.volumeMl),
                abv,
                formatNumber(log.standardDrinks),
                place,
                yuan,
                log.note ?? "",
                started,
                status == "active" ? "进行中" : (status == "archived" ? "已结束" : status)
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        // BOM so Excel on Windows opens UTF-8 correctly.
        let body = "\u{FEFF}" + lines.joined(separator: "\r\n")
        let data = Data(body.utf8)
        return try write(data: data, fileName: fileName(prefix: "DrinkTrack-记录", ext: "csv"))
    }

    // MARK: - Files

    private static func write(data: Data, fileName: String) throws -> Result {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return Result(url: url, fileName: fileName)
    }

    private static func fileName(prefix: String, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "\(prefix)-\(formatter.string(from: Date())).\(ext)"
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

/// 把临时文件交给系统分享面板。
struct ActivityShareView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
