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
    func updateLocation(of session: DrinkSessionEntity, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.locationName = trimmed.isEmpty ? nil : trimmed
        if !trimmed.isEmpty { UserPreferences.rememberLocation(trimmed) }
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
        locationName: String? = nil
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
            log.setValue(trimmedLocation, forKey: "locationName")
            if (session.locationName ?? "").isEmpty {
                session.locationName = trimmedLocation
            }
            UserPreferences.rememberLocation(trimmedLocation)
        }
        log.session = session
        UserPreferences.rememberLastDrink(category: category, volumeML: volumeML)
        save()
        return log
    }

    func save() {
        guard context.hasChanges else { return }
        try? context.save()
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
}
