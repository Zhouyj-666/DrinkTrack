import Foundation

/// 集中管理功能开关。
///
/// `afibDisplayEnabled` 对应 PRD §8 R3/R6 以及我们给出的建议①：
/// 异常心律 (AFib) 展示是全产品合规风险最高的功能点，法务文案尚未定稿前默认关闭。
/// 用户可以在 设置 → 实验性功能 里手动打开（会先弹一次 FR-LEGAL-04 的额外免责），
/// 但这个值的"出厂默认"必须是 false，不能等运营/产品经理去手动关一次。
enum FeatureFlags {
    /// 默认关闭。打开后 HealthKitManager 才会去查询 HKElectrocardiogramType / 房颤历史记录。
    static let afibDisplayDefaultEnabled = false

    /// iCloud 真实同步本轮未实现（见实现计划），这里只保留开关位，
    /// Settings 页会展示"即将推出"而不是假装已经同步。
    static let iCloudSyncImplemented = false
}
