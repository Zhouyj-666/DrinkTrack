import Foundation
import CoreData
import CoreLocation

/// Optional coordinates stored on a drink log or session.
/// Missing values stay nil; invalid numbers are treated as missing.
enum LocationCoordinate {
    static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite
            && longitude.isFinite
            && latitude >= -90
            && latitude <= 90
            && longitude >= -180
            && longitude <= 180
    }

    static func validated(latitude: Double?, longitude: Double?) -> (Double, Double)? {
        guard let latitude, let longitude, isValid(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return (latitude, longitude)
    }

    static func pair(from object: NSManagedObject) -> (Double, Double)? {
        guard let latitude = (object.value(forKey: "latitude") as? NSNumber)?.doubleValue,
              let longitude = (object.value(forKey: "longitude") as? NSNumber)?.doubleValue else {
            return nil
        }
        return validated(latitude: latitude, longitude: longitude)
    }

    static func apply(_ pair: (Double, Double)?, to object: NSManagedObject) {
        if let pair, isValid(latitude: pair.0, longitude: pair.1) {
            object.setValue(pair.0, forKey: "latitude")
            object.setValue(pair.1, forKey: "longitude")
        } else {
            object.setValue(nil, forKey: "latitude")
            object.setValue(nil, forKey: "longitude")
        }
    }

    static func clLocation(from pair: (Double, Double)?) -> CLLocationCoordinate2D? {
        guard let pair else { return nil }
        return CLLocationCoordinate2D(latitude: pair.0, longitude: pair.1)
    }
}
