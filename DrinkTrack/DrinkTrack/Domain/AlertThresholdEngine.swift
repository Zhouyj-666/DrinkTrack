import Foundation

/// §6.2 被动预警阈值规则。
///
/// 决策背景（Q1）：MVP 先用保守阈值上线，阈值以用户**个性化基线**（安静心率、7 天 HRV 均值）
/// 为参照，而非固定数值；收集真实用户数据后再迭代（§8 R5 也明确标注 +30bpm 这个数字本身
/// 需要后续根据数据调整，这里先按 PRD 原值实现，不擅自改数字）。
struct AlertThresholdEngine {

    enum AlertKind {
        case heartRate
        case spo2
        case hrv
        case afib

        /// FR-LEGAL-03 / FR-DASH-03：所有预警文案固定包含免责声明。
        var disclaimerMessage: String { DisclaimerStrings.passiveAlertDisclaimer }
    }

    struct AlertResult {
        let kind: AlertKind
        let message: String
    }

    /// 心率阈值：安静心率 + 30bpm，持续 5 分钟以上（§6.2）。
    /// - Parameters:
    ///   - recentHeartRates: 最近若干分钟的心率采样点（时间升序）
    ///   - restingHeartRate: 用户安静心率基线（User.restingHeartRate，若用户没填则取
    ///     HealthKit 最近 7 天静息均值，由调用方在取数据时就处理好，这里只做判断）
    ///   - sustainedMinutes: 需要持续超过阈值的分钟数，默认 5（对应 PRD 数值）
    static func evaluateHeartRate(recentHeartRates: [(timestamp: Date, bpm: Double)],
                                   restingHeartRate: Double,
                                   sustainedMinutes: Double = 5) -> AlertResult? {
        let threshold = restingHeartRate + 30
        let overThreshold = recentHeartRates.filter { $0.bpm > threshold }
        guard let first = overThreshold.first, let last = overThreshold.last else { return nil }
        let sustained = last.timestamp.timeIntervalSince(first.timestamp) / 60
        guard sustained >= sustainedMinutes else { return nil }
        return AlertResult(kind: .heartRate, message: DisclaimerStrings.passiveAlertDisclaimer)
    }

    /// 血氧阈值：< 93% 持续 10 分钟（§6.2，留了缓冲以应对 Apple Watch ±2% 误差）。
    static func evaluateSpO2(recentSpO2: [(timestamp: Date, percent: Double)],
                              sustainedMinutes: Double = 10) -> AlertResult? {
        let below = recentSpO2.filter { $0.percent < 93 }
        guard let first = below.first, let last = below.last else { return nil }
        let sustained = last.timestamp.timeIntervalSince(first.timestamp) / 60
        guard sustained >= sustainedMinutes else { return nil }
        return AlertResult(kind: .spo2, message: DisclaimerStrings.passiveAlertDisclaimer)
    }

    /// HRV 阈值：当前 SDNN < 用户 7 天（无饮酒状态下）均值的 50%（§6.2）。
    static func evaluateHRV(currentSDNN: Double, baseline7DayAverage: Double) -> AlertResult? {
        guard baseline7DayAverage > 0 else { return nil }
        guard currentSDNN < baseline7DayAverage * 0.5 else { return nil }
        return AlertResult(kind: .hrv, message: DisclaimerStrings.passiveAlertDisclaimer)
    }

    /// 异常心律：Apple Health 检测到 AFib 事件且时间戳落在 DrinkSession 期间（§6.2）。
    /// 合规风险最高，必须用 FR-LEGAL-04 的额外免责文案，而不是通用免责文案。
    static func evaluateAFib(eventTimestamp: Date, sessionRange: ClosedRange<Date>) -> AlertResult? {
        guard sessionRange.contains(eventTimestamp) else { return nil }
        return AlertResult(kind: .afib, message: DisclaimerStrings.afibExtraDisclaimer)
    }

    // 不触发预警的场景（§6.2 明确列出，这里作为文档存档，实际过滤逻辑在数据采集层去噪，
    // 不在本引擎里重复实现"去抖"逻辑）：
    // - 单次心率瞬时跳变（手表佩戴松动）
    // - 血氧仅偶尔 < 95%（正常波动）
    // - HRV 持续低但用户没在饮酒（可能是数据质量问题）
}
