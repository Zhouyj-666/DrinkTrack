import Foundation
import CoreLocation
import MapKit

/// Time window chips on the 饮酒地图 map.
enum RouteTimeRange: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "本周"
        case .month: return "本月"
        case .all: return "全部"
        }
    }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        case .all:
            return nil
        }
    }
}

/// One chronological stop on the 饮酒地图 route. Revisiting the same place later
/// becomes another stop. PlaceMarks are not drink sessions.
struct RouteStop: Identifiable, Equatable {
    enum Kind: Equatable {
        case session
        case placeMark
    }

    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let at: Date
    let kind: Kind
    let volumeML: Double
    let standardDrinks: Double
    let sessionObjectIDURI: String?
    /// User-written place or session remark (shop name, drink name, short note).
    let note: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Pure builders for the 饮酒地图 map: ordering, filtering, polyline, pin numbers.
enum RouteJournal {
    /// Build chronological stops (oldest → newest) from sessions with coordinates
    /// and from explicit PlaceMark rows. Name-only places never become stops.
    static func stops(
        sessions: [(id: String, name: String?, startedAt: Date?, latitude: Double?, longitude: Double?, volumeML: Double, standardDrinks: Double)],
        placeMarks: [(id: String, name: String, markedAt: Date, latitude: Double, longitude: Double)]
    ) -> [RouteStop] {
        annotatedStops(
            sessions: sessions.map {
                (id: $0.id, name: $0.name, startedAt: $0.startedAt, latitude: $0.latitude, longitude: $0.longitude, volumeML: $0.volumeML, standardDrinks: $0.standardDrinks, note: nil)
            },
            placeMarks: placeMarks.map {
                (id: $0.id, name: $0.name, markedAt: $0.markedAt, latitude: $0.latitude, longitude: $0.longitude, note: nil)
            }
        )
    }

    static func annotatedStops(
        sessions: [(id: String, name: String?, startedAt: Date?, latitude: Double?, longitude: Double?, volumeML: Double, standardDrinks: Double, note: String?)],
        placeMarks: [(id: String, name: String, markedAt: Date, latitude: Double, longitude: Double, note: String?)]
    ) -> [RouteStop] {
        var result: [RouteStop] = []

        for session in sessions {
            guard let name = trimmed(session.name),
                  let startedAt = session.startedAt,
                  let pair = LocationCoordinate.validated(latitude: session.latitude, longitude: session.longitude) else {
                continue
            }
            result.append(RouteStop(
                id: "session-\(session.id)",
                name: name,
                latitude: pair.0,
                longitude: pair.1,
                at: startedAt,
                kind: .session,
                volumeML: session.volumeML,
                standardDrinks: session.standardDrinks,
                sessionObjectIDURI: session.id,
                note: trimmed(session.note)
            ))
        }

        for mark in placeMarks {
            let name = trimmed(mark.name) ?? mark.name
            guard let pair = LocationCoordinate.validated(latitude: mark.latitude, longitude: mark.longitude) else {
                continue
            }
            result.append(RouteStop(
                id: "mark-\(mark.id)",
                name: name,
                latitude: pair.0,
                longitude: pair.1,
                at: mark.markedAt,
                kind: .placeMark,
                volumeML: 0,
                standardDrinks: 0,
                sessionObjectIDURI: nil,
                note: trimmed(mark.note)
            ))
        }

        return result.sorted { $0.at < $1.at }
    }

    static func filter(
        _ stops: [RouteStop],
        range: RouteTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RouteStop] {
        guard let start = range.startDate(now: now, calendar: calendar) else {
            return stops
        }
        return stops.filter { $0.at >= start }
    }

    /// Unique map pins for the current window: latest visit keeps the coordinate,
    /// but the sequence number is the first appearance in chronological order.
    static func numberedPins(from stops: [RouteStop]) -> [(number: Int, stop: RouteStop)] {
        var firstIndex: [String: Int] = [:]
        var latestByName: [String: RouteStop] = [:]
        var order: [String] = []

        for stop in stops {
            if firstIndex[stop.name] == nil {
                firstIndex[stop.name] = order.count + 1
                order.append(stop.name)
            }
            latestByName[stop.name] = stop
        }

        return order.compactMap { name in
            guard let number = firstIndex[name], let stop = latestByName[name] else { return nil }
            return (number, stop)
        }
    }

    static func polylineCoordinates(from stops: [RouteStop]) -> [CLLocationCoordinate2D] {
        stops.map(\.coordinate)
    }

    /// Distinct place names that appear in the filtered stops (for the "走过 N 个地方" line).
    static func uniquePlaceCount(in stops: [RouteStop]) -> Int {
        Set(stops.map(\.name)).count
    }

    static func fitRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return chinaOverviewRegion
        }
        if coordinates.count == 1 {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.7, 0.03)
        let lonDelta = max((maxLon - minLon) * 1.7, 0.03)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }

    /// Default empty-map framing: a China overview so the map is never blank.
    static var chinaOverviewRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.8, longitude: 104.1),
            span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 36)
        )
    }

    private static func trimmed(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}