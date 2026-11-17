import XCTest
@testable import DrinkTrack

final class DashboardGlanceBuilderTests: XCTestCase {
    func testWeekVsLastWeekAndMonthFacts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 18))!
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let lastWeek = calendar.date(byAdding: .day, value: -3, to: startOfWeek)!
        let thisWeek = calendar.date(byAdding: .hour, value: 5, to: startOfWeek)!
        let today = calendar.startOfDay(for: now).addingTimeInterval(10 * 3600)

        let logs: [GlanceLogFact] = [
            GlanceLogFact(timestamp: today, volumeMl: 100, standardDrinks: 1, categoryRaw: DrinkCategory.beer.rawValue, brand: "青岛", amountFen: 2000, locationName: "家里"),
            GlanceLogFact(timestamp: thisWeek, volumeMl: 200, standardDrinks: 2, categoryRaw: DrinkCategory.baijiu.rawValue, brand: "茅台", amountFen: nil, locationName: "三里屯"),
            GlanceLogFact(timestamp: lastWeek, volumeMl: 500, standardDrinks: 4, categoryRaw: DrinkCategory.beer.rawValue, brand: "青岛", amountFen: 1500, locationName: "公司")
        ]
        let sessions: [GlanceSessionFact] = [
            GlanceSessionFact(startedAt: today, locationName: "家里"),
            GlanceSessionFact(startedAt: thisWeek, locationName: "三里屯"),
            GlanceSessionFact(startedAt: lastWeek, locationName: "公司")
        ]

        let metrics = DashboardGlanceBuilder.metrics(logs: logs, sessions: sessions, now: now, calendar: calendar)
        XCTAssertEqual(metrics.todayVolumeML, 100, accuracy: 0.01)
        XCTAssertEqual(metrics.weekVolumeML, 300, accuracy: 0.01)
        XCTAssertEqual(metrics.lastWeekVolumeML, 500, accuracy: 0.01)
        XCTAssertEqual(metrics.weekSessionCount, 2)
        XCTAssertEqual(metrics.monthSessionCount, 3)
        XCTAssertEqual(metrics.monthPlaceCount, 3)
        XCTAssertEqual(metrics.monthSpendFen, 3500)
        XCTAssertEqual(metrics.topBrand, "青岛")
    }

    func testPlaceMarkDoesNotAppearInSessionFacts() {
        // Dashboard session counts come only from GlanceSessionFact inputs.
        // PlaceMarks are never converted into session facts by DrinkRepository.
        let metrics = DashboardGlanceBuilder.metrics(
            logs: [GlanceLogFact](),
            sessions: [GlanceSessionFact](),
            now: Date(),
            calendar: .current
        )
        XCTAssertEqual(metrics.weekSessionCount, 0)
        XCTAssertEqual(metrics.monthSessionCount, 0)
        XCTAssertEqual(metrics.monthPlaceCount, 0)
    }

    func testWeekMixFoldsMoreThanTwoTypesIntoOther() {
        let mix = DashboardGlanceBuilder.foldedMix(from: [
            .beer: 69,
            .riceWine: 20,
            .baijiu: 11
        ])
        XCTAssertEqual(mix.map(\.title), ["啤酒", "其他"])
        XCTAssertEqual(mix[0].fraction, 0.69, accuracy: 0.001)
        XCTAssertEqual(mix[1].fraction, 0.31, accuracy: 0.001)
        XCTAssertEqual(mix[1].title, "其他")
    }

    func testWeekMixKeepsTwoTypesUnchanged() {
        let mix = DashboardGlanceBuilder.foldedMix(from: [
            .beer: 69,
            .riceWine: 31
        ])
        XCTAssertEqual(mix.map(\.title), ["啤酒", "米酒"])
    }

    func testShortenedDisplayNameDropsGenericSuffix() {
        XCTAssertEqual(DashboardGlanceBuilder.shortenedDisplayName("醪糟（通用）"), "醪糟")
        XCTAssertEqual(DashboardGlanceBuilder.shortenedDisplayName("青岛"), "青岛")
    }

    func testFormatYuanOmitsCentsOnWholeAmounts() {
        XCTAssertEqual(UserPreferences.formatYuan(fen: 5000), "¥50")
        XCTAssertEqual(UserPreferences.formatYuan(fen: 5050), "¥50.50")
    }
}

