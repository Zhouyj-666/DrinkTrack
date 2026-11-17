import Foundation
import CoreData

/// DrinkSession / DrinkLog 的读写封装，View 层不直接操作 NSManagedObjectContext。
@MainActor
final class DrinkRepository: ObservableObject {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        self.context = context
    }

    // MARK: FR-DASH-04 会话开始/结束

    @discardableResult
    func startNewSession() -> DrinkSessionEntity {
        let session = DrinkSessionEntity(context: context)
        session.id = UUID()
        session.startedAt = Date()
        session.status = "active"
        save()
        return session
    }

    /// FR-DR-06：一键开始——创建会话并立刻写入第一条记录（上次的种类和杯型，新用户默认啤酒 330ml）。
    /// 不弹确认表单；用户可以稍后在会话里继续改或再加记录。
    @discardableResult
    func startSessionWithQuickLog() -> DrinkSessionEntity {
        let session = startNewSession()
        addDrinkLog(
            to: session,
            category: UserPreferences.lastDrinkCategory,
            brand: nil,
            volumeML: UserPreferences.lastDrinkVolumeML,
            timestamp: Date()
        )
        return session
    }

    /// 修改本场地点（会话详情页可编辑）。空字符串表示清除。
    /// 若带上坐标，会写到本场，并把同一地点名称、但还没有坐标的旧记录补上，方便出现在地图上。
    func updateLocation(
        of session: DrinkSessionEntity,
        to name: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            session.locationName = nil
            LocationCoordinate.apply(nil, to: session)
            save()
            return
        }
        session.locationName = trimmed
        let coordinate = LocationCoordinate.validated(latitude: latitude, longitude: longitude)
            ?? knownCoordinate(forPlaceName: trimmed)
        LocationCoordinate.apply(coordinate, to: session)
        UserPreferences.rememberLocation(trimmed)
        if let coordinate {
            backfillCoordinates(forPlaceName: trimmed, latitude: coordinate.0, longitude: coordinate.1)
        }
        save()
    }

    func endSession(_ session: DrinkSessionEntity) {
        session.status = "archived"
        session.endedAt = Date()
        save()
    }

    func fetchActiveSession() -> DrinkSessionEntity? {
        let request = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        request.predicate = NSPredicate(format: "status == %@", "active")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkSessionEntity.startedAt, ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchArchivedSessions(limit: Int = 200) -> [DrinkSessionEntity] {
        let request = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        request.predicate = NSPredicate(format: "status == %@", "archived")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkSessionEntity.startedAt, ascending: false)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }

    // MARK: FR-DR-01~05 饮酒手工录入 / FR-DR-07 可选花费

    /// - Parameters:
    ///   - customABVFraction: 仅 `.other` 类目或用户想手动覆盖默认 ABV 时传入（小数形式）
    ///   - amountFen: 可选花费，单位为分（1 元 = 100 分）。`nil` 表示这次没记花费。
    ///   - latitude / longitude: 仅在用户点「用当前位置」或沿用同一地点已有坐标时传入。
    @discardableResult
    func addDrinkLog(
        to session: DrinkSessionEntity,
        category: DrinkCategory,
        brand: String?,
        volumeML: Double,
        timestamp: Date = Date(),
        note: String? = nil,
        customABVFraction: Double? = nil,
        amountFen: Int? = nil,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> DrinkLogEntity {
        let log = DrinkLogEntity(context: context)
        log.id = UUID()
        log.category = category.rawValue
        log.brand = brand
        log.volumeMl = volumeML
        log.timestamp = timestamp
        log.note = note
        log.standardDrinks = StandardDrinkConverter.standardDrinks(
            volumeML: volumeML, category: category, customABVFraction: customABVFraction
        ) ?? 0
        if let amountFen {
            log.setValue(amountFen, forKey: "amountFen")
        }
        // Store the ABV actually used for the standard-drink figure, so a brand's
        // 53% (rather than the category's typical 42%) is visible later.
        if let abv = customABVFraction ?? category.typicalABVFraction {
            log.setValue(abv * 100, forKey: "abvPercent")
        }
        // FR-DR-05 地点（可选）：记在这一条上；会话还没有地点时，顺手作为本场地点。
        let trimmedLocation = locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedLocation.isEmpty {
            let coordinate = LocationCoordinate.validated(latitude: latitude, longitude: longitude)
                ?? knownCoordinate(forPlaceName: trimmedLocation)
            log.setValue(trimmedLocation, forKey: "locationName")
            LocationCoordinate.apply(coordinate, to: log)
            if (session.locationName ?? "").isEmpty {
                session.locationName = trimmedLocation
                LocationCoordinate.apply(coordinate, to: session)
            } else if session.locationName == trimmedLocation, LocationCoordinate.pair(from: session) == nil, let coordinate {
                LocationCoordinate.apply(coordinate, to: session)
            }
            UserPreferences.rememberLocation(trimmedLocation)
            if let coordinate {
                backfillCoordinates(forPlaceName: trimmedLocation, latitude: coordinate.0, longitude: coordinate.1)
            }
        }
        log.session = session
        UserPreferences.rememberLastDrink(category: category, volumeML: volumeML)
        save()
        return log
    }

    func save() {
        guard context.hasChanges else { return }
        try? context.save()
        NotificationCenter.default.post(name: .drinkTrackDataDidChange, object: nil)
    }

    // MARK: Places / 饮酒地图

    /// Exact-name lookup for a coordinate the user already granted via current location
    /// or an explicit PlaceMark. Never geocodes a typed name.
    func knownCoordinate(forPlaceName name: String) -> (Double, Double)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let logRequest = NSFetchRequest<DrinkLogEntity>(entityName: "DrinkLog")
        logRequest.predicate = NSPredicate(format: "locationName == %@ AND latitude != nil AND longitude != nil", trimmed)
        logRequest.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkLogEntity.timestamp, ascending: false)]
        logRequest.fetchLimit = 1
        if let log = try? context.fetch(logRequest).first, let pair = LocationCoordinate.pair(from: log) {
            return pair
        }

        let sessionRequest = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        sessionRequest.predicate = NSPredicate(format: "locationName == %@ AND latitude != nil AND longitude != nil", trimmed)
        sessionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkSessionEntity.startedAt, ascending: false)]
        sessionRequest.fetchLimit = 1
        if let session = try? context.fetch(sessionRequest).first, let pair = LocationCoordinate.pair(from: session) {
            return pair
        }

        let markRequest = NSFetchRequest<NSManagedObject>(entityName: "PlaceMark")
        markRequest.predicate = NSPredicate(format: "name == %@", trimmed)
        markRequest.sortDescriptors = [NSSortDescriptor(key: "markedAt", ascending: false)]
        markRequest.fetchLimit = 1
        if let mark = try? context.fetch(markRequest).first {
            let latitude = Self.doubleKey(mark, "latitude")
            let longitude = Self.doubleKey(mark, "longitude")
            if let pair = LocationCoordinate.validated(latitude: latitude, longitude: longitude) {
                return pair
            }
        }
        return nil
    }

    /// Fill coordinates on same-named records that still have none. Existing
    /// coordinates are left untouched so a later reading does not rewrite history.
    func backfillCoordinates(forPlaceName name: String, latitude: Double, longitude: Double) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, LocationCoordinate.isValid(latitude: latitude, longitude: longitude) else { return }
        let pair = (latitude, longitude)

        let logRequest = NSFetchRequest<DrinkLogEntity>(entityName: "DrinkLog")
        logRequest.predicate = NSPredicate(format: "locationName == %@ AND (latitude == nil OR longitude == nil)", trimmed)
        for log in (try? context.fetch(logRequest)) ?? [] {
            LocationCoordinate.apply(pair, to: log)
        }

        let sessionRequest = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        sessionRequest.predicate = NSPredicate(format: "locationName == %@ AND (latitude == nil OR longitude == nil)", trimmed)
        for session in (try? context.fetch(sessionRequest)) ?? [] {
            LocationCoordinate.apply(pair, to: session)
        }
    }

    /// Groups the user's own sessions and logs by exact place name.
    /// Name-only places stay in the list even when they have no coordinates.
    /// Explicit PlaceMarks contribute coordinates / catalog entries but never
    /// inflate drink-session counts.
    func placeSummaries() -> [PlaceSummary] {
        let sessions = fetchAllSessions(limit: 1000)
        var buckets: [String: PlaceAccumulator] = [:]

        for session in sessions {
            let sessionPlace = Self.trimmed(session.locationName)
            let sessionCoordinate = LocationCoordinate.pair(from: session)
            let logs = ((session.logs as? Set<DrinkLogEntity>) ?? []).sorted {
                ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
            }
            var attributed = Set<String>()

            for log in logs {
                let logPlace = Self.trimmed(log.value(forKey: "locationName") as? String)
                guard let place = logPlace ?? sessionPlace else { continue }
                let coordinate = LocationCoordinate.pair(from: log)
                    ?? (place == sessionPlace ? sessionCoordinate : nil)
                var acc = buckets[place] ?? PlaceAccumulator(name: place)
                acc.addLog(log, coordinate: coordinate)
                if attributed.insert(place).inserted {
                    acc.addSession(session)
                }
                buckets[place] = acc
            }

            if let sessionPlace, attributed.contains(sessionPlace) == false {
                var acc = buckets[sessionPlace] ?? PlaceAccumulator(name: sessionPlace)
                acc.addSession(session)
                acc.consider(coordinate: sessionCoordinate, at: session.startedAt)
                buckets[sessionPlace] = acc
            }
        }

        for mark in fetchPlaceMarks() {
            guard let name = Self.trimmed(mark.value(forKey: "name") as? String) else { continue }
            let latitude = Self.doubleKey(mark, "latitude")
            let longitude = Self.doubleKey(mark, "longitude")
            let markedAt = mark.value(forKey: "markedAt") as? Date
            var acc = buckets[name] ?? PlaceAccumulator(name: name)
            acc.considerMark(
                coordinate: LocationCoordinate.validated(latitude: latitude, longitude: longitude),
                at: markedAt
            )
            buckets[name] = acc
        }

        return buckets.values
            .map { $0.summary() }
            .sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
    }

    /// Chronological 饮酒地图 stops (sessions with coordinates + PlaceMarks).
    func routeStops() -> [RouteStop] {
        let sessions = fetchAllSessions(limit: 1000).map { session -> (id: String, name: String?, startedAt: Date?, latitude: Double?, longitude: Double?, volumeML: Double, standardDrinks: Double) in
            let logs = (session.logs as? Set<DrinkLogEntity>) ?? []
            let volume = logs.reduce(0.0) { $0 + $1.volumeMl }
            let standard = logs.reduce(0.0) { $0 + $1.standardDrinks }
            let pair = LocationCoordinate.pair(from: session)
            return (
                id: session.objectID.uriRepresentation().absoluteString,
                name: session.locationName,
                startedAt: session.startedAt,
                latitude: pair?.0,
                longitude: pair?.1,
                volumeML: volume,
                standardDrinks: standard
            )
        }

        let marks = fetchPlaceMarks().compactMap { mark -> (id: String, name: String, markedAt: Date, latitude: Double, longitude: Double)? in
            guard let name = Self.trimmed(mark.value(forKey: "name") as? String),
                  let markedAt = mark.value(forKey: "markedAt") as? Date,
                  let latitude = Self.doubleKey(mark, "latitude"),
                  let longitude = Self.doubleKey(mark, "longitude") else {
                return nil
            }
            let id = (mark.value(forKey: "id") as? UUID)?.uuidString
                ?? mark.objectID.uriRepresentation().absoluteString
            return (id: id, name: name, markedAt: markedAt, latitude: latitude, longitude: longitude)
        }

        return RouteJournal.stops(sessions: sessions, placeMarks: marks)
    }

    // MARK: PlaceMark / 饮酒地图标记

    func fetchPlaceMarks() -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PlaceMark")
        request.sortDescriptors = [NSSortDescriptor(key: "markedAt", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    /// Explicit map mark that is NOT a drink session. Same-name drink rows get
    /// coordinates back-filled; session counts stay unchanged.
    @discardableResult
    func addPlaceMark(
        name: String,
        latitude: Double,
        longitude: Double,
        markedAt: Date = Date(),
        note: String? = nil
    ) -> NSManagedObject? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let pair = LocationCoordinate.validated(latitude: latitude, longitude: longitude),
              let entity = NSEntityDescription.entity(forEntityName: "PlaceMark", in: context) else {
            return nil
        }
        let mark = NSManagedObject(entity: entity, insertInto: context)
        mark.setValue(UUID(), forKey: "id")
        mark.setValue(trimmed, forKey: "name")
        mark.setValue(pair.0, forKey: "latitude")
        mark.setValue(pair.1, forKey: "longitude")
        mark.setValue(markedAt, forKey: "markedAt")
        if let note {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            mark.setValue(trimmedNote.isEmpty ? nil : trimmedNote, forKey: "note")
        }
        UserPreferences.rememberLocation(trimmed)
        backfillCoordinates(forPlaceName: trimmed, latitude: pair.0, longitude: pair.1)
        save()
        return mark
    }

    /// Fill coordinates on same-named drink rows (and leave PlaceMarks alone).
    func applyCoordinatesToPlaceName(_ name: String, latitude: Double, longitude: Double) {
        backfillCoordinates(forPlaceName: name, latitude: latitude, longitude: longitude)
        save()
    }

    private static func trimmed(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    // MARK: FR-TREND-* 长期趋势报告数据源

    /// 取指定时间之后的所有饮酒记录。
    ///
    /// 注意这里**不过滤会话状态**：之前只查 `session.status == "archived"`，
    /// 导致用户刚录入、还没点「结束会话」的记录在趋势页完全看不到——
    /// 但那杯酒是真的喝了，没理由因为会话还开着就不算数。
    func allLogs(since: Date) -> [DrinkLogEntity] {
        let request = NSFetchRequest<DrinkLogEntity>(entityName: "DrinkLog")
        request.predicate = NSPredicate(format: "timestamp >= %@", since as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkLogEntity.timestamp, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// 所有会话（含进行中），用于历史记录列表。
    func fetchAllSessions(limit: Int = 200) -> [DrinkSessionEntity] {
        let request = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkSessionEntity.startedAt, ascending: false)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }

    /// 把一条会话提示追加到本场（写入 DrinkSession.alertsJSON）。同类提示在 30 分钟内不重复记录。
    @discardableResult
    func appendAlert(_ alert: AlertThresholdEngine.AlertResult, to session: DrinkSessionEntity, cooldownMinutes: Double = 30) -> Bool {
        var alerts = alerts(for: session)
        if let last = alerts.last(where: { $0.kind == alert.kind }),
           alert.triggeredAt.timeIntervalSince(last.triggeredAt) < cooldownMinutes * 60 {
            return false
        }
        alerts.append(alert)
        if let json = AlertThresholdEngine.encode(alerts) {
            session.setValue(json, forKey: "alertsJSON")
            save()
        }
        return true
    }

    func alerts(for session: DrinkSessionEntity) -> [AlertThresholdEngine.AlertResult] {
        AlertThresholdEngine.decode(session.value(forKey: "alertsJSON") as? String)
    }

        /// FR-DR-07 monthly spend: this calendar month's total, the same month-to-date
    /// figure, and the average among sessions that recorded at least one amount.
    func monthSpendSummary(now: Date = Date()) -> (monthTotalFen: Int, monthToDateFen: Int, sessionAverageFen: Int?, sessionCount: Int) {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let logs = allLogs(since: startOfMonth)
        var total = 0
        var sessionsWithSpend = Set<NSManagedObjectID>()
        for log in logs {
            guard let raw = log.value(forKey: "amountFen") as? NSNumber else { continue }
            total += raw.intValue
            if let sessionID = log.session?.objectID {
                sessionsWithSpend.insert(sessionID)
            }
        }
        let count = sessionsWithSpend.count
        let average = count > 0 ? Int((Double(total) / Double(count)).rounded()) : nil
        // 本月花费 and 本月至今花费 are the same number while the month is still
        // in progress: we cannot know future days. Both are month-to-date.
        return (total, total, average, count)
    }

    private static func doubleKey(_ object: NSManagedObject, _ key: String) -> Double? {
        if let number = object.value(forKey: key) as? NSNumber {
            return number.doubleValue
        }
        return object.value(forKey: key) as? Double
    }
}