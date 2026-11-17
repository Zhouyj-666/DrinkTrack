import SwiftUI
import Charts

/// FR-TREND-02：饮酒量趋势——分酒种类堆叠图，可切换「原始 ml」/「标准饮品数」两套单位，
/// 以及周/月/3个月/年四个时间范围。
/// 分类颜色固定按 DrinkCategory 的枚举顺序取色（DesignSystem.color(for:)），
/// 不会因为某天某种类目数据多少而重新排序配色（Color follows the entity, never its rank）。
///
/// X uses the same discrete category domain as 每日饮酒量, so a trailing empty
/// today (or empty trailing days in 月 / 3个月) keeps its slot and tick.
struct VolumeTrendChart: View {
    let logs: [DrinkLogEntity]
    var now: Date = Date()
    var calendar: Calendar = .current
    @State private var unit: Unit = .standardDrinks
    @State private var range: TrendRange = .quarter

    enum Unit: String, CaseIterable { case ml = "原始 ml", standardDrinks = "标准饮品数" }

    private struct StackedPoint: Identifiable {
        var id: String { "\(categoryID)-\(category.rawValue)" }
        let categoryID: String
        let bucketStart: Date
        let category: DrinkCategory
        let value: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("饮酒量趋势").font(.headline)
                Spacer()
                Picker("单位", selection: $unit) {
                    ForEach(Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            TrendRangePicker(selection: $range)

            Chart(stackedPoints) { point in
                BarMark(
                    x: .value("日期", point.categoryID),
                    y: .value("数量", point.value)
                )
                .foregroundStyle(by: .value("种类", point.category.displayName))
            }
            .chartForegroundStyleScale(domain: DrinkCategory.allCases.map(\.displayName),
                                        range: DrinkCategory.allCases.map { DesignSystem.color(for: $0) })
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
            .chartYAxis(position: .leading) {
                AxisMarks(preset: .aligned, position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(DesignSystem.gridline)
                    AxisValueLabel().foregroundStyle(DesignSystem.mutedInk)
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.trailing, 8)
            }
            .frame(height: 180)
            .chartLegend(position: .bottom, spacing: 8)
            .accessibilityIdentifier("volume-chart")

            Text(plotModel.axisTexts.joined(separator: " "))
                .font(.caption2)
                .foregroundStyle(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
                .accessibilityIdentifier("volume-chart-x-domain")
                .accessibilityLabel(plotModel.axisTexts.joined(separator: " "))
                .accessibilityValue(plotModel.axisTexts.joined(separator: " "))
                .allowsHitTesting(false)
                .accessibilityHidden(false)

            Text("\(range.bucketCaption) · \(totalText)")
                .font(.caption)
                .foregroundStyle(DesignSystem.secondaryInk)

            if unit == .standardDrinks {
                Text("标准饮品数可跨酒种类直接比较总量（10g 纯酒精 = 1 标准饮品）")
                    .font(.caption2).foregroundStyle(DesignSystem.mutedInk)
            }
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

    private var totalText: String {
        let window = logsInWindow
        if unit == .ml {
            let total = window.reduce(0.0) { $0 + $1.volumeMl }
            return String(format: "合计 %.0f ml", total)
        }
        let total = window.reduce(0.0) { $0 + $1.standardDrinks }
        return String(format: "合计 ≈%.1f 标准饮品", total)
    }

    private var stackedPoints: [StackedPoint] {
        let calendar = calendar
        let component = range.bucket
        let grouped = Dictionary(grouping: logsInWindow) { log -> Date in
            let timestamp = log.timestamp ?? Date()
            return calendar.dateInterval(of: component, for: timestamp)?.start ?? calendar.startOfDay(for: timestamp)
        }
        var result: [StackedPoint] = []
        for bucket in plotModel.buckets {
            let bucketLogs = grouped[bucket.start] ?? []
            if bucketLogs.isEmpty {
                result.append(StackedPoint(categoryID: bucket.id, bucketStart: bucket.start, category: .other, value: 0))
                continue
            }
            let byCategory = Dictionary(grouping: bucketLogs) { $0.category ?? "" }
            for (rawCategory, categoryLogs) in byCategory {
                guard let category = DrinkCategory(rawValue: rawCategory) else { continue }
                let value: Double
                if unit == .ml {
                    value = categoryLogs.reduce(0) { $0 + $1.volumeMl }
                } else {
                    value = categoryLogs.reduce(0) { $0 + $1.standardDrinks }
                }
                result.append(StackedPoint(categoryID: bucket.id, bucketStart: bucket.start, category: category, value: value))
            }
        }
        return result.sorted {
            if $0.bucketStart != $1.bucketStart { return $0.bucketStart < $1.bucketStart }
            return (DrinkCategory.allCases.firstIndex(of: $0.category) ?? 0) < (DrinkCategory.allCases.firstIndex(of: $1.category) ?? 0)
        }
    }
}
