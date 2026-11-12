import SwiftUI
import Charts

/// FR-TREND-01：饮酒频率——周/月/年视图的饮酒天数条形图 + 单日总剂量标注。
struct FrequencyChart: View {
    let logs: [DrinkLogEntity]
    @State private var range: Range = .month

    enum Range: String, CaseIterable { case week = "周", month = "月", year = "年" }

    private struct DayTotal: Identifiable {
        var id: Date { day }
        let day: Date
        let totalML: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("饮酒频率").font(.headline)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            Chart(dailyTotals) { item in
                BarMark(x: .value("日期", item.day, unit: .day), y: .value("总量(ml)", item.totalML))
                    .foregroundStyle(DesignSystem.heartRateLine)
                    .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(DesignSystem.gridline)
                    AxisValueLabel().foregroundStyle(DesignSystem.mutedInk)
                }
            }
            .frame(height: 160)

            Text("共 \(dailyTotals.count) 个饮酒日").font(.caption).foregroundStyle(DesignSystem.secondaryInk)
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dailyTotals: [DayTotal] {
        let calendar = Calendar.current
        let cutoff: Date = {
            switch range {
            case .week: return calendar.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            case .month: return calendar.date(byAdding: .month, value: -1, to: Date()) ?? .distantPast
            case .year: return calendar.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
            }
        }()
        let filtered = logs.filter { log in
            guard let timestamp = log.timestamp else { return false }
            return timestamp >= cutoff
        }
        let grouped = Dictionary(grouping: filtered) { log in
            calendar.startOfDay(for: log.timestamp ?? cutoff)
        }
        var totals: [DayTotal] = []
        for (day, dayLogs) in grouped {
            let totalML = dayLogs.reduce(0.0) { partial, log in
                partial + log.volumeMl
            }
            totals.append(DayTotal(day: day, totalML: totalML))
        }
        return totals.sorted { $0.day < $1.day }
    }
}
