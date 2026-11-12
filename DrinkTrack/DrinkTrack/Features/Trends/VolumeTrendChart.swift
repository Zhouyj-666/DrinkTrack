import SwiftUI
import Charts

/// FR-TREND-02：饮酒量趋势——分酒种类堆叠图，顶部 Tab 切换「原始 ml」/「标准饮品数」两套单位。
/// 分类颜色固定按 DrinkCategory 的枚举顺序取色（DesignSystem.color(for:)），
/// 不会因为某天某种类目数据多少而重新排序配色（dataviz skill：Color follows the entity, never its rank）。
struct VolumeTrendChart: View {
    let logs: [DrinkLogEntity]
    @State private var unit: Unit = .standardDrinks

    enum Unit: String, CaseIterable { case ml = "原始 ml", standardDrinks = "标准饮品数" }

    private struct StackedPoint: Identifiable {
        var id: String { "\(day.timeIntervalSince1970)-\(category.rawValue)" }
        let day: Date
        let category: DrinkCategory
        let value: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("饮酒量趋势").font(.headline)
                Spacer()
                Picker("", selection: $unit) {
                    ForEach(Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Chart(stackedPoints) { point in
                BarMark(x: .value("日期", point.day, unit: .day), y: .value("数量", point.value))
                    .foregroundStyle(by: .value("种类", point.category.displayName))
            }
            .chartForegroundStyleScale(domain: DrinkCategory.allCases.map(\.displayName),
                                        range: DrinkCategory.allCases.map { DesignSystem.color(for: $0) })
            .frame(height: 180)
            .chartLegend(position: .bottom, spacing: 8)

            if unit == .standardDrinks {
                Text("标准饮品数可跨酒种类直接比较总量（§6.6，10g 纯酒精 = 1 标准饮品）")
                    .font(.caption2).foregroundStyle(DesignSystem.mutedInk)
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var stackedPoints: [StackedPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logs) { log in
            calendar.startOfDay(for: log.timestamp)
        }
        var result: [StackedPoint] = []
        for (day, dayLogs) in grouped {
            let byCategory = Dictionary(grouping: dayLogs) { $0.category }
            for (rawCategory, categoryLogs) in byCategory {
                guard let category = DrinkCategory(rawValue: rawCategory) else { continue }
                let value = unit == .ml
                    ? categoryLogs.reduce(0) { $0 + $1.volumeMl }
                    : categoryLogs.reduce(0) { $0 + $1.standardDrinks }
                result.append(StackedPoint(day: day, category: category, value: value))
            }
        }
        return result.sorted { $0.day < $1.day }
    }
}
