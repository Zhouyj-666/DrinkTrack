import Foundation
import CoreData
import CoreLocation

/// One unique place name from the user's own logs and sessions.
/// Name-only places (no coordinates) still appear in the list.
struct PlaceSummary: Identifiable {
    var id: String { name }

    let name: String
    let latitude: Double?
    let longitude: Double?
    let sessionCount: Int
    let logCount: Int
    let totalVolumeML: Double
    let totalStandardDrinks: Double
    let lastAt: Date?
    let categoryMix: [(category: DrinkCategory, fraction: Double)]
    let sessions: [DrinkSessionEntity]

    var coordinate: CLLocationCoordinate2D? {
        LocationCoordinate.clLocation(from: LocationCoordinate.validated(latitude: latitude, longitude: longitude))
    }

    var hasCoordinate: Bool { coordinate != nil }
}

/// Mutable builder used by `DrinkRepository.placeSummaries()`.
struct PlaceAccumulator {
    let name: String
    private var latitude: Double?
    private var longitude: Double?
    private var coordinateAt: Date?
    private var sessions: [DrinkSessionEntity] = []
    private var sessionIDs = Set<NSManagedObjectID>()
    private var logCount = 0
    private var totalVolumeML = 0.0
    private var totalStandardDrinks = 0.0
    private var lastAt: Date?
    private var categoryVolumes: [DrinkCategory: Double] = [:]

    init(name: String) {
        self.name = name
    }

    mutating func addSession(_ session: DrinkSessionEntity) {
        guard sessionIDs.insert(session.objectID).inserted else { return }
        sessions.append(session)
    }

    mutating func addLog(_ log: DrinkLogEntity, coordinate: (Double, Double)?) {
        logCount += 1
        totalVolumeML += log.volumeMl
        totalStandardDrinks += log.standardDrinks
        if let timestamp = log.timestamp, timestamp > (lastAt ?? .distantPast) {
            lastAt = timestamp
        }
        if let raw = log.category, let category = DrinkCategory(rawValue: raw) {
            categoryVolumes[category, default: 0] += log.volumeMl
        }
        consider(coordinate: coordinate, at: log.timestamp)
    }

    mutating func consider(coordinate: (Double, Double)?, at date: Date?) {
        guard let coordinate else { return }
        if latitude == nil || (date ?? .distantPast) >= (coordinateAt ?? .distantPast) {
            latitude = coordinate.0
            longitude = coordinate.1
            coordinateAt = date
        }
    }

    /// PlaceMark-only visits: keep the catalog row alive even with zero drink logs.
    mutating func considerMark(coordinate: (Double, Double)?, at date: Date?) {
        consider(coordinate: coordinate, at: date)
        if let date, date > (lastAt ?? .distantPast) {
            lastAt = date
        }
    }

    func summary() -> PlaceSummary {
        let ranked = categoryVolumes.sorted { $0.value > $1.value }
        let total = ranked.reduce(0) { $0 + $1.value }
        let mix = ranked.prefix(3).map { item in
            (category: item.key, fraction: total > 0 ? item.value / total : 0)
        }
        let sortedSessions = sessions.sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
        return PlaceSummary(
            name: name,
            latitude: latitude,
            longitude: longitude,
            sessionCount: sortedSessions.count,
            logCount: logCount,
            totalVolumeML: totalVolumeML,
            totalStandardDrinks: totalStandardDrinks,
            lastAt: lastAt,
            categoryMix: mix,
            sessions: sortedSessions
        )
    }
}
