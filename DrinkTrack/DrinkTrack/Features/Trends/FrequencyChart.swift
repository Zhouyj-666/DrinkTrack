import SwiftUI
import Charts

/// FR-TREND-01：每日饮酒量——周/月/3个月/年视图的饮酒量条形图，并用饮酒天数作为频率摘要。
/// 周、月、3个月按天出柱；年视图按月汇总，否则 365 根柱子会挤成细线。
struct FrequencyChart: View {
    let logs: [DrinkLogEntity]
    var now: Date = Date()
    var calendar: Calendar = .current
    @State private var range: TrendRange = .month

    private struct BucketTotal: Identifiable {
        var id: Date { start }
        let start: Date
        let totalML: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每日饮酒量").font(.headline)
            TrendRangePicker(selection: $range)

            Chart(bucketTotals) { item in
                BarMark(x: .value("日期", item.start, unit: range.bucket), y: .value("总量(ml)", item.totalML))
                    .foregroundStyle(DesignSystem.heartRateLine)
                    .cornerRadius(3)
            }
            // Pin the visible domain to the selected calendar window. Without an
            // explicit domain, SwiftUI Charts picks a "nice" Date scale — often
            // hours — and a single short session's bar stretches across the axis.
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: axisPlan.values) { _ in
                    AxisGridLine().foregroundStyle(DesignSystem.gridline)
                    AxisTick().foregroundStyle(DesignSystem.gridline)
                    AxisValueLabel(format: axisPlan.format, centered: axisPlan.centered)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(DesignSystem.gridline)
                    AxisValueLabel().foregroundStyle(DesignSystem.mutedInk)
                }
            }
            .frame(height: 160)

            Text("共 \(drinkingDayCount) 个饮酒日 · \(range.bucketCaption) · 单位 ml")
                .font(.caption)
                .foregroundStyle(DesignSystem.secondaryInk)
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var xDomain: ClosedRange<Date> {
        ChartDateDomain.range(for: range, now: now, calendar: calendar)
    }

    private var axisPlan: TrendAxisPlan {
        TrendAxisPlan.plan(for: range, domain: xDomain, calendar: calendar)
    }

    private var logsInWindow: [DrinkLogEntity] {
        let domain = xDomain
        return logs.filter { log in
            guard let timestamp = log.timestamp else { return false }
            return timestamp >= domain.lowerBound && timestamp < domain.upperBound
        }
    }

    private var drinkingDayCount: Int {
        let calendar = calendar
        return Set(logsInWindow.compactMap { $0.timestamp.map { calendar.startOfDay(for: $0) } }).count
    }

    private var bucketTotals: [BucketTotal] {
        let calendar = calendar
        let component = range.bucket
        let grouped = Dictionary(grouping: logsInWindow) { log -> Date in
            let timestamp = log.timestamp ?? Date()
            return calendar.dateInterval(of: component, for: timestamp)?.start ?? calendar.startOfDay(for: timestamp)
        }
        return grouped.map { start, bucketLogs in
            BucketTotal(start: start, totalML: bucketLogs.reduce(0.0) { $0 + $1.volumeMl })
        }
        .sorted { $0.start < $1.start }
    }
}
