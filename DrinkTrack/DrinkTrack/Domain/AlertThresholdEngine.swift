import Foundation

/// §6.2 被动提示阈值规则。
///
/// 阈值以用户个性化基线（安静心率、近 7 天 HRV 均值）为参照，而不是固定数字。
/// +30 bpm、血氧 93%、HRV 减半这些数字来自 PRD 的保守起点，后续可根据真实数据再调，
/// 这里不擅自改数字。
struct AlertThresholdEngine {

    /// 用户未填写安静心率时使用的通用值（bpm）。
    static let defaultRestingHeartRate = 65.0

    /// 心率：安静心率之上再加这么多 bpm。
    static let heartRateOffset = 30.0
    /// 心率需要持续超过参考线的分钟数。
    static let heartRateSustainedMinutes = 5.0
    /// 血氧低于该百分比才会进入计时。
    static let spo2PercentThreshold = 93.0
    /// 血氧需要持续低于阈值的分钟数。
    static let spo2SustainedMinutes = 10.0
    /// 当前 SDNN 低于基线的这个比例时提示。
    static let hrvBaselineFraction = 0.5

    enum AlertKind: String, Codable, CaseIterable {
        case heartRate
        case spo2
        case hrv
        case afib

        var title: String {
            switch self {
            case .heartRate: return "心率持续偏高"
            case .spo2: return "血氧持续偏低"
            case .hrv: return "心率变异偏低"
            case .afib: return "检测到心律事件"
            }
        }

        var symbolName: String {
            switch self {
            case .heartRate: return "heart.fill"
            case .spo2: return "lungs.fill"
            case .hrv: return "waveform.path.ecg"
            case .afib: return "exclamationmark.circle.fill"
            }
        }
    }

    /// 一次提示的完整内容：标题、原因、测到的值、使用的参考线，以及固定免责。
    struct AlertResult: Identifiable, Codable, Equatable {
        var id: UUID
        var kind: AlertKind
        var title: String
        var reason: String
        var disclaimer: String
        var triggeredAt: Date
        var measuredValue: Double?
        var thresholdValue: Double?

        init(
            id: UUID = UUID(),
            kind: AlertKind,
            title: String? = nil,
            reason: String,
            disclaimer: String? = nil,
            triggeredAt: Date = Date(),
            measuredValue: Double? = nil,
            thresholdValue: Double? = nil
        ) {
            self.id = id
            self.kind = kind
            self.title = title ?? kind.title
            self.reason = reason
            self.disclaimer = disclaimer ?? (kind == .afib
                ? DisclaimerStrings.afibExtraDisclaimer
                : DisclaimerStrings.passiveAlertDisclaimer)
            self.triggeredAt = triggeredAt
            self.measuredValue = measuredValue
            self.thresholdValue = thresholdValue
        }

        static func == (lhs: AlertResult, rhs: AlertResult) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// 把档案里的安静心率整理成实际使用的基线：未填或无效时退回通用值。
    static func resolvedRestingHeartRate(from stored: Double?) -> Double {
        guard let stored, stored >= 35, stored <= 140 else {
            return defaultRestingHeartRate
        }
        return stored
    }

    static func heartRateThreshold(restingHeartRate stored: Double?) -> Double {
        resolvedRestingHeartRate(from: stored) + heartRateOffset
    }

    /// 心率：连续超过「安静心率 + 30bpm」至少 5 分钟。
    /// 中间一旦出现低于参考线的采样，计时重新开始，避免把间隔很久的两次跳变算成持续。
    static func evaluateHeartRate(
        recentHeartRates: [(timestamp: Date, bpm: Double)],
        restingHeartRate stored: Double?,
        sustainedMinutes: Double = heartRateSustainedMinutes,
        now: Date = Date()
    ) -> AlertResult? {
        let resting = resolvedRestingHeartRate(from: stored)
        let threshold = resting + heartRateOffset
        guard let run = longestSustainedRun(
            samples: recentHeartRates.map { ($0.timestamp, $0.bpm) },
            isHit: { $0 > threshold }
        ) else { return nil }
        let minutes = run.end.timeIntervalSince(run.start) / 60
        guard minutes >= sustainedMinutes else { return nil }
        let reason = String(
            format: "心率已连续约 %.0f 分钟高于参考线。刚才约 %.0f bpm，参考线是 %.0f bpm（安静心率 %.0f + %.0f）。",
            minutes.rounded(), run.lastValue, threshold, resting, heartRateOffset
        )
        return AlertResult(
            kind: .heartRate,
            reason: reason,
            triggeredAt: now,
            measuredValue: run.lastValue,
            thresholdValue: threshold
        )
    }

