import Foundation
import CoreData
import CoreLocation
@testable import TripTrack

/// Общий инструмент тестов трека: точки в метрах от одного начала координат,
/// чтобы тесты читались как чертёж. Начало — центр Краснодара, трек
/// синтетический: настоящих поездок владельца в репозитории нет (спека §2.7).
/// Эпоха та же, что у `TrackFidelityTests`.
enum TrackTestKit {
    static let origin = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
    static let metersPerDegree = 111_320.0
    static let epoch = Date(timeIntervalSince1970: 1_780_000_000)

    static func coordinate(east: Double, north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: origin.latitude + north / metersPerDegree,
            longitude: origin.longitude + east / (metersPerDegree * cos(origin.latitude * .pi / 180))
        )
    }

    static func fix(east: Double, north: Double, speed: Double, course: Double = 0,
                    after seconds: TimeInterval, accuracy: Double = 8) -> CLLocation {
        CLLocation(
            coordinate: coordinate(east: east, north: north),
            altitude: 30,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 3,
            course: course,
            speed: speed,
            timestamp: epoch.addingTimeInterval(seconds)
        )
    }

    struct PointSpec {
        var east: Double
        var north: Double
        var seconds: TimeInterval
        var accuracy: Double = 8
        var speed: Double = 10
        var altitude: Double = 30
        var interpolated = false
    }

    /// Готовая поездка в базе — такой её оставил бы финиш.
    @MainActor
    @discardableResult
    static func insertTrip(into pc: PersistenceController, points: [PointSpec],
                           processed: Bool = false,
                           confirmation: TripConfirmation = .confirmed) -> TripEntity {
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        trip.id = UUID()
        trip.startDate = epoch.addingTimeInterval(points.first?.seconds ?? 0)
        trip.endDate = epoch.addingTimeInterval(points.last?.seconds ?? 0)
        trip.isTrackProcessed = processed
        trip.confirmation = confirmation.rawValue
        trip.userId = SettingsManager.shared.localUserId
        for spec in points {
            let p = TrackPointEntity(context: ctx)
            p.id = UUID()
            let c = coordinate(east: spec.east, north: spec.north)
            p.latitude = c.latitude
            p.longitude = c.longitude
            p.altitude = spec.altitude
            p.speed = spec.speed
            p.course = 0
            p.horizontalAccuracy = spec.accuracy
            p.timestamp = epoch.addingTimeInterval(spec.seconds)
            p.isInterpolated = spec.interpolated
            p.trip = trip
        }
        try? ctx.save()
        return trip
    }
}
