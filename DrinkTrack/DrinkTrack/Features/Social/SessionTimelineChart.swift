import SwiftUI
import Charts

/// Time-axis chart for a single drinking session.
///
/// The x-axis domain is the session's real start...end (with a little padding).
/// A session that only lasted a few seconds must plot as a few seconds — never
/// as a multi-hour default window, which is what SwiftUI Charts will invent
/// when you leave the Date scale to automatic "nice" hours.
struct SessionTimelineChart: View {
    let session: DrinkSessionEntity

    private var logs: [DrinkLogEntity] {
        ((session.logs as? Set<DrinkLogEntity>) ?? []).sorted {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }
    }

    private var start: Date {
        session.startedAt ?? logs.first?.timestamp ?? Date()
    }

    private var end: Date {
        if let endedAt = session.endedAt, endedAt > start { return endedAt }
        if let lastLog = logs.last?.timestamp, lastLog > start { return lastLog }
        // Active session with no later event: use now, but never invent hours
        // of empty axis when the session only just started.
        let now = Date()
        return now > start ? now : start.addingTimeInterval(1)
    }

    private var domain: ClosedRange<Date> {
        let duration = max(end.timeIntervalSince(start), 1)
        // 10% padding on each side, with a floor so a 5s session still has
        // a readable axis (about 1 second of padding, not 2 hours).
        let padding = max(1, duration * 0.1)
        return start.addingTimeInterval(-padding)...end.addingTimeInterval(padding)
    }

    private var durationText: String {
        UserPreferences.formatDuration(end.timeIntervalSince(start))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本场时间轴").font(.headline)
                Spacer()
                Text("时长 \(durationText)")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }

            Chart {
                ForEach(logs, id: \.objectID) { log in
                    if let timestamp = log.timestamp {
                        PointMark(
                            x: .value("时间", timestamp),
                            y: .value("记录", 1)
                        )
                        .foregroundStyle(DesignSystem.heartRateLine)
                        .symbolSize(60)
                        .annotation(position: .top) {
                            Text(categoryLabel(for: log))
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.secondaryInk)
                        }
                    }
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...2)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: axisValues) { value in
                    AxisGridLine().foregroundStyle(DesignSystem.gridline)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Self.tickFormatter(for: domain).string(from: date))
                                .foregroundStyle(DesignSystem.mutedInk)
                        }
                    }
                }
            }
            .frame(height: 120)

            if logs.isEmpty {
                Text("这场会话还没有饮酒记录。")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var axisValues: [Date] {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let steps = 4
        let step = span / Double(steps)
        return (0...steps).map { domain.lowerBound.addingTimeInterval(Double($0) * step) }
    }

    private static func tickFormatter(for domain: ClosedRange<Date>) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        if span < 120 {
            formatter.dateFormat = "HH:mm:ss"
        } else if span < 24 * 3600 {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MM/dd HH:mm"
        }
        return formatter
    }

    private func categoryLabel(for log: DrinkLogEntity) -> String {
        guard let raw = log.category, let category = DrinkCategory(rawValue: raw) else { return "记录" }
        return category.displayName
    }
}
