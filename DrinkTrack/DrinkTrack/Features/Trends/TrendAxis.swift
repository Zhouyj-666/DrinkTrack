import SwiftUI
import Charts

/// 趋势页共用的时间范围。每日饮酒量和饮酒量趋势两张图都用它，
/// 保证同一个范围在两张图上的横轴窗口、柱子粒度和刻度规则完全一致。
enum TrendRange: String, CaseIterable, Identifiable {
    case week = "周"
    case month = "月"
    case quarter = "3个月"
    case year = "年"

    var id: String { rawValue }

    /// 柱子的聚合粒度：一年按天画会是 365 根 1pt 宽的细线，所以年视图按月聚合。
    var bucket: Calendar.Component {
        self == .year ? .month : .day
    }

    var bucketCaption: String {
        self == .year ? "按月汇总" : "按天汇总"
    }
}

/// Visible x-axis windows for the trends charts.
enum ChartDateDomain {
    static func range(for trendRange: TrendRange, now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date> {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now.addingTimeInterval(86400)
        switch trendRange {
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return start...tomorrow
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: todayStart) ?? todayStart
            return start...tomorrow
        case .quarter:
            let start = calendar.date(byAdding: .month, value: -3, to: todayStart) ?? todayStart
            return start...tomorrow
        case .year:
            // Month buckets: align the window to whole months so the first and
            // last bars are not clipped in half.
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? todayStart
            let start = calendar.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
            let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? tomorrow
            return start...end
        }
    }

    /// Oldest date any trends chart can show. TrendsView loads logs from here.
    static func earliestStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        range(for: .year, now: now, calendar: calendar).lowerBound
    }

    /// Start of every visible bucket, including today (or this month in the
    /// year view) even when that bucket has no logs.
    ///
    /// Swift Charts BarMarks that use a Date `unit` will clip trailing empty
    /// categories after the last data point, even when `chartXScale(domain:)`
    /// already extends to tomorrow. A week window on 17 Nov 2026 therefore
    /// showed 11/11–11/16 — mid-range empty days were labeled, but today
    /// (0 ml, after the last bar) disappeared. Callers must emit a 0-value
    /// placeholder for each of these starts.
    static func bucketStarts(for trendRange: TrendRange, now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let domain = range(for: trendRange, now: now, calendar: calendar)
        let step: Calendar.Component = trendRange.bucket
        var result: [Date] = []
        var current = calendar.startOfDay(for: domain.lowerBound)
        if step == .month {
            current = calendar.date(from: calendar.dateComponents([.year, .month], from: domain.lowerBound)) ?? current
        }
        var guardCounter = 0
        while current < domain.upperBound && guardCounter < 400 {
            result.append(current)
            guard let next = calendar.date(byAdding: step, value: 1, to: current) else { break }
            current = next
            guardCounter += 1
        }
        return result
    }
}

/// Explicit x-axis ticks for a trends chart.
///
/// Bug this fixes: the 3-month 饮酒量趋势 chart put a label on every week
/// (8/16 8/23 8/30 ... 11/1), twelve "M/d" labels on a phone-width axis, and
/// they overlapped into an unreadable strip. Instead of letting each chart pick
/// a stride, every range now gets a hand-picked tick set, capped at
/// `maxLabels`, with month names ("9月") once the window is longer than a month.
struct TrendAxisPlan {
    let values: [Date]
    let format: Date.FormatStyle
    /// Center the label inside its bucket (only for day ticks under day bars).
    let centered: Bool

    static let maxLabels = 6

    static func plan(for range: TrendRange, domain: ClosedRange<Date>, calendar: Calendar = .current) -> TrendAxisPlan {
        switch range {
        case .week:
            // 7 day labels such as "11/7" fit comfortably on a phone.
            let days = dates(from: domain.lowerBound, before: domain.upperBound, step: .day, count: 1, calendar: calendar)
            return TrendAxisPlan(values: days, format: .dateTime.month(.defaultDigits).day(), centered: true)
        case .month:
            // Weekly ticks: about 5 labels for a 31-day window.
            let weeks = dates(from: domain.lowerBound, before: domain.upperBound, step: .day, count: 7, calendar: calendar)
            return TrendAxisPlan(values: thin(weeks), format: .dateTime.month(.defaultDigits).day(), centered: false)
        case .quarter:
            // Month starts only ("9月 10月 11月"), never every week.
            let months = monthStarts(in: domain, calendar: calendar)
            return TrendAxisPlan(values: thin(months), format: .dateTime.month(.abbreviated), centered: false)
        case .year:
            // 12 month buckets -> every other month, 6 labels.
            let months = monthStarts(in: domain, calendar: calendar)
            return TrendAxisPlan(values: thin(months), format: .dateTime.month(.abbreviated), centered: false)
        }
    }

    /// Keep at most `maxLabels` values by taking every n-th one.
    static func thin(_ values: [Date], maxLabels: Int = TrendAxisPlan.maxLabels) -> [Date] {
        guard values.count > maxLabels, maxLabels > 0 else { return values }
        let stride = Int((Double(values.count) / Double(maxLabels)).rounded(.up))
        return values.enumerated().compactMap { index, value in
            index % stride == 0 ? value : nil
        }
    }

    private static func dates(from start: Date, before end: Date, step: Calendar.Component, count: Int, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var current = calendar.startOfDay(for: start)
        var guardCounter = 0
        while current < end && guardCounter < 400 {
            result.append(current)
            guard let next = calendar.date(byAdding: step, value: count, to: current) else { break }
            current = next
            guardCounter += 1
        }
        return result
    }

    private static func monthStarts(in domain: ClosedRange<Date>, calendar: Calendar) -> [Date] {
        guard var current = calendar.date(from: calendar.dateComponents([.year, .month], from: domain.lowerBound)) else { return [] }
        if current < domain.lowerBound {
            current = calendar.date(byAdding: .month, value: 1, to: current) ?? domain.upperBound
        }
        var result: [Date] = []
        var guardCounter = 0
        while current < domain.upperBound && guardCounter < 24 {
            result.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
            guardCounter += 1
        }
        return result
    }
}

/// Segmented range picker shared by the trends charts.
struct TrendRangePicker: View {
    @Binding var selection: TrendRange

    var body: some View {
        Picker("时间范围", selection: $selection) {
            ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
