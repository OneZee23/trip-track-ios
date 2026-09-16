import Foundation
import CoreLocation
@testable import TripTrack

/// Треки для матчеров находок — руками, без сидов и без базы.
///
/// Плотность пятиметровая: ровно та, с какой пишется настоящий трек с 0.6.5,
/// и ровно та, на которой порог в 300 метров вообще имеет смысл. На редких
/// точках «проехал в 250 м» решалось бы случайным попаданием точки.
enum DiscoveryTrackFixtures {

    /// Прямая от точки до точки, точка каждые `step` метров.
    static func line(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        step: Double = 5,
        startingAt origin: Date = Date(timeIntervalSince1970: 1_750_000_000),
        altitude: Double = 0,
        secondsPerStep: TimeInterval = 1
    ) -> [TrackPoint] {
        let a = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let b = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let metres = a.distance(from: b)
        let count = max(1, Int((metres / step).rounded(.up)))
        return (0...count).map { i in
            let t = Double(i) / Double(count)
            return TrackPoint(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t,
                altitude: altitude,
                speed: 15,
                timestamp: origin.addingTimeInterval(Double(i) * secondsPerStep)
            )
        }
    }

    /// Смещение координаты на метры: север — плюс по широте, восток — плюс по
    /// долготе.
    static func offset(_ coordinate: CLLocationCoordinate2D, northMetres: Double = 0, eastMetres: Double = 0)
        -> CLLocationCoordinate2D {
        let latitude = coordinate.latitude + northMetres / 111_320
        let longitude = coordinate.longitude
            + eastMetres / (111_320 * cos(coordinate.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
