import SwiftUI
import CoreData

/// A compact dashboard digest: today / this week volume, session count,
/// this month's spend, week-vs-last-week facts, and the most-logged type.
/// Facts only, no cut-back framing.
struct DashboardGlanceView: View {
    let todayVolumeML: Double
    let todayStandard: Double
    let weekVolumeML: Double
    let weekStandard: Double
    let weekSessionCount: Int
    let lastWeekVolumeML: Double
    let lastWeekStandard: Double
    let monthSessionCount: Int
    let monthPlaceCount: Int
    let monthSpendFen: Int
    let monthSpendCount: Int
    let showSpend: Bool
    let topCategory: DrinkCategory?
    let topBrand: String?
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

            HStack(spacing: 10) {
                metricTile(
                    icon: "calendar.badge.clock",
                    title: "上周",
                    value: volumeLine(ml: lastWeekVolumeML, standard: lastWeekStandard),
                    caption: lastWeekVolumeML > 0 ? "对照看一眼" : "上周没有记录"
                )
                metricTile(
                    icon: "building.2.fill",
                    title: "本月",
                    value: monthSessionCount > 0 ? "\(monthSessionCount) 场" : "—",
                    caption: monthPlaceCount > 0 ? "走过 \(monthPlaceCount) 个地方" : (monthSessionCount > 0 ? "还没有地点" : "还没有场次")
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

            if let topBrand, !topBrand.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color("AccentColor"))
                    Text("本月常喝")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.secondaryInk)
                    Text(topBrand)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.primaryInk)
                    if let topCategory {
                        Text("· \(topCategory.displayName)")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
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

/// Plain facts used by glance metrics so unit tests do not need Core Data entities.
struct GlanceLogFact {
    let timestamp: Date
    let volumeMl: Double
    let standardDrinks: Double
    let categoryRaw: String?
    let brand: String?
    let amountFen: Int?
    let locationName: String?
}

struct GlanceSessionFact {
    let startedAt: Date
    let locationName: String?
}

enum DashboardGlanceBuilder {
    static func metrics(
        logs: [DrinkLogEntity],
        sessions: [DrinkSessionEntity],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Metrics {
        let logFacts: [GlanceLogFact] = logs.compactMap { log in
            guard let timestamp = log.timestamp else { return nil }
            return GlanceLogFact(
                timestamp: timestamp,
                volumeMl: log.volumeMl,
                standardDrinks: log.standardDrinks,
                categoryRaw: log.category,
                brand: log.brand,
                amountFen: (log.value(forKey: "amountFen") as? NSNumber)?.intValue,
                locationName: (log.value(forKey: "locationName") as? String) ?? log.session?.locationName
            )
        }
        let sessionFacts: [GlanceSessionFact] = sessions.compactMap { session in
            guard let started = session.startedAt else { return nil }
            return GlanceSessionFact(startedAt: started, locationName: session.locationName)
        }
        return metrics(logs: logFacts, sessions: sessionFacts, now: now, calendar: calendar)
    }

    struct Metrics {
        let todayVolumeML: Double
        let todayStandard: Double
        let weekVolumeML: Double
        let weekStandard: Double
        let weekSessionCount: Int
        let lastWeekVolumeML: Double
        let lastWeekStandard: Double
        let monthSessionCount: Int
        let monthPlaceCount: Int
        let monthSpendFen: Int
        let monthSpendCount: Int
        let topCategory: DrinkCategory?
        let topBrand: String?
        let mix: [(DrinkCategory, Double)]
    }

    static func metrics(
        logs: [GlanceLogFact],
        sessions: [GlanceSessionFact],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Metrics {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfDay
        let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: startOfWeek) ?? startOfWeek
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfDay

        var todayML = 0.0, todayStd = 0.0
        var weekML = 0.0, weekStd = 0.0
        var lastWeekML = 0.0, lastWeekStd = 0.0
        var monthFen = 0, monthSpendCount = 0
        var weekByCategory: [DrinkCategory: Double] = [:]
        var monthByCategory: [DrinkCategory: Double] = [:]
        var monthByBrand: [String: Double] = [:]
        var monthPlaces = Set<String>()

        for log in logs {
            let timestamp = log.timestamp
            let volume = log.volumeMl
            let standard = log.standardDrinks
            if timestamp >= startOfDay {
                todayML += volume
                todayStd += standard
            }
            if timestamp >= startOfWeek {
                weekML += volume
                weekStd += standard
                if let category = log.categoryRaw.flatMap(DrinkCategory.init(rawValue:)) {
                    weekByCategory[category, default: 0] += volume
                }
            } else if timestamp >= startOfLastWeek && timestamp < startOfWeek {
                lastWeekML += volume
                lastWeekStd += standard
            }
            if timestamp >= startOfMonth {
                if let fen = log.amountFen {
                    monthFen += fen
                    monthSpendCount += 1
                }
                if let category = log.categoryRaw.flatMap(DrinkCategory.init(rawValue:)) {
                    monthByCategory[category, default: 0] += volume
                }
                if let brand = log.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
                    monthByBrand[brand, default: 0] += volume
                }
                if let place = log.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
                    monthPlaces.insert(place)
                }
            }
        }

        let weekSessionCount = sessions.filter { $0.startedAt >= startOfWeek }.count
        let monthSessionCount = sessions.filter { $0.startedAt >= startOfMonth }.count
        for session in sessions where session.startedAt >= startOfMonth {
            if let place = session.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
                monthPlaces.insert(place)
            }
        }

        let totalMix = weekByCategory.values.reduce(0, +)
        let ranked = weekByCategory.sorted { $0.value > $1.value }
        let topWeek = ranked.first?.key
        let mix = ranked.prefix(3).map { category, volume in
            (category, totalMix > 0 ? volume / totalMix : 0)
        }
        let topMonthCategory = monthByCategory.sorted { $0.value > $1.value }.first?.key
        let topBrand = monthByBrand.sorted { $0.value > $1.value }.first?.key

        return Metrics(
            todayVolumeML: todayML,
            todayStandard: todayStd,
            weekVolumeML: weekML,
            weekStandard: weekStd,
            weekSessionCount: weekSessionCount,
            lastWeekVolumeML: lastWeekML,
            lastWeekStandard: lastWeekStd,
            monthSessionCount: monthSessionCount,
            monthPlaceCount: monthPlaces.count,
            monthSpendFen: monthFen,
            monthSpendCount: monthSpendCount,
            topCategory: topWeek ?? topMonthCategory,
            topBrand: topBrand,
            mix: mix
        )
    }
}