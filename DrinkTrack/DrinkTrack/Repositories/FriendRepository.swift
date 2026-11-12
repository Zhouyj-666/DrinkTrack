import Foundation

/// §5.5 轻量社交模块的数据接口。
///
/// 本轮（第一轮交付）只提供 `MockFriendRepository`：好友关系和动态 feed 用内存里的
/// 示例数据驱动，UI 完整可交互，但不连接任何真实后端/CloudKit——因为真实的跨设备好友关系
/// 需要后端或 CloudKit 公共数据库支持 FR-SOC-01 的"好友码扫码/链接邀请 + 双向确认"，
/// 这部分留给后续轮次实现，不在这一轮里做一半假装能用，误导用户以为已经能加到真实好友。
///
/// 后续轮次接入真实数据源时，只需要新增一个实现这个 protocol 的 `CloudKitFriendRepository`，
/// 把 App 启动时注入的实例换掉即可，Feature 层的 View/ViewModel 不需要改。
protocol FriendRepository {
    func myFriendCode() async -> String
    func fetchFriends() async -> [FriendSummary]
    /// FR-SOC-02：好友最近 7 天的饮酒记录摘要 feed
    func fetchFeed() async -> [FriendFeedItem]
    /// FR-SOC-01：发起好友请求（扫码/输入好友码）；mock 版本直接返回成功，不做真实网络请求
    func sendFriendRequest(code: String) async -> Result<FriendSummary, FriendRequestError>
}

enum FriendRequestError: LocalizedError {
    case codeNotFound
    case alreadyFriends

    var errorDescription: String? {
        switch self {
        case .codeNotFound: return "好友码不存在，请确认后重试"
        case .alreadyFriends: return "你们已经是好友了"
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

/// 本轮默认实现：纯本地 mock 数据，不发任何网络请求。
final class MockFriendRepository: FriendRepository {
    private let sampleCode = "482913"

    func myFriendCode() async -> String { sampleCode }

    func fetchFriends() async -> [FriendSummary] {
        [
            FriendSummary(id: UUID(), displayName: "阿杰", friendCode: "118204", status: "confirmed"),
            FriendSummary(id: UUID(), displayName: "小美", friendCode: "773310", status: "confirmed"),
            FriendSummary(id: UUID(), displayName: "老王", friendCode: "556729", status: "pending"),
        ]
    }

    func fetchFeed() async -> [FriendFeedItem] {
        let now = Date()
        return [
            FriendFeedItem(id: UUID(), friendDisplayName: "阿杰", date: now.addingTimeInterval(-3600 * 5),
                            category: .beer, totalVolumeML: 1500, note: "公司团建，微醺"),
            FriendFeedItem(id: UUID(), friendDisplayName: "小美", date: now.addingTimeInterval(-3600 * 20),
                            category: .redWine, totalVolumeML: 300, note: "和朋友小聚"),
            FriendFeedItem(id: UUID(), friendDisplayName: "阿杰", date: now.addingTimeInterval(-3600 * 48),
                            category: .baijiu, totalVolumeML: 150, note: nil),
        ]
    }

    func sendFriendRequest(code: String) async -> Result<FriendSummary, FriendRequestError> {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            return .failure(.codeNotFound)
        }
        return .success(FriendSummary(id: UUID(), displayName: "新好友 \(code.suffix(2))", friendCode: code, status: "pending"))
    }
}
