import SwiftUI
import CoreData

/// A compact dashboard digest: today / this week volume, session count,
/// this month's spend, and the most-logged type. Facts only, no cut-back framing.
struct DashboardGlanceView: View {
    let todayVolumeML: Double
    let todayStandard: Double
    let weekVolumeML: Double
    let weekStandard: Double
    let weekSessionCount: Int
    let monthSpendFen: Int
    let monthSpendCount: Int
    let showSpend: Bool
    let topCategory: DrinkCategory?
    let mix: [(DrinkCategory, Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("饮酒一览")
                .font(.headline)

            HStack(spacing: 10) {
                metricTile(
                    icon: "sun.max.fill",
                    title: "今天",
                    value: volumeLine(ml: todayVolumeML, standard: todayStandard),
                    caption: todayVolumeML > 0 ? nil : "还没有记录"
                )
                metricTile(
                    icon: "calendar",
                    title: "本周",
                    value: volumeLine(ml: weekVolumeML, standard: weekStandard),
                    caption: weekSessionCount > 0 ? "\(weekSessionCount) 场" : "还没有场次"
                )
            }

            if showSpend {
                HStack(spacing: 10) {
                    metricTile(
                        icon: "yensign.circle.fill",
                        title: "本月花费",
                        value: monthSpendCount > 0 ? UserPreferences.formatYuan(fen: monthSpendFen) : "—",
                        caption: monthSpendCount > 0 ? "\(monthSpendCount) 条记了花费" : "本月还没记花费"
                    )
                }
            }

            if !mix.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.pie.fill")
                            .foregroundStyle(Color("AccentColor"))
                        Text("本周酒类")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.secondaryInk)
                        if let topCategory {
                            Text("最多是\(topCategory.displayName)")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.mutedInk)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(mix, id: \.0) { item in
                            HStack(spacing: 4) {
                                Image(systemName: item.0.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(DesignSystem.color(for: item.0))
                                Text(item.0.displayName)
                                    .font(.caption)
                                Text(percent(item.1))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DesignSystem.mutedInk)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(DesignSystem.color(for: item.0).opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metricTile(icon: String, title: String, value: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(Color("AccentColor"))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func volumeLine(ml: Double, standard: Double) -> String {
        if ml <= 0 { return "—" }
        return "\(formatML(ml)) · ≈\(formatStandard(standard))"
    }

    private func formatML(_ ml: Double) -> String {
        ml == ml.rounded() ? "\(Int(ml)) ml" : String(format: "%.0f ml", ml)
    }

    private func formatStandard(_ value: Double) -> String {
        String(format: "%.1f 标准饮品", value)
    }

    private func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }
}

enum DashboardGlanceBuilder {
    static func metrics(
        logs: [DrinkLogEntity],
        sessions: [DrinkSessionEntity],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (
        todayVolumeML: Double,
        todayStandard: Double,
        weekVolumeML: Double,
        weekStandard: Double,
        weekSessionCount: Int,
        monthSpendFen: Int,
        monthSpendCount: Int,
        topCategory: DrinkCategory?,
        mix: [(DrinkCategory, Double)]
    ) {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfDay
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfDay

        var todayML = 0.0, todayStd = 0.0
        var weekML = 0.0, weekStd = 0.0
        var monthFen = 0, monthSpendCount = 0
        var weekByCategory: [DrinkCategory: Double] = [:]

        for log in logs {
            guard let timestamp = log.timestamp else { continue }
            let volume = log.volumeMl
            let standard = log.standardDrinks
            if timestamp >= startOfDay {
                todayML += volume
                todayStd += standard
            }
            if timestamp >= startOfWeek {
                weekML += volume
                weekStd += standard
                if let category = log.category.flatMap(DrinkCategory.init(rawValue:)) {
                    weekByCategory[category, default: 0] += volume
                }
            }
            if timestamp >= startOfMonth, let fen = log.value(forKey: "amountFen") as? NSNumber {
                monthFen += fen.intValue
                monthSpendCount += 1
            }
        }

        let weekSessionCount = sessions.filter { session in
            guard let started = session.startedAt else { return false }
            return started >= startOfWeek
        }.count

        let totalMix = weekByCategory.values.reduce(0, +)
        let ranked = weekByCategory.sorted { $0.value > $1.value }
        let top = ranked.first?.key
        let mix = ranked.prefix(3).map { category, volume in
            (category, totalMix > 0 ? volume / totalMix : 0)
        }

        return (todayML, todayStd, weekML, weekStd, weekSessionCount, monthFen, monthSpendCount, top, mix)
    }
}
