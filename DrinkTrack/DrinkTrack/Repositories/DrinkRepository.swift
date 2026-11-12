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

    // MARK: FR-DR-01~05 饮酒手工录入

    /// - Parameters:
    ///   - customABVFraction: 仅 `.other` 类目或用户想手动覆盖默认 ABV 时传入（小数形式）
    @discardableResult
    func addDrinkLog(
        to session: DrinkSessionEntity,
        category: DrinkCategory,
        brand: String?,
        volumeML: Double,
        timestamp: Date = Date(),
        note: String? = nil,
        customABVFraction: Double? = nil
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
        log.session = session
        save()
        return log
    }

    func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }

    // MARK: FR-TREND-* 长期趋势报告数据源

    func allArchivedLogs(since: Date) -> [DrinkLogEntity] {
        let request = NSFetchRequest<DrinkLogEntity>(entityName: "DrinkLog")
        request.predicate = NSPredicate(format: "timestamp >= %@ AND session.status == %@", since as NSDate, "archived")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkLogEntity.timestamp, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
}
