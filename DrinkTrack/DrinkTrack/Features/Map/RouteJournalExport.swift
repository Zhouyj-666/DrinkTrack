import Foundation

/// A name-only place (no validated coordinates) that can appear on an exported
/// 饮酒地图 list but is never given a invented map position.
struct RouteJournalNameOnlyPlace: Equatable {
    let name: String
    let lastAt: Date?
}

/// Shareable 饮酒地图 payload for the current time-range filter.
///
/// Coordinates may be used in memory to draw a map overview, but this payload
/// and its shareable text/JSON never include latitude or longitude by default.
struct RouteJournalExport: Equatable {
    struct StopItem: Equatable, Identifiable {
        let id: String
        /// Pin number shared by revisits of the same mapped place; nil for name-only.
        let pinNumber: Int?
        let name: String
        let dateText: String
        let kindLabel: String
        let isNameOnly: Bool
    }

    let range: RouteTimeRange
    let rangeTitle: String
    let dateRangeText: String
    let mappedPlaceCount: Int
    let mappedStopCount: Int
    let nameOnlyCount: Int
    let recapLine: String
    let privacyLine: String
    let items: [StopItem]
    /// Always false in this release: export never attaches exact coordinates.
    let includesCoordinates: Bool

    var canExport: Bool { !items.isEmpty }

    var shareTitle: String { "小酌场 饮酒地图" }

    static let defaultPrivacyLine = "分享的饮酒地图默认不含精确坐标。"

    static func build(
        stops: [RouteStop],
        nameOnlyPlaces: [RouteJournalNameOnlyPlace],
        range: RouteTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeCoordinates: Bool = false
    ) -> RouteJournalExport {
        let filteredStops = RouteJournal.filter(stops, range: range, now: now, calendar: calendar)
        let filteredNameOnly = filterNameOnly(nameOnlyPlaces, range: range, now: now, calendar: calendar)
        let pins = RouteJournal.numberedPins(from: filteredStops)
        let pinNumberByName = Dictionary(uniqueKeysWithValues: pins.map { ($0.stop.name, $0.number) })

        var items: [StopItem] = filteredStops.map { stop in
            StopItem(
                id: stop.id,
                pinNumber: pinNumberByName[stop.name],
                name: stop.name,
                dateText: formatDateTime(stop.at),
                kindLabel: stop.kind == .placeMark ? "地点标记" : "饮酒场次",
                isNameOnly: false
            )
        }

        for place in filteredNameOnly {
            items.append(StopItem(
                id: "name-\(place.name)",
                pinNumber: nil,
                name: place.name,
                dateText: place.lastAt.map(formatDateTime) ?? "日期未知",
                kindLabel: "仅名称",
                isNameOnly: true
            ))
        }

        items.sort { lhs, rhs in
            let left = dateForSort(lhs, stops: filteredStops, nameOnly: filteredNameOnly)
            let right = dateForSort(rhs, stops: filteredStops, nameOnly: filteredNameOnly)
            if left != right { return left < right }
            return lhs.name < rhs.name
        }

        let mappedPlaceCount = RouteJournal.uniquePlaceCount(in: filteredStops)
        let nameOnlyCount = filteredNameOnly.count
        return RouteJournalExport(
            range: range,
            rangeTitle: range.title,
            dateRangeText: dateRangeText(range: range, items: items, now: now, calendar: calendar),
            mappedPlaceCount: mappedPlaceCount,
            mappedStopCount: filteredStops.count,
            nameOnlyCount: nameOnlyCount,
            recapLine: recapLine(mappedPlaceCount: mappedPlaceCount, mappedStopCount: filteredStops.count, nameOnlyCount: nameOnlyCount),
            privacyLine: defaultPrivacyLine,
            items: items,
            includesCoordinates: includeCoordinates
        )
    }

    /// Plain-text itinerary for the share sheet. Never includes coordinates.
    var shareableText: String {
        var lines: [String] = [shareTitle, "\(rangeTitle) · \(dateRangeText)", recapLine, ""]
        for item in items {
            let pin = item.pinNumber.map { "\($0). " } ?? "• "
            let extra = item.isNameOnly ? "（图上未标点）" : ""
            lines.append("\(pin)\(item.name)  \(item.dateText)  \(item.kindLabel)\(extra)")
        }
        lines.append("")
        lines.append(privacyLine)
        return lines.joined(separator: "\n")
    }

