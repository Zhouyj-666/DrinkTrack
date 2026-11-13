import SwiftUI

/// FR-SOC-03：分享饮酒打卡。生成可分享卡片：本场摘要 + 可选心率走势 + 可选地点。
///
/// 分享边界（§6.1）：
/// - 心率只画走势线，不画坐标轴和数值；而且只取**这一场时间段内**的心率点。
/// - 花费永远不上卡片；地点默认不显示，用户在详情页手动打开才显示。
struct ShareCardView: View {
    let session: DrinkSessionEntity
    let includeHeartRateCurve: Bool
    var showLocation: Bool = false
    @EnvironmentObject private var healthKitManager: HealthKitManager

    /// 渲染成图片时用的固定宽度，保证分享出去的图片比例稳定。
    static let renderWidth: CGFloat = 360

    private var logs: [DrinkLogEntity] {
        ((session.logs as? Set<DrinkLogEntity>) ?? []).sorted {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }
    }

    private var start: Date { session.startedAt ?? logs.first?.timestamp ?? Date() }

    private var end: Date {
        if let endedAt = session.endedAt, endedAt > start { return endedAt }
        if session.status == "active" { return max(Date(), start) }
        return logs.last?.timestamp ?? start
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if showLocation, let place = session.locationName, !place.isEmpty {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }

            statsRow

            if !categorySummary.isEmpty {
                categoryChips
            }

            if !logs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(logs.prefix(6), id: \.objectID) { log in
                        logLine(log)
                    }
                    if logs.count > 6 {
                        Text("……还有 \(logs.count - 6) 杯")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                }
            }

            if includeHeartRateCurve, sessionHeartRates.count >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    TrendOnlySparkline(points: sessionHeartRates)
                        .frame(height: 44)
                    Text("本场心率走势（只展示走势，不展示具体数值）")
                        .font(.caption2).foregroundStyle(DesignSystem.mutedInk)
                }
            }

            Text(DisclaimerStrings.passiveAlertDisclaimer)
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.gridline))
        .padding()
    }

    private var header: some View {
        HStack(alignment: .top) {
            Image(systemName: "wineglass.fill")
                .font(.title2)
                .foregroundStyle(DesignSystem.heartRateLine)
            VStack(alignment: .leading, spacing: 2) {
                Text("DrinkTrack 饮酒打卡").font(.headline)
                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }
            Spacer()
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(value: UserPreferences.formatDuration(end.timeIntervalSince(start)), title: "时长")
            stat(value: "\(logs.count)", title: "杯数")
            stat(value: "\(Int(logs.reduce(0.0) { $0 + $1.volumeMl }))ml", title: "总量")
            stat(value: String(format: "%.1f", logs.reduce(0.0) { $0 + $1.standardDrinks }), title: "标准饮品")
        }
        .padding(.vertical, 10)
        .background(DesignSystem.pagePlane)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func stat(value: String, title: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var categoryChips: some View {
        HStack(spacing: 6) {
            ForEach(categorySummary, id: \.category) { entry in
                Text("\(entry.category.emoji) \(entry.category.displayName) ×\(entry.count)")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(DesignSystem.color(for: entry.category).opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private func logLine(_ log: DrinkLogEntity) -> some View {
        let category = log.category.flatMap(DrinkCategory.init(rawValue:)) ?? .other
        return HStack(spacing: 6) {
            Text(category.emoji)
            Text(log.brand.flatMap { $0.isEmpty ? nil : $0 } ?? category.displayName)
                .lineLimit(1)
            Text("\(Int(log.volumeMl))ml")
                .foregroundStyle(DesignSystem.secondaryInk)
            Spacer()
            if let timestamp = log.timestamp {
                Text(timestamp, format: .dateTime.hour().minute())
                    .foregroundStyle(DesignSystem.mutedInk)
            }
        }
        .font(.footnote)
    }

    private struct CategoryCount {
        let category: DrinkCategory
        let count: Int
    }

    private var categorySummary: [CategoryCount] {
        let grouped = Dictionary(grouping: logs) { log -> DrinkCategory in
            log.category.flatMap(DrinkCategory.init(rawValue:)) ?? .other
        }
        var result: [CategoryCount] = []
        for category in DrinkCategory.allCases {
            if let items = grouped[category], !items.isEmpty {
                result.append(CategoryCount(category: category, count: items.count))
            }
        }
        return Array(result.prefix(4))
    }

    private var timeRangeText: String {
        let dateText = start.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated))
        let startText = start.formatted(.dateTime.hour().minute())
        let endText = end.formatted(.dateTime.hour().minute())
        return "\(dateText) \(startText)–\(endText)"
    }

    /// 只取本场时间段内的心率点（前后各留 10 分钟），不拿别的时间的数据冒充本场。
    private var sessionHeartRates: [Double] {
        let lower = start.addingTimeInterval(-600)
        let upper = end.addingTimeInterval(600)
        return healthKitManager.recentHeartRatePoints
            .filter { $0.timestamp >= lower && $0.timestamp <= upper }
            .map(\.value)
    }
}

/// 不带坐标轴/刻度的纯趋势折线，专用于分享卡片（故意不暴露精确数值）。
private struct TrendOnlySparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = points.max() ?? 1
            let minV = points.min() ?? 0
            let span = max(maxV - minV, 1)
            Path { path in
                for (index, value) in points.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let y = geo.size.height * (1 - CGFloat((value - minV) / span))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(DesignSystem.heartRateLine, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}
