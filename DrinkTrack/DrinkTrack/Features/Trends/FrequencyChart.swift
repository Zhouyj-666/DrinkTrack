import SwiftUI
import Charts

/// FR-TREND-01：每日饮酒量——周/月/3个月/年视图的饮酒量条形图，并用饮酒天数作为频率摘要。
/// 周、月、3个月按天出柱；年视图按月汇总，否则 365 根柱子会挤成细线。
///
/// X is a discrete category domain (`chartXScale(domain: plotModel.categoryDomain)`),
/// not a Date-unit BarMark. A continuous Date scale plus trailing 0-ml placeholders
/// still let Swift Charts clip today after the last real bar, and a right-side
/// Y-axis could hide the last tick. Every bucket, including today at 0 ml, now
/// keeps a slot; the Y-axis sits on the leading/left side.
struct FrequencyChart: View {
    let logs: [DrinkLogEntity]
    var now: Date = Date()
    var calendar: Calendar = .current
    @State private var range: TrendRange = .month

    private struct BucketTotal: Identifiable {
        var id: String { categoryID }
        let categoryID: String
        let start: Date
        let totalML: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每日饮酒量").font(.headline)
            TrendRangePicker(selection: $range)

            Chart(bucketTotals) { item in
                BarMark(
                    x: .value("日期", item.categoryID),
                    y: .value("总量(ml)", item.totalML)
                )
                .foregroundStyle(DesignSystem.heartRateLine)
                .cornerRadius(3)
            }
            .chartXScale(
                domain: plotModel.categoryDomain,
                range: .plotDimension(startPadding: 4, endPadding: 12)
            )
            .chartXAxis {
                AxisMarks(values: plotModel.tickIDs) { value in
                    AxisGridLine().foregroundStyle(DesignSystem.gridline)
                    AxisTick().foregroundStyle(DesignSystem.gridline)
                    AxisValueLabel {
                        if let id = value.as(String.self), let text = plotModel.axisText(for: id) {
                            Text(text)
                        }
                    }
                    .foregroundStyle(DesignSystem.mutedInk)
                }
            }
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(DesignSystem.gridline)
                    AxisValueLabel().foregroundStyle(DesignSystem.mutedInk)
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.trailing, 8)
            }
            .frame(height: 160)
            .accessibilityIdentifier("frequency-chart")

            Text(plotModel.axisTexts.joined(separator: " "))
                .font(.caption2)
                .foregroundStyle(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
                .accessibilityIdentifier("frequency-chart-x-domain")
                .accessibilityLabel(plotModel.axisTexts.joined(separator: " "))
                .accessibilityValue(plotModel.axisTexts.joined(separator: " "))
                .allowsHitTesting(false)
                .accessibilityHidden(false)

            Text("共 \(drinkingDayCount) 个饮酒日 · \(range.bucketCaption) · 单位 ml")
                .font(.caption)
                .foregroundStyle(DesignSystem.secondaryInk)
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var plotModel: TrendChartPlotModel {
        TrendChartPlotModel.make(for: range, now: now, calendar: calendar)
    }

    private var xDomain: ClosedRange<Date> {
        ChartDateDomain.range(for: range, now: now, calendar: calendar)
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
        return plotModel.buckets.map { bucket in
            BucketTotal(
                categoryID: bucket.id,
                start: bucket.start,
                totalML: grouped[bucket.start]?.reduce(0.0) { $0 + $1.volumeMl } ?? 0
            )
        }
    }
}