    /// 血氧：连续低于 93% 至少 10 分钟。
    static func evaluateSpO2(
        recentSpO2: [(timestamp: Date, percent: Double)],
        sustainedMinutes: Double = spo2SustainedMinutes,
        now: Date = Date()
    ) -> AlertResult? {
        guard let run = longestSustainedRun(
            samples: recentSpO2.map { ($0.timestamp, $0.percent) },
            isHit: { $0 < spo2PercentThreshold }
        ) else { return nil }
        let minutes = run.end.timeIntervalSince(run.start) / 60
        guard minutes >= sustainedMinutes else { return nil }
        let reason = String(
            format: "血氧已连续约 %.0f 分钟低于 %.0f%%。刚才约 %.0f%%。",
            minutes.rounded(), spo2PercentThreshold, run.lastValue
        )
        return AlertResult(
            kind: .spo2,
            reason: reason,
            triggeredAt: now,
            measuredValue: run.lastValue,
            thresholdValue: spo2PercentThreshold
        )
    }

    /// HRV：当前 SDNN 低于近 7 天均值的 50%。这是瞬时比较，不要求持续分钟数。
    static func evaluateHRV(
        currentSDNN: Double,
        baseline7DayAverage: Double,
        now: Date = Date()
    ) -> AlertResult? {
        guard baseline7DayAverage > 0 else { return nil }
        let threshold = baseline7DayAverage * hrvBaselineFraction
        guard currentSDNN < threshold else { return nil }
        let reason = String(
            format: "当前心率变异（SDNN）约 %.0f ms，低于近 7 天均值 %.0f ms 的一半。",
            currentSDNN, baseline7DayAverage
        )
        return AlertResult(
            kind: .hrv,
            reason: reason,
            triggeredAt: now,
            measuredValue: currentSDNN,
            thresholdValue: threshold
        )
    }

    /// 异常心律：Apple Health 检测到的事件落在本场会话时间段内。
    /// 合规风险最高，使用额外免责文案；默认不开启。
    static func evaluateAFib(
        eventTimestamp: Date,
        sessionRange: ClosedRange<Date>,
        now: Date = Date()
    ) -> AlertResult? {
        guard sessionRange.contains(eventTimestamp) else { return nil }
        return AlertResult(
            kind: .afib,
            reason: "Apple 健康在这场会话期间记录到一次心律事件。",
            disclaimer: DisclaimerStrings.afibExtraDisclaimer,
            triggeredAt: now
        )
    }

    // MARK: - Persistence helpers

    static func encode(_ alerts: [AlertResult]) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(alerts) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> [AlertResult] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AlertResult].self, from: data)) ?? []
    }

    // MARK: - Internals

    private struct Run {
        let start: Date
        let end: Date
        let lastValue: Double
    }

    /// 最长的一段连续「命中」采样。中间出现一次未命中就断开。
    private static func longestSustainedRun(
        samples: [(Date, Double)],
        isHit: (Double) -> Bool
    ) -> Run? {
        let sorted = samples.sorted { $0.0 < $1.0 }
        var best: Run?
        var runStart: Date?
        var lastHit: Date?
        var lastValue: Double?
        func closeRun() {
            guard let start = runStart, let end = lastHit, let value = lastValue else { return }
            let candidate = Run(start: start, end: end, lastValue: value)
            if best == nil || candidate.end.timeIntervalSince(candidate.start) > best!.end.timeIntervalSince(best!.start) {
                best = candidate
            }
        }
        for (timestamp, value) in sorted {
            if isHit(value) {
                if runStart == nil { runStart = timestamp }
                lastHit = timestamp
                lastValue = value
            } else {
                closeRun()
                runStart = nil
                lastHit = nil
                lastValue = nil
            }
        }
        closeRun()
        return best
    }
}
