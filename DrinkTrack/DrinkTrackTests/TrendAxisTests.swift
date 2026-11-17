import XCTest
@testable import DrinkTrack

final class TrendAxisTests: XCTestCase {
    private func shanghaiCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func dayKeys(_ dates: [Date], calendar: Calendar) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d"
        return dates.map { formatter.string(from: $0) }
    }

    func testWeekWindowIncludesTodayJustAfterLocalMidnight() {
        let calendar = shanghaiCalendar()
        let now = date(2026, 11, 17, 1, 50, calendar: calendar)
        let domain = ChartDateDomain.range(for: .week, now: now, calendar: calendar)
        let plan = TrendAxisPlan.plan(for: .week, domain: domain, calendar: calendar)
        let buckets = ChartDateDomain.bucketStarts(for: .week, now: now, calendar: calendar)

        XCTAssertEqual(calendar.startOfDay(for: domain.lowerBound), date(2026, 11, 11, 0, calendar: calendar))
        XCTAssertEqual(domain.upperBound, date(2026, 11, 18, 0, calendar: calendar))
        XCTAssertEqual(dayKeys(plan.values, calendar: calendar), ["11/11", "11/12", "11/13", "11/14", "11/15", "11/16", "11/17"])
        XCTAssertEqual(dayKeys(buckets, calendar: calendar), ["11/11", "11/12", "11/13", "11/14", "11/15", "11/16", "11/17"])
    }

    func testWeekWindowIncludesTodayAt1034EvenWithNoDrinks() {
        // Matches the 17 Nov 2026 10:34 Asia/Shanghai screenshot: today must
        // still appear as the last week bucket when it has 0 ml.
        let calendar = shanghaiCalendar()
        let now = date(2026, 11, 17, 10, 34, calendar: calendar)
        let buckets = ChartDateDomain.bucketStarts(for: .week, now: now, calendar: calendar)
        let plan = TrendAxisPlan.plan(
            for: .week,
            domain: ChartDateDomain.range(for: .week, now: now, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(dayKeys(buckets, calendar: calendar), ["11/11", "11/12", "11/13", "11/14", "11/15", "11/16", "11/17"])
        XCTAssertEqual(dayKeys(plan.values, calendar: calendar).last, "11/17")
        XCTAssertEqual(buckets.last, calendar.startOfDay(for: now))

        let drinksOn: Set<Date> = [
            date(2026, 11, 15, 20, calendar: calendar),
            date(2026, 11, 16, 21, calendar: calendar)
        ].reduce(into: Set<Date>()) { $0.insert(calendar.startOfDay(for: $1)) }
        let padded = buckets.map { start in (start, drinksOn.contains(start) ? 1.0 : 0.0) }
        XCTAssertEqual(padded.last?.0, calendar.startOfDay(for: now))
        XCTAssertEqual(padded.last?.1, 0)
        XCTAssertEqual(padded.count, 7)
    }

    func testWeekWindowLastDayIsStillYesterdayJustBeforeMidnight() {
        let calendar = shanghaiCalendar()
        let now = date(2026, 11, 16, 23, 59, 59, calendar: calendar)
        let domain = ChartDateDomain.range(for: .week, now: now, calendar: calendar)
        let plan = TrendAxisPlan.plan(for: .week, domain: domain, calendar: calendar)
        let buckets = ChartDateDomain.bucketStarts(for: .week, now: now, calendar: calendar)

        XCTAssertEqual(calendar.startOfDay(for: domain.lowerBound), date(2026, 11, 10, 0, calendar: calendar))
        XCTAssertEqual(domain.upperBound, date(2026, 11, 17, 0, calendar: calendar))
        XCTAssertEqual(dayKeys(plan.values, calendar: calendar), ["11/10", "11/11", "11/12", "11/13", "11/14", "11/15", "11/16"])
        XCTAssertEqual(dayKeys(buckets, calendar: calendar), ["11/10", "11/11", "11/12", "11/13", "11/14", "11/15", "11/16"])
    }

    func testWeekWindowRollsAtLocalMidnightWithoutCustomCutoff() {
        let calendar = shanghaiCalendar()
        let atMidnight = date(2026, 11, 17, 0, 0, 0, calendar: calendar)
        let justAfter = date(2026, 11, 17, 0, 0, 1, calendar: calendar)
        let fourAM = date(2026, 11, 17, 4, 0, 0, calendar: calendar)
        let morning = date(2026, 11, 17, 10, 34, calendar: calendar)

        for now in [atMidnight, justAfter, fourAM, morning] {
            let domain = ChartDateDomain.range(for: .week, now: now, calendar: calendar)
            let plan = TrendAxisPlan.plan(for: .week, domain: domain, calendar: calendar)
            let buckets = ChartDateDomain.bucketStarts(for: .week, now: now, calendar: calendar)
            XCTAssertEqual(dayKeys(plan.values, calendar: calendar).last, "11/17", "now=\(now)")
            XCTAssertEqual(dayKeys(buckets, calendar: calendar).last, "11/17", "now=\(now)")
            XCTAssertEqual(plan.values.count, 7)
            XCTAssertEqual(buckets.count, 7)
        }
    }

    func testLocalCalendarDoesNotUseUTCDayAfterShanghaiMidnight() {
        let calendar = shanghaiCalendar()
        // 2026-11-17 01:50 in Shanghai is still 2026-11-16 17:50 UTC.
        let now = date(2026, 11, 17, 1, 50, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: now), 17)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(utc.component(.day, from: now), 16)

        let domain = ChartDateDomain.range(for: .week, now: now, calendar: calendar)
        let plan = TrendAxisPlan.plan(for: .week, domain: domain, calendar: calendar)
        XCTAssertEqual(dayKeys(plan.values, calendar: calendar).last, "11/17")
    }

    func testLogsOnNewLocalDayAreInsideWeekWindow() {
        let calendar = shanghaiCalendar()
        let now = date(2026, 11, 17, 1, 50, calendar: calendar)
        let domain = ChartDateDomain.range(for: .week, now: now, calendar: calendar)
        let logAt0150 = now
        XCTAssertTrue(logAt0150 >= domain.lowerBound && logAt0150 < domain.upperBound)
    }
    func testPlotModelWeekCategoryDomainEndsTodayWhenLastDrinkWasYesterday() {
        // The array actually passed to chartXScale(domain:). Unit tests of
        // bucketStarts/axis plan can pass while Date-unit BarMarks still clip
        // today after a last drink on 11/16.
        let calendar = shanghaiCalendar()
        let now = date(2026, 11, 17, 10, 34, calendar: calendar)
        let model = TrendChartPlotModel.make(for: .week, now: now, calendar: calendar)

        XCTAssertEqual(model.categoryDomain, [
            "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14",
            "2026-11-15", "2026-11-16", "2026-11-17"
        ])
        XCTAssertEqual(model.axisTexts, ["11/11", "11/12", "11/13", "11/14", "11/15", "11/16", "11/17"])
        XCTAssertEqual(model.axisTexts.last, "11/17")
        XCTAssertEqual(model.buckets.last?.start, calendar.startOfDay(for: now))
        XCTAssertEqual(model.tickIDs.last, "2026-11-17")
        XCTAssertEqual(model.tickIDs.count, 7)

        let lastDrinkDay = calendar.startOfDay(for: date(2026, 11, 16, 21, calendar: calendar))
        let totals = model.buckets.map { bucket -> Double in
            bucket.start == lastDrinkDay ? 330 : 0
        }
        XCTAssertEqual(totals, [0, 0, 0, 0, 0, 330, 0])
        XCTAssertEqual(model.categoryDomain.last, "2026-11-17")
    }

    func testPlotModelMonthAndQuarterKeepTrailingEmptyToday() {
        let calendar = shanghaiCalendar()
        let now = date(2026, 11, 17, 10, 34, calendar: calendar)
        for range in [TrendRange.month, .quarter] {
            let model = TrendChartPlotModel.make(for: range, now: now, calendar: calendar)
            XCTAssertEqual(model.categoryDomain.last, "2026-11-17", "range=\(range.rawValue)")
            XCTAssertEqual(model.buckets.last?.start, calendar.startOfDay(for: now), "range=\(range.rawValue)")
        }

        // Month buckets stay labeled M/d, including a trailing empty today.
        let month = TrendChartPlotModel.make(for: .month, now: now, calendar: calendar)
        XCTAssertEqual(month.axisTexts.last, "11/17")

        // Quarter axis labels are month names ("9月 10月 11月"), not M/d.
        let quarter = TrendChartPlotModel.make(for: .quarter, now: now, calendar: calendar)
        XCTAssertEqual(quarter.axisTexts.last, "11月")
    }

    func testPlotModelYearKeepsCurrentMonthCategory() {
        let calendar = shanghaiCalendar()
        let now = date(2026, 11, 17, 10, 34, calendar: calendar)
        let model = TrendChartPlotModel.make(for: .year, now: now, calendar: calendar)
        XCTAssertEqual(model.categoryDomain.count, 12)
        XCTAssertEqual(model.categoryDomain.last, "2026-11")
        XCTAssertEqual(model.axisTexts.last, "11月")
    }
}
