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


    func testExportPayloadOmitsCoordinatesByDefault() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 21))!
        // Distinctive values that must never appear in the shareable payload.
        let latitude = 39.934567
        let longitude = 116.456789
        let stops = RouteJournal.stops(
            sessions: [
                (id: "s1", name: "三里屯", startedAt: day, latitude: latitude, longitude: longitude, volumeML: 330, standardDrinks: 1)
            ],
            placeMarks: []
        )
        let payload = RouteJournalExport.build(
            stops: stops,
            nameOnlyPlaces: [RouteJournalNameOnlyPlace(name: "巷子酒馆", lastAt: day)],
            range: .all,
            now: day,
            calendar: calendar
        )
        XCTAssertTrue(payload.canExport)
        XCTAssertFalse(payload.includesCoordinates)
        let blob = payload.shareableText + "\n" + payload.shareableJSONString
        let lowered = blob.lowercased()
        XCTAssertFalse(blob.contains("39.934567"))
        XCTAssertFalse(blob.contains("116.456789"))
        XCTAssertFalse(blob.contains("39.93"))
        XCTAssertFalse(blob.contains("116.45"))
        XCTAssertFalse(lowered.contains("latitude"))
        XCTAssertFalse(lowered.contains("longitude"))
        XCTAssertFalse(lowered.contains("\"lat\""))
        XCTAssertFalse(lowered.contains("\"lon\""))
        XCTAssertTrue(payload.items.contains { $0.name == "三里屯" && $0.pinNumber == 1 && !$0.isNameOnly })
        XCTAssertTrue(payload.items.contains { $0.name == "巷子酒馆" && $0.isNameOnly })
    }

    func testExportAppliesTimeRangeFilter() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        cal.firstWeekday = 2
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let stops = RouteJournal.stops(
            sessions: [
                (id: "old", name: "A", startedAt: cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 20))!, latitude: 1, longitude: 1, volumeML: 1, standardDrinks: 1),
                (id: "month", name: "B", startedAt: cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 20))!, latitude: 2, longitude: 2, volumeML: 1, standardDrinks: 1),
                (id: "week", name: "C", startedAt: cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10))!, latitude: 3, longitude: 3, volumeML: 1, standardDrinks: 1)
            ],
            placeMarks: []
        )
        let nameOnly = [
            RouteJournalNameOnlyPlace(name: "巷子酒馆", lastAt: cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 11))!),
            RouteJournalNameOnlyPlace(name: "过期店", lastAt: cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 19))!)
        ]
        let week = RouteJournalExport.build(stops: stops, nameOnlyPlaces: nameOnly, range: .week, now: now, calendar: cal)
        XCTAssertEqual(week.items.filter { !$0.isNameOnly }.map(\.name), ["C"])
        XCTAssertEqual(week.items.filter(\.isNameOnly).map(\.name), ["巷子酒馆"])
        let month = RouteJournalExport.build(stops: stops, nameOnlyPlaces: nameOnly, range: .month, now: now, calendar: cal)
        XCTAssertEqual(month.items.filter { !$0.isNameOnly }.map(\.name), ["B", "C"])
        XCTAssertEqual(month.items.filter(\.isNameOnly).map(\.name), ["巷子酒馆"])
        let all = RouteJournalExport.build(stops: stops, nameOnlyPlaces: nameOnly, range: .all, now: now, calendar: cal)
        XCTAssertEqual(all.items.filter { !$0.isNameOnly }.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(Set(all.items.filter(\.isNameOnly).map(\.name)), Set(["巷子酒馆", "过期店"]))
    }

    func testExportListsNameOnlyPlacesWithoutFakeCoordinates() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 19))!
        let stops = RouteJournal.stops(
            sessions: [
                (id: "s1", name: "家里", startedAt: day, latitude: 31.230401, longitude: 121.473701, volumeML: 200, standardDrinks: 0.8),
                (id: "s2", name: "仅名称", startedAt: day, latitude: nil, longitude: nil, volumeML: 100, standardDrinks: 0.4)
            ],
            placeMarks: []
        )
        let payload = RouteJournalExport.build(
            stops: stops,
            nameOnlyPlaces: [RouteJournalNameOnlyPlace(name: "仅名称", lastAt: day)],
            range: .all,
            now: day,
            calendar: calendar
        )
        XCTAssertEqual(payload.mappedStopCount, 1)
        XCTAssertEqual(payload.nameOnlyCount, 1)
        let nameOnly = payload.items.first { $0.isNameOnly }
        XCTAssertEqual(nameOnly?.name, "仅名称")
        XCTAssertNil(nameOnly?.pinNumber)
        let mapped = payload.items.first { !$0.isNameOnly }
        XCTAssertEqual(mapped?.name, "家里")
        XCTAssertEqual(mapped?.pinNumber, 1)
        let blob = payload.shareableText + "\n" + payload.shareableJSONString
        XCTAssertFalse(blob.contains("31.230401"))
        XCTAssertFalse(blob.contains("121.473701"))
        XCTAssertTrue(blob.contains("图上未标点"))
    }

    func testEmptyExportCannotShare() {
        let payload = RouteJournalExport.build(stops: [], nameOnlyPlaces: [], range: .all)
        XCTAssertFalse(payload.canExport)
        XCTAssertTrue(payload.items.isEmpty)
        XCTAssertFalse(RouteJournalExport.emptyHint(hasAnyData: false, range: .all).isEmpty)
    }

    func testAnnotatedStopsCarryNotesIntoExportWithoutCoordinates() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 20))!
        let stops = RouteJournal.annotatedStops(
            sessions: [
                (id: "s1", name: "武康路", startedAt: day, latitude: 31.21, longitude: 121.44, volumeML: 150, standardDrinks: 1.2, note: "老酒吧，点了杯威士忌")
            ],
            placeMarks: [
                (id: "m1", name: "江边", markedAt: day, latitude: 31.23, longitude: 121.47, note: "看见江景")
            ]
        )
        XCTAssertEqual(stops.map(\.note), ["老酒吧，点了杯威士忌", "看见江景"])
        let payload = RouteJournalExport.build(stops: stops, nameOnlyPlaces: [], range: .all, now: day, calendar: calendar)
        XCTAssertTrue(payload.shareableText.contains("老酒吧，点了杯威士忌"))
        XCTAssertTrue(payload.shareableText.contains("看见江景"))
        XCTAssertTrue(payload.shareableJSONString.contains("老酒吧，点了杯威士忌"))
        let blob = payload.shareableText + "\n" + payload.shareableJSONString
        XCTAssertFalse(blob.contains("31.21"))
        XCTAssertFalse(blob.contains("121.44"))
    }
}
