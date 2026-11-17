import Foundation
import CoreData

/// Restore a JSON backup written by `DataExporter`. The file stays on device;
/// nothing is uploaded. HealthKit samples are not in the backup and are never faked.
enum DataImporter {
    static let supportedSchemaVersion = 2

    enum Mode {
        case merge
        case replace
    }

    enum Failure: LocalizedError {
        case unreadable
        case notJSON
        case unrecognized
        case newerSchema(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "无法读取这个文件。"
            case .notJSON:
                return "这个文件不是可识别的 JSON。"
            case .unrecognized:
                return "这个文件不像是小酌场的备份。请选择由本 App 导出的 JSON 备份。"
            case .newerSchema(let version):
                return "这个备份的格式版本是 \(version)，当前 App 只支持到版本 \(DataImporter.supportedSchemaVersion)。请先把小酌场更新到更新的版本，再尝试导入。"
            case .empty:
                return "这个备份里没有可以导入的会话、饮酒记录、饮酒地图标记、好友或个人基础信息。"
            }
        }
    }

    struct Preview {
        let fileName: String
        let exportedAt: Date?
        let schemaVersion: Int
        let sessionCount: Int
        let activeSessionCount: Int
        let logCount: Int
        let spendCount: Int
        let spendFen: Int
        let placeCount: Int
        let placeMarkCount: Int
        let alertCount: Int
        let hasProfile: Bool
        let friendCount: Int
        let duplicateSessionCount: Int
        let duplicateLogCount: Int
        let duplicateFriendCount: Int
        let localHasActiveSession: Bool
        let payload: [String: Any]
    }

    struct Outcome {
        let sessionsAdded: Int
        let sessionsSkipped: Int
        let logsAdded: Int
        let friendsAdded: Int
        let placesAdded: Int
        let placeMarksAdded: Int
        let profileImported: Bool
        let archivedImportedActive: Bool
    }

    static func preview(from url: URL, context: NSManagedObjectContext) throws -> Preview {
        let payload = try loadPayload(from: url)
        let sessions = payload["sessions"] as? [[String: Any]] ?? []
        let friends = payload["friends"] as? [[String: Any]] ?? []
        let placeMarks = payload["placeMarks"] as? [[String: Any]] ?? []
        let profile = payload["profile"] as? [String: Any]
        let hasProfile = profile.map { !$0.isEmpty } ?? false

        var logCount = 0
        var spendCount = 0
        var spendFen = 0
        var alertCount = 0
        var places = Set<String>()
        var activeCount = 0
        var duplicateSessions = 0
        var duplicateLogs = 0
        let existingSessions = existingSessionIDs(in: context)
        let existingLogs = existingLogIDs(in: context)
        let existingFriends = existingFriendCodes(in: context)

        for session in sessions {
            if (session["status"] as? String) == "active" { activeCount += 1 }
            if let place = string(session["locationName"]) { places.insert(place) }
            if let sessionID = uuid(session["id"]), existingSessions.contains(sessionID) {
                duplicateSessions += 1
            }
            let logs = session["logs"] as? [[String: Any]] ?? []
            logCount += logs.count
            for log in logs {
                if let logID = uuid(log["id"]), existingLogs.contains(logID) {
                    duplicateLogs += 1
                }
                if let place = string(log["locationName"]) { places.insert(place) }
                if let fen = intValue(log["amountFen"]) {
                    spendCount += 1
                    spendFen += fen
                }
            }
            alertCount += (session["alerts"] as? [Any])?.count ?? 0
        }

        var duplicateFriends = 0
        for friend in friends {
            if let code = string(friend["friendCode"]), existingFriends.contains(code) {
                duplicateFriends += 1
            }
        }

        if sessions.isEmpty && friends.isEmpty && placeMarks.isEmpty && !hasProfile {
            throw Failure.empty
        }

        return Preview(
            fileName: url.lastPathComponent,
            exportedAt: dateValue(payload["exportedAt"]),
            schemaVersion: intValue(payload["schemaVersion"]) ?? 1,
            sessionCount: sessions.count,
            activeSessionCount: activeCount,
            logCount: logCount,
            spendCount: spendCount,
            spendFen: spendFen,
            placeCount: places.count,
            placeMarkCount: placeMarks.count,
            alertCount: alertCount,
            hasProfile: hasProfile,
            friendCount: friends.count,
            duplicateSessionCount: duplicateSessions,
            duplicateLogCount: duplicateLogs,
            duplicateFriendCount: duplicateFriends,
            localHasActiveSession: (try? context.fetch(activeSessionRequest()).first) != nil,
            payload: payload
        )
    }

    static func apply(_ preview: Preview, mode: Mode, context: NSManagedObjectContext) throws -> Outcome {
        if mode == .replace {
            try PersistenceController.shared.eraseAllLocalData()
            UserPreferences.clearRecentLocations()
        }

        let payload = preview.payload
        let sessions = payload["sessions"] as? [[String: Any]] ?? []
        let friends = payload["friends"] as? [[String: Any]] ?? []
        let placeMarks = payload["placeMarks"] as? [[String: Any]] ?? []
        let profile = payload["profile"] as? [String: Any]

        let existingSessions = existingSessionIDs(in: context)
        let existingLogs = existingLogIDs(in: context)
        let existingFriends = existingFriendCodes(in: context)
        let localActive = (try? context.fetch(activeSessionRequest()).first) != nil

        var sessionsAdded = 0
        var sessionsSkipped = 0
        var logsAdded = 0
        var archivedImportedActive = false
        var importedAnActive = false
        var places: [String] = []

        for sessionPayload in sessions {
            guard let startedAt = dateValue(sessionPayload["startedAt"]) else {
                sessionsSkipped += 1
                continue
            }
            if let sessionID = uuid(sessionPayload["id"]), existingSessions.contains(sessionID) {
                sessionsSkipped += 1
                continue
            }

            let session = DrinkSessionEntity(context: context)
            session.id = uuid(sessionPayload["id"]) ?? UUID()
            session.startedAt = startedAt
            session.endedAt = dateValue(sessionPayload["endedAt"])
            var status = string(sessionPayload["status"]) ?? "archived"
            if status == "active" {
                if importedAnActive || (mode == .merge && localActive) {
                    status = "archived"
                    if session.endedAt == nil { session.endedAt = Date() }
                    archivedImportedActive = true
                } else {
                    importedAnActive = true
                }
            }
            session.status = status
            if let place = string(sessionPayload["locationName"]) {
                session.locationName = place
                places.append(place)
            }
            applyCoordinates(sessionPayload, to: session)
            if let alerts = sessionPayload["alerts"] as? [[String: Any]],
               let encoded = encodeAlerts(alerts) {
                session.setValue(encoded, forKey: "alertsJSON")
            }

            let logs = sessionPayload["logs"] as? [[String: Any]] ?? []
            for logPayload in logs {
                if let logID = uuid(logPayload["id"]), existingLogs.contains(logID) {
                    continue
                }
                guard let timestamp = dateValue(logPayload["timestamp"]) else { continue }
                let log = DrinkLogEntity(context: context)
                log.id = uuid(logPayload["id"]) ?? UUID()
                log.category = string(logPayload["category"]) ?? DrinkCategory.other.rawValue
                log.brand = string(logPayload["brand"])
                log.volumeMl = doubleValue(logPayload["volumeMl"]) ?? 0
                log.standardDrinks = doubleValue(logPayload["standardDrinks"]) ?? 0
                log.timestamp = timestamp
                log.note = string(logPayload["note"])
                if let place = string(logPayload["locationName"]) {
                    log.setValue(place, forKey: "locationName")
                    places.append(place)
                }
                applyCoordinates(logPayload, to: log)
                if let abv = doubleValue(logPayload["abvPercent"]) {
                    log.setValue(abv, forKey: "abvPercent")
                }
                if let fen = intValue(logPayload["amountFen"]) {
                    log.setValue(fen, forKey: "amountFen")
                }
                log.session = session
                logsAdded += 1
            }
            sessionsAdded += 1
        }

        var friendsAdded = 0
        for friendPayload in friends {
            guard let code = string(friendPayload["friendCode"]), !code.isEmpty else { continue }
            if existingFriends.contains(code) { continue }
            let friend = FriendConnectionEntity(context: context)
            friend.id = uuid(friendPayload["id"]) ?? UUID()
            friend.friendCode = code
            let fallback = "好友 " + String(code.suffix(3))
            friend.friendDisplayName = string(friendPayload["displayName"]) ?? fallback
            friend.status = string(friendPayload["status"]) ?? "pending"
            friend.connectedAt = dateValue(friendPayload["connectedAt"]) ?? Date()
            friend.feedVisible = true
            friendsAdded += 1
        }

        var placeMarksAdded = 0
        let existingMarkIDs = existingPlaceMarkIDs(in: context)
        for markPayload in placeMarks {
            guard let name = string(markPayload["name"]),
                  let latitude = doubleValue(markPayload["latitude"]),
                  let longitude = doubleValue(markPayload["longitude"]),
                  let pair = LocationCoordinate.validated(latitude: latitude, longitude: longitude),
                  let entity = NSEntityDescription.entity(forEntityName: "PlaceMark", in: context) else {
                continue
            }
            if let markID = uuid(markPayload["id"]), existingMarkIDs.contains(markID), mode == .merge {
                continue
            }
            let mark = NSManagedObject(entity: entity, insertInto: context)
            mark.setValue(uuid(markPayload["id"]) ?? UUID(), forKey: "id")
            mark.setValue(name, forKey: "name")
            mark.setValue(pair.0, forKey: "latitude")
            mark.setValue(pair.1, forKey: "longitude")
            mark.setValue(dateValue(markPayload["markedAt"]) ?? Date(), forKey: "markedAt")
            mark.setValue(string(markPayload["note"]), forKey: "note")
            places.append(name)
            placeMarksAdded += 1
        }

        let profileImported = importProfile(profile, mode: mode, context: context)

        var seenPlaces = Set<String>()
        for place in places.reversed() {
            if seenPlaces.insert(place).inserted {
                UserPreferences.rememberLocation(place)
            }
        }

        if context.hasChanges {
            try context.save()
        }

        return Outcome(
            sessionsAdded: sessionsAdded,
            sessionsSkipped: sessionsSkipped,
            logsAdded: logsAdded,
            friendsAdded: friendsAdded,
            placesAdded: seenPlaces.count,
            placeMarksAdded: placeMarksAdded,
            profileImported: profileImported,
            archivedImportedActive: archivedImportedActive
        )
    }

    // MARK: - Payload

    private static func loadPayload(from url: URL) throws -> [String: Any] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Failure.unreadable
        }
        let trimmed = stripBOM(data)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: trimmed)
        } catch {
            throw Failure.notJSON
        }
        guard let payload = object as? [String: Any] else {
            throw Failure.unrecognized
        }
        if let version = intValue(payload["schemaVersion"]), version > supportedSchemaVersion {
            throw Failure.newerSchema(version)
        }
        if !looksLikeBackup(payload) {
            throw Failure.unrecognized
        }
        return payload
    }

    private static func looksLikeBackup(_ payload: [String: Any]) -> Bool {
        if payload["sessions"] is [Any] { return true }
        if payload["placeMarks"] is [Any] { return true }
        if payload["friends"] is [Any] { return true }
        if payload["profile"] is [String: Any] { return true }
        if let app = string(payload["app"]), app == "SipSession" || app == "DrinkTrack" {
            return true
        }
        if string(payload["displayName"]) == "小酌场" { return true }
        return false
    }

    private static func stripBOM(_ data: Data) -> Data {
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return data.subdata(in: 3..<data.count)
        }
        return data
    }

    // MARK: - Profile

    private static func importProfile(_ profile: [String: Any]?, mode: Mode, context: NSManagedObjectContext) -> Bool {
        guard let profile, !profile.isEmpty else { return false }
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.fetchLimit = 1
        let existing = try? context.fetch(request).first
        if mode == .merge, existing != nil {
            return false
        }
        let row = existing ?? UserProfileEntity(context: context)
        if row.id == nil { row.id = UUID() }
        if let gender = string(profile["gender"]) { row.gender = gender }
        if let birthYear = intValue(profile["birthYear"]) { row.birthYear = Int32(birthYear) }
        if let weight = intValue(profile["weightKg"]) { row.weightKg = Int32(weight) }
        if let hr = intValue(profile["restingHeartRate"]) { row.restingHeartRate = Int32(hr) }
        if let source = string(profile["restingHRSource"]) { row.restingHRSource = source }
        if let code = string(profile["friendCode"]), code.count == 6 {
            row.friendCode = code
        } else if (row.friendCode ?? "").count != 6 {
            row.friendCode = UserProfileStore.newFriendCode()
        }
        if row.createdAt == nil {
            row.createdAt = dateValue(profile["createdAt"]) ?? Date()
        }
        return true
    }

    // MARK: - Alerts

    private static func encodeAlerts(_ raw: [[String: Any]]) -> String? {
        let alerts: [AlertThresholdEngine.AlertResult] = raw.compactMap { body in
            guard let kindRaw = string(body["kind"]),
                  let kind = AlertThresholdEngine.AlertKind(rawValue: kindRaw),
                  let title = string(body["title"]),
                  let reason = string(body["reason"]),
                  let triggeredAt = dateValue(body["triggeredAt"]) else { return nil }
            return AlertThresholdEngine.AlertResult(
                id: uuid(body["id"]) ?? UUID(),
                kind: kind,
                title: title,
                reason: reason,
                triggeredAt: triggeredAt,
                measuredValue: doubleValue(body["measuredValue"]),
                thresholdValue: doubleValue(body["thresholdValue"])
            )
        }
        return AlertThresholdEngine.encode(alerts)
    }

    // MARK: - Lookups

    private static func existingSessionIDs(in context: NSManagedObjectContext) -> Set<UUID> {
        let request = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        let rows = (try? context.fetch(request)) ?? []
        return Set(rows.compactMap(\.id))
    }

    private static func existingLogIDs(in context: NSManagedObjectContext) -> Set<UUID> {
        let request = NSFetchRequest<DrinkLogEntity>(entityName: "DrinkLog")
        let rows = (try? context.fetch(request)) ?? []
        return Set(rows.compactMap(\.id))
    }

    private static func existingFriendCodes(in context: NSManagedObjectContext) -> Set<String> {
        let request = NSFetchRequest<FriendConnectionEntity>(entityName: "FriendConnection")
        let rows = (try? context.fetch(request)) ?? []
        return Set(rows.compactMap { $0.friendCode }.filter { !$0.isEmpty })
    }

    private static func existingPlaceMarkIDs(in context: NSManagedObjectContext) -> Set<UUID> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PlaceMark")
        let rows = (try? context.fetch(request)) ?? []
        return Set(rows.compactMap { $0.value(forKey: "id") as? UUID })
    }

    private static func activeSessionRequest() -> NSFetchRequest<DrinkSessionEntity> {
        let request = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        request.predicate = NSPredicate(format: "status == %@", "active")
        request.fetchLimit = 1
        return request
    }


    private static func applyCoordinates(_ payload: [String: Any], to object: NSManagedObject) {
        let pair = LocationCoordinate.validated(
            latitude: doubleValue(payload["latitude"]),
            longitude: doubleValue(payload["longitude"])
        )
        LocationCoordinate.apply(pair, to: object)
    }

    // MARK: - Scalars

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func uuid(_ value: Any?) -> UUID? {
        string(value).flatMap(UUID.init(uuidString:))
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        if let text = value as? String, let number = Int(text) { return number }
        if let number = value as? Double { return Int(number) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String, let number = Double(text) { return number }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let text = string(value) else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text)
    }
}


extension Notification.Name {
    static let drinkTrackDataDidChange = Notification.Name("drinkTrackDataDidChange")
}
