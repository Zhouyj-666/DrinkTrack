import SwiftUI
import CoreData

/// Today / this-week / this-month summary cards for the redesigned dashboard.
struct DashboardSummaryStack: View {
    let todayVolumeML: Double
    let todayStandard: Double
    let weekVolumeML: Double
    let weekStandard: Double
    let weekSessionCount: Int
    let monthSessionCount: Int
    let monthPlaceCount: Int
    let monthSpendFen: Int
    let showSpend: Bool
    let topBrand: String?
    let mix: [DrinkMixShare]
    let lastEndedSession: DrinkSessionEntity?
    let lastSessionIsToday: Bool

    var body: some View {
        VStack(spacing: DesignSystem.cardSpacing) {
            todayCard
            if let session = lastEndedSession, !lastSessionIsToday {
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    LastSessionRow(session: session, showsDate: true)
                        .sipCard()
                }
                .buttonStyle(.plain)
            }
            weekCard
            monthCard
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("今天")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.mutedInk)

            if todayVolumeML <= 0 {
                Text("今天还没记")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DesignSystem.primaryInk)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(DashboardGlanceBuilder.formatMLNumber(todayVolumeML))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignSystem.primaryInk)
                        .monospacedDigit()
                    Text("ml")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DesignSystem.primaryInk)
                }
                .padding(.top, 2)
                Text(DashboardGlanceBuilder.formatStandardDrinks(todayStandard))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignSystem.mutedInk)
                    .padding(.top, 2)
            }

            if let session = lastEndedSession, lastSessionIsToday {
                Divider().background(DesignSystem.separator).padding(.vertical, 14)
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    LastSessionRow(session: session, showsDate: false)
                }
                .buttonStyle(.plain)
            }
        }
        .sipCard()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.mutedInk)
            if weekVolumeML <= 0 {
                Text("本周还没记")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DesignSystem.primaryInk)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(DashboardGlanceBuilder.formatMLNumber(weekVolumeML)) ml")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(DesignSystem.primaryInk)
                            .monospacedDigit()
                        Text("·")
                            .foregroundStyle(DesignSystem.muted2)
                        Text(DashboardGlanceBuilder.formatStandardDrinks(weekStandard))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DesignSystem.primaryInk)
                    }
                    Spacer(minLength: 8)
                    Text("\(weekSessionCount) 场")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.mutedInk)
                }
                if !mix.isEmpty {
                    DrinkMixBar(shares: mix)
                        .padding(.top, 4)
                    HStack(spacing: 14) {
                        ForEach(mix) { share in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(share.color)
                                    .frame(width: 7, height: 7)
                                Text("\(share.title) \(share.percentLabel)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(DesignSystem.primaryInk)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .sipCard()
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本月")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.mutedInk)
            HStack(alignment: .top) {
                monthColumn(value: "\(monthSessionCount)", label: "场次")
                Spacer()
                monthColumn(value: "\(monthPlaceCount)", label: "个地方")
                if showSpend {
                    Spacer()
                    monthColumn(value: UserPreferences.formatYuan(fen: monthSpendFen), label: "花费")
                }
            }
            .padding(.top, 4)
            if let topBrand, !topBrand.isEmpty {
                HStack {
                    Text("常喝")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.mutedInk)
                    Spacer()
                    Text(DashboardGlanceBuilder.shortenedDisplayName(topBrand))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.primaryInk)
                        .lineLimit(1)
                }
                .padding(.top, 4)
            }
        }
        .sipCard()
    }

    private func monthColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(DesignSystem.primaryInk)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(DesignSystem.mutedInk)
        }
        .frame(minWidth: 70)
    }
}

struct LastSessionRow: View {
    let session: DrinkSessionEntity
    var showsDate: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DesignSystem.successSoft)
                    .frame(width: 26, height: 26)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesignSystem.success)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("上一场已结束")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignSystem.primaryInk)
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.mutedInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("查看 / 分享")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.burgundy)
        }
    }

    private var logs: [DrinkLogEntity] {
        Array((session.logs as? Set<DrinkLogEntity>) ?? [])
    }

    private var summary: String {
        let volume = logs.reduce(0.0) { $0 + $1.volumeMl }
        var text = ""
        if showsDate, let end = session.endedAt ?? session.startedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            text += formatter.string(from: end) + " · "
        }
        text += "\(logs.count) 杯 · \(DashboardGlanceBuilder.formatMLNumber(volume)) ml"
        return text
    }
}

struct DrinkMixBar: View {
    let shares: [DrinkMixShare]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    share.color
                        .frame(width: max(4, geo.size.width * share.fraction))
                }
            }
        }
        .frame(height: 7)
        .clipShape(Capsule())
    }
}

struct DrinkMixShare: Equatable, Identifiable {
    let title: String
    let fraction: Double
    let category: DrinkCategory?

    var id: String { title }
    var color: Color {
        if let category { return DesignSystem.color(for: category) }
        return DesignSystem.muted2
    }
    var percentLabel: String {
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
        let mix: [DrinkMixShare]
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

        let mix = foldedMix(from: weekByCategory)
        let topMonthCategory = monthByCategory.sorted { $0.value > $1.value }.first?.key
        let topBrand = monthByBrand.sorted { $0.value > $1.value }.first?.key
        let topWeek = mix.first?.category

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

    /// At most two segments: if more than two types are present, keep the
    /// largest share and fold the rest into 「其他」.
    static func foldedMix(from weekByCategory: [DrinkCategory: Double]) -> [DrinkMixShare] {
        let total = weekByCategory.values.reduce(0, +)
        guard total > 0 else { return [] }
        let ranked = weekByCategory.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        guard !ranked.isEmpty else { return [] }
        if ranked.count <= 2 {
            return ranked.map {
                DrinkMixShare(title: $0.key.displayName, fraction: $0.value / total, category: $0.key)
            }
        }
        let top = ranked[0]
        let rest = ranked.dropFirst().reduce(0.0) { $0 + $1.value }
        return [
            DrinkMixShare(title: top.key.displayName, fraction: top.value / total, category: top.key),
            DrinkMixShare(title: "其他", fraction: rest / total, category: .other)
        ]
    }

    /// Drop a purely generic qualifier such as 「（通用）」.
    static func shortenedDisplayName(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["（通用）", "(通用)"] where result.hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func formatMLNumber(_ ml: Double) -> String {
        ml == ml.rounded() ? "\(Int(ml))" : String(format: "%.0f", ml)
    }

    static func formatStandardDrinks(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value)) 标饮"
        }
        return String(format: "%.1f 标饮", value)
    }

    static func isOnLocalDay(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }
}
