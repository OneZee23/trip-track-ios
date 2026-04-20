import Foundation

struct TrackPointPayload: Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let course: Double
    let horizontalAccuracy: Double
    let timestamp: Date
    let isInterpolated: Bool
}

extension TrackPointPayload {
    init(_ p: TrackPoint) {
        self.init(
            id: p.id,
            latitude: p.latitude,
            longitude: p.longitude,
            altitude: p.altitude,
            speed: p.speed,
            course: p.course,
            horizontalAccuracy: p.horizontalAccuracy,
            timestamp: p.timestamp,
            isInterpolated: p.isInterpolated
        )
    }

    func toTrackPoint() -> TrackPoint {
        TrackPoint(id: id, latitude: latitude, longitude: longitude,
                   altitude: altitude, speed: speed, course: course,
                   horizontalAccuracy: horizontalAccuracy, timestamp: timestamp,
                   isInterpolated: isInterpolated)
    }
}
