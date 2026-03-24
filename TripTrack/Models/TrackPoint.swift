import Foundation
import CoreLocation

struct TrackPoint: Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double // m/s
    let course: Double // degrees
    let horizontalAccuracy: Double
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var speedKmh: Double {
        speed * 3.6
    }

    init(id: UUID = UUID(), latitude: Double, longitude: Double, altitude: Double = 0,
         speed: Double = 0, course: Double = -1, horizontalAccuracy: Double = 0,
         timestamp: Date = Date()) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    init(id: UUID = UUID(), location: CLLocation) {
        self.id = id
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.speed = max(0, location.speed)
        self.course = location.course
        self.horizontalAccuracy = location.horizontalAccuracy
        self.timestamp = location.timestamp
    }
}
