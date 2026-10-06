import Foundation
import CoreLocation

struct TrackPoint: Identifiable, Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double // m/s
    let course: Double // degrees
    let horizontalAccuracy: Double
    let timestamp: Date
    let isInterpolated: Bool
    /// Derived from Trip.recordingBreaks, never a second persisted source.
    var recordingSegmentIndex: Int = 0

    private enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, altitude, speed, course
        case horizontalAccuracy, timestamp, isInterpolated
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: UUID = UUID(), latitude: Double, longitude: Double, altitude: Double = 0,
         speed: Double = 0, course: Double = -1, horizontalAccuracy: Double = 0,
         timestamp: Date = Date(), isInterpolated: Bool = false,
         recordingSegmentIndex: Int = 0) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
        self.isInterpolated = isInterpolated
        self.recordingSegmentIndex = recordingSegmentIndex
    }

    init(id: UUID = UUID(), location: CLLocation, isInterpolated: Bool = false) {
        self.id = id
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.speed = max(0, location.speed)
        self.course = location.course
        self.horizontalAccuracy = location.horizontalAccuracy
        self.timestamp = location.timestamp
        self.isInterpolated = isInterpolated
    }

    /// Вправе ли точка двигать одометр — см. `TripDistanceGate.countsForDistance`.
    var countsForDistance: Bool {
        TripDistanceGate.countsForDistance(horizontalAccuracy: horizontalAccuracy,
                                           isInterpolated: isInterpolated)
    }
}
