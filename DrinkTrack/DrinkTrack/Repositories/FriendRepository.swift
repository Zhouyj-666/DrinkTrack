import Foundation
import CoreData

/// §5.5 轻量社交模块的数据接口。
///
/// 本版本只提供 `LocalFriendRepository`：好友码和好友列表保存在这台手机的 Core Data 里，
/// 不连接任何服务器或 CloudKit。换机、或想看对方设备上的动态，都还做不到。
/// 界面会如实说明这一点，不再用示例动态假装已经互通。
protocol FriendRepository {
    func myFriendCode() async -> String
    func fetchFriends() async -> [FriendSummary]
    /// FR-SOC-02：好友最近 7 天的饮酒摘要。本版本没有跨设备数据，一般返回空数组。
    func fetchFeed() async -> [FriendFeedItem]
    /// 把对方的 6 位好友码存到本机。不是网络请求。
    func sendFriendRequest(code: String) async -> Result<FriendSummary, FriendRequestError>
    func confirmFriend(id: UUID) async
    func removeFriend(id: UUID) async
    func renameFriend(id: UUID, displayName: String) async
}

enum FriendRequestError: LocalizedError {
    case codeNotFound
    case alreadyFriends
    case isSelf
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "请输入 6 位数字好友码"
        case .isSelf: return "这是你自己的好友码"
        case .alreadyFriends: return "这个好友码已经保存在本机了"
        case .codeNotFound: return "好友码格式不正确，请确认后重试"
        }
    }
}

struct FriendSummary: Identifiable {
    let id: UUID
    let displayName: String
    let friendCode: String
    let status: String // pending / confirmed
}

struct FriendFeedItem: Identifiable {
    let id: UUID
    let friendDisplayName: String
    let date: Date
    let category: DrinkCategory
    let totalVolumeML: Double
    let note: String?
}

/// 读取或创建本机用户档案。好友码在首次创建时生成，之后保持不变。
enum UserProfileStore {
    @discardableResult
    static func ensureProfile(in context: NSManagedObjectContext) -> UserProfileEntity {
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \UserProfileEntity.createdAt, ascending: false)]
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first {
            if (existing.friendCode ?? "").count != 6 {
                existing.friendCode = Self.newFriendCode()
                try? context.save()
            }
            return existing
        }
        let profile = UserProfileEntity(context: context)
        profile.id = UUID()
        profile.gender = "other"
        profile.birthYear = 0
        profile.weightKg = 0
        profile.restingHeartRate = 0
        profile.restingHRSource = "manual"
        profile.friendCode = newFriendCode()
        profile.afibDisplayEnabled = FeatureFlags.afibDisplayDefaultEnabled
        profile.iCloudSyncEnabled = false
        profile.createdAt = Date()
        try? context.save()
        return profile
    }

    static func newFriendCode() -> String {
        String(format: "%06d", Int.random(in: 0...999999))
    }
}

/// 本机好友列表。不发网络请求，也不能看到另一台设备上的动态。
@MainActor
final class LocalFriendRepository: ObservableObject, FriendRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        self.context = context
    }

    func myFriendCode() async -> String {
        UserProfileStore.ensureProfile(in: context).friendCode ?? UserProfileStore.newFriendCode()
    }

    func fetchFriends() async -> [FriendSummary] {
        let request = NSFetchRequest<FriendConnectionEntity>(entityName: "FriendConnection")
        request.sortDescriptors = [
            NSSortDescriptor(key: "status", ascending: true),
            NSSortDescriptor(key: "connectedAt", ascending: false)
        ]
        let rows = (try? context.fetch(request)) ?? []
        return rows.compactMap { row in
            guard let id = row.id else { return nil }
            return FriendSummary(
                id: id,
                displayName: row.friendDisplayName ?? "好友",
                friendCode: row.friendCode ?? "",
                status: row.status ?? "pending"
            )
        }
    }

    func fetchFeed() async -> [FriendFeedItem] {
        // 没有跨设备数据源，不能编造动态。
        []
    }

    func sendFriendRequest(code: String) async -> Result<FriendSummary, FriendRequestError> {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else {
            return .failure(.invalidCode)
        }
        let mine = await myFriendCode()
        if trimmed == mine {
            return .failure(.isSelf)
        }
        let existing = NSFetchRequest<FriendConnectionEntity>(entityName: "FriendConnection")
        existing.predicate = NSPredicate(format: "friendCode == %@", trimmed)
        existing.fetchLimit = 1
        if (try? context.fetch(existing).first) != nil {
            return .failure(.alreadyFriends)
        }

        let row = FriendConnectionEntity(context: context)
        let id = UUID()
        row.id = id
        row.friendCode = trimmed
        row.friendDisplayName = "好友 " + String(trimmed.suffix(3))
        row.status = "pending"
        row.connectedAt = Date()
        row.feedVisible = true
        try? context.save()
        return .success(FriendSummary(id: id, displayName: row.friendDisplayName ?? "好友", friendCode: trimmed, status: "pending"))
    }

    func confirmFriend(id: UUID) async {
        guard let row = connection(id: id) else { return }
        row.status = "confirmed"
        if row.connectedAt == nil { row.connectedAt = Date() }
        try? context.save()
    }

    func removeFriend(id: UUID) async {
        guard let row = connection(id: id) else { return }
        context.delete(row)
        try? context.save()
    }

    func renameFriend(id: UUID, displayName: String) async {
        guard let row = connection(id: id) else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        row.friendDisplayName = trimmed
        try? context.save()
    }

    private func connection(id: UUID) -> FriendConnectionEntity? {
        let request = NSFetchRequest<FriendConnectionEntity>(entityName: "FriendConnection")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
