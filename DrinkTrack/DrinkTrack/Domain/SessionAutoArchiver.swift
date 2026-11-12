import Foundation
import CoreData

/// FR-DASH-04：无 DrinkLog 录入超过 6 小时自动归档，避免用户忘记结束会话导致数据冗余。
struct SessionAutoArchiver {
    static let autoArchiveThresholdHours: Double = 6

    /// 检查某个进行中的会话是否应该被自动归档。
    /// - Parameter lastActivityAt: 会话内最后一次 DrinkLog 的时间（如果一条都没录，用 session.startedAt）
    static func shouldAutoArchive(lastActivityAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastActivityAt) >= autoArchiveThresholdHours * 3600
    }

    /// 扫描所有"进行中"的会话，把超时的自动归档。建议在 App 进入前台 /
    /// 场景激活时调用一次，而不是用一个持续运行的定时器（省电、避免后台任务被系统限制打断）。
    static func runAutoArchiveSweep(context: NSManagedObjectContext) {
        let request = NSFetchRequest<DrinkSessionEntity>(entityName: "DrinkSession")
        request.predicate = NSPredicate(format: "status == %@", "active")
        guard let activeSessions = try? context.fetch(request) else { return }

        for session in activeSessions {
            let logs = (session.logs as? Set<DrinkLogEntity>) ?? []
            let lastActivity = logs.map(\.timestamp).max() ?? session.startedAt
            if shouldAutoArchive(lastActivityAt: lastActivity ?? session.startedAt) {
                session.status = "archived"
                session.endedAt = Date()
            }
        }
        if context.hasChanges {
            try? context.save()
        }
    }
}
