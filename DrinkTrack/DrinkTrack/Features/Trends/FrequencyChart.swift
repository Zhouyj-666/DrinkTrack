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
            // Pin the visible domain to the selected calendar window (week / month
            // / year). Without an explicit domain, SwiftUI Charts picks a "nice"
            // Date scale — often hours — and a single short session's bar can
            // stretch across several hours on the axis.
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: xStride, count: 1)) { _ in
                    AxisGridLine().foregroundStyle(DesignSystem.gridline)
                    AxisValueLabel(format: xLabelFormat, centered: true)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
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

    private var xDomain: ClosedRange<Date> {
        ChartDateDomain.range(for: range)
    }

    private var xStride: Calendar.Component {
        switch range {
        case .week: return .day
        case .month: return .weekOfYear
        case .year: return .month
        }
    }

    private var xLabelFormat: Date.FormatStyle {
        if range == .year {
            return .dateTime.month(.abbreviated)
        }
        return .dateTime.month(.defaultDigits).day()
    }

    private var dailyTotals: [DayTotal] {
        let calendar = Calendar.current
        let cutoff = xDomain.lowerBound
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

/// Shared visible-window helper for the trends date axes.
enum ChartDateDomain {
    static func range(for frequencyRange: FrequencyChart.Range, now: Date = Date()) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now.addingTimeInterval(86400)
        let start: Date
        switch frequencyRange {
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        case .month:
            start = calendar.date(byAdding: .month, value: -1, to: todayStart) ?? todayStart
        case .year:
            start = calendar.date(byAdding: .year, value: -1, to: todayStart) ?? todayStart
        }
        return start...end
    }

    /// Last three months through the end of today, matching TrendsView's log window.
    static func lastThreeMonths(now: Date = Date()) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now.addingTimeInterval(86400)
        let start = calendar.date(byAdding: .month, value: -3, to: todayStart) ?? todayStart
        return start...end
    }
}
