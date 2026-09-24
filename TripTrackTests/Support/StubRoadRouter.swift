import Foundation
import CoreLocation
@testable import TripTrack

/// Маршрутизатор-заглушка: сеть на симуляторе мертва, а тест обязан быть
/// детерминированным (спека §2.7).
final class StubRoadRouter: RoadRouter {
    var answer: (CLLocationCoordinate2D, CLLocationCoordinate2D) throws -> RoadRoute
    private(set) var calls = 0

    init(_ answer: @escaping (CLLocationCoordinate2D, CLLocationCoordinate2D) throws -> RoadRoute) {
        self.answer = answer
    }

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> RoadRoute {
        calls += 1
        return try answer(from, to)
    }

    /// Прямая «дорога» на 10 % длиннее прямой, минута езды — правдоподобна
    /// для любой дыры стенда.
    static func straightLine() -> StubRoadRouter {
        StubRoadRouter { a, b in
            let metres = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            return RoadRoute(coordinates: [a, b], distance: metres * 1.1, expectedTravelTime: 60)
        }
    }
}
