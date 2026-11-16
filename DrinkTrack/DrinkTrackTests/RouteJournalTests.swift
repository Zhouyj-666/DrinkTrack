import XCTest
@testable import DrinkTrack

final class RouteJournalTests: XCTestCase {
    func testStopsOrderAndPolylineIncludeRevisits() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 20))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 21))!
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 19))!

        let stops = RouteJournal.stops(
            sessions: [
                (id: "s1", name: "三里屯", startedAt: day1, latitude: 39.93, longitude: 116.45, volumeML: 500, standardDrinks: 2),
                (id: "s2", name: "家里", startedAt: day2, latitude: 39.90, longitude: 116.40, volumeML: 330, standardDrinks: 1),
                (id: "s3", name: "三里屯", startedAt: day3, latitude: 39.93, longitude: 116.45, volumeML: 200, standardDrinks: 0.8),
                (id: "s4", name: "仅名称", startedAt: day3, latitude: nil, longitude: nil, volumeML: 100, standardDrinks: 0.4)
            ],
            placeMarks: [
                (id: "m1", name: "江边", markedAt: calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 18))!, latitude: 31.23, longitude: 121.47)
            ]
        )

        XCTAssertEqual(stops.map(\.name), ["三里屯", "江边", "家里", "三里屯"])
        XCTAssertEqual(RouteJournal.polylineCoordinates(from: stops).count, 4)
        XCTAssertEqual(RouteJournal.uniquePlaceCount(in: stops), 3)

        let pins = RouteJournal.numberedPins(from: stops)
        XCTAssertEqual(pins.map(\.number), [1, 2, 3])
        XCTAssertEqual(pins.map(\.stop.name), ["三里屯", "江边", "家里"])
        // Latest coordinate for 三里屯 still the revisit.
        XCTAssertEqual(pins.first?.stop.id, "session-s3")
    }

    func testTimeRangeFilter() {
        let calendar = Calendar(identifier: .gregorian)
        var cal = calendar
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        cal.firstWeekday = 2 // Monday, matching zh_CN
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!

        let stops = RouteJournal.stops(
            sessions: [
                (id: "old", name: "A", startedAt: cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 20))!, latitude: 1, longitude: 1, volumeML: 1, standardDrinks: 1),
                (id: "month", name: "B", startedAt: cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 20))!, latitude: 2, longitude: 2, volumeML: 1, standardDrinks: 1),
                (id: "week", name: "C", startedAt: cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10))!, latitude: 3, longitude: 3, volumeML: 1, standardDrinks: 1)
            ],
            placeMarks: []
        )

        XCTAssertEqual(RouteJournal.filter(stops, range: .all, now: now, calendar: cal).count, 3)
        XCTAssertEqual(RouteJournal.filter(stops, range: .month, now: now, calendar: cal).map(\.name), ["B", "C"])
        XCTAssertEqual(RouteJournal.filter(stops, range: .week, now: now, calendar: cal).map(\.name), ["C"])
    }

    func testPlaceMarkKindIsNotSession() {
        let stops = RouteJournal.stops(
            sessions: [],
            placeMarks: [
                (id: "m1", name: "公园", markedAt: Date(), latitude: 30, longitude: 120)
            ]
        )
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops[0].kind, .placeMark)
        XCTAssertEqual(stops[0].volumeML, 0)
    }

    @MainActor
    func testPlaceMarkDoesNotCountAsDrinkSession() {
        let controller = PersistenceController(inMemory: true)
        let repo = DrinkRepository(context: controller.viewContext)
        let mark = repo.addPlaceMark(name: "公园", latitude: 31.23, longitude: 121.47)
        XCTAssertNotNil(mark)
        XCTAssertEqual(repo.fetchAllSessions().count, 0)
        let stops = repo.routeStops()
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops.first?.kind, .placeMark)
        XCTAssertEqual(stops.first?.name, "公园")
        let summaries = repo.placeSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.sessionCount, 0)
        XCTAssertEqual(summaries.first?.name, "公园")
        XCTAssertTrue(summaries.first?.hasCoordinate ?? false)
    }
}