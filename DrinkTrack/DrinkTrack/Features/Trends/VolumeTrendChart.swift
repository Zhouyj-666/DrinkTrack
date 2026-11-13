import SwiftUI
import Charts

/// FR-TREND-02：饮酒量趋势——分酒种类堆叠图，可切换「原始 ml」/「标准饮品数」两套单位，
/// 以及周/月/3个月/年四个时间范围。
/// 分类颜色固定按 DrinkCategory 的枚举顺序取色（DesignSystem.color(for:)），
/// 不会因为某天某种类目数据多少而重新排序配色（Color follows the entity, never its rank）。
struct VolumeTrendChart: View {
    let logs: [DrinkLogEntity]
    @State private var unit: Unit = .standardDrinks
    @State private var range: TrendRange = .quarter

    enum Unit: String, CaseIterable { case ml = "原始 ml", standardDrinks = "标准饮品数" }

    private struct StackedPoint: Identifiable {
        var id: String { "\(bucketStart.timeIntervalSince1970)-\(category.rawValue)" }
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
                BarMark(x: .value("日期", point.bucketStart, unit: range.bucket), y: .value("数量", point.value))
                    .foregroundStyle(by: .value("种类", point.category.displayName))
            }
            .chartForegroundStyleScale(domain: DrinkCategory.allCases.map(\.displayName),
                                        range: DrinkCategory.allCases.map { DesignSystem.color(for: $0) })
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
            .frame(height: 180)
            .chartLegend(position: .bottom, spacing: 8)

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

    private var xDomain: ClosedRange<Date> {
        ChartDateDomain.range(for: range)
    }

    private var axisPlan: TrendAxisPlan {
        TrendAxisPlan.plan(for: range, domain: xDomain)
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
        let calendar = Calendar.current
        let component = range.bucket
        let grouped = Dictionary(grouping: logsInWindow) { log -> Date in
            let timestamp = log.timestamp ?? Date()
            return calendar.dateInterval(of: component, for: timestamp)?.start ?? calendar.startOfDay(for: timestamp)
        }
        var result: [StackedPoint] = []
        for (bucketStart, bucketLogs) in grouped {
            let byCategory = Dictionary(grouping: bucketLogs) { $0.category ?? "" }
            for (rawCategory, categoryLogs) in byCategory {
                guard let category = DrinkCategory(rawValue: rawCategory) else { continue }
                let value: Double
                if unit == .ml {
                    value = categoryLogs.reduce(0) { $0 + $1.volumeMl }
                } else {
                    value = categoryLogs.reduce(0) { $0 + $1.standardDrinks }
                }
                result.append(StackedPoint(bucketStart: bucketStart, category: category, value: value))
            }
        }
        return result.sorted {
            if $0.bucketStart != $1.bucketStart { return $0.bucketStart < $1.bucketStart }
            return (DrinkCategory.allCases.firstIndex(of: $0.category) ?? 0) < (DrinkCategory.allCases.firstIndex(of: $1.category) ?? 0)
        }
    }
}