    /// JSON used by tests and as a description of what is being shared.
    /// Keys never include latitude/longitude; values never embed raw coordinates.
    var shareableJSONString: String {
        var root: [String: Any] = [
            "brand": "小酌场",
            "title": "饮酒地图",
            "range": rangeTitle,
            "dateRange": dateRangeText,
            "mappedPlaceCount": mappedPlaceCount,
            "mappedStopCount": mappedStopCount,
            "nameOnlyCount": nameOnlyCount,
            "recap": recapLine,
            "privacy": privacyLine,
            "includesCoordinates": includesCoordinates
        ]
        root["stops"] = items.map { item -> [String: Any] in
            var dict: [String: Any] = [
                "name": item.name,
                "date": item.dateText,
                "kind": item.kindLabel,
                "nameOnly": item.isNameOnly
            ]
            if let pin = item.pinNumber {
                dict["pin"] = pin
            }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func emptyHint(hasAnyData: Bool, range: RouteTimeRange) -> String {
        if !hasAnyData {
            return "还没有可导出的饮酒地图。先标记地点，或在记酒时加上地点。"
        }
        if range == .all {
            return "还没有可导出的饮酒地图。先标记地点，或在记酒时加上地点。"
        }
        return "这个时间范围里还没有可导出的内容，可切换到「全部」看看。"
    }

    // MARK: - Helpers

    private static func filterNameOnly(
        _ places: [RouteJournalNameOnlyPlace],
        range: RouteTimeRange,
        now: Date,
        calendar: Calendar
    ) -> [RouteJournalNameOnlyPlace] {
        guard let start = range.startDate(now: now, calendar: calendar) else {
            return places
        }
        return places.filter { place in
            guard let lastAt = place.lastAt else { return false }
            return lastAt >= start
        }
    }

    private static func recapLine(mappedPlaceCount: Int, mappedStopCount: Int, nameOnlyCount: Int) -> String {
        var parts: [String] = []
        if mappedStopCount > 0 {
            parts.append("走过 \(mappedPlaceCount) 个地方 · \(mappedStopCount) 次停留")
        }
        if nameOnlyCount > 0 {
            parts.append("\(nameOnlyCount) 个仅名称地点")
        }
        if parts.isEmpty {
            return "还没有饮酒地图足迹"
        }
        return parts.joined(separator: " · ")
    }

    private static func dateRangeText(
        range: RouteTimeRange,
        items: [StopItem],
        now: Date,
        calendar: Calendar
    ) -> String {
        switch range {
        case .week:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
                let end = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
                return "\(formatDay(interval.start)) – \(formatDay(end))"
            }
            return range.title
        case .month:
            return formatMonth(now, calendar: calendar)
        case .all:
            if let first = items.first, let last = items.last {
                if first.dateText == last.dateText { return first.dateText }
                let firstDay = dayPortion(of: first.dateText)
                let lastDay = dayPortion(of: last.dateText)
                if firstDay == lastDay { return firstDay }
                return "\(firstDay) – \(lastDay)"
            }
            return "全部"
        }
    }

    private static func dateForSort(
        _ item: StopItem,
        stops: [RouteStop],
        nameOnly: [RouteJournalNameOnlyPlace]
    ) -> Date {
        if let stop = stops.first(where: { $0.id == item.id }) {
            return stop.at
        }
        if let place = nameOnly.first(where: { $0.name == item.name }) {
            return place.lastAt ?? .distantFuture
        }
        return .distantFuture
    }

    private static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    private static func formatMonth(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("yMMM")
        return formatter.string(from: date)
    }

    private static func dayPortion(of formatted: String) -> String {
        // "2026年11月16日 10:00" → "2026年11月16日"
        if let space = formatted.firstIndex(of: " ") {
            return String(formatted[..<space])
        }
        return formatted
    }
}
