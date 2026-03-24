import Foundation
import CoreLocation
import Combine

/// Унифицированные данные о позиции
struct LocationUpdate {
    let coordinate: CLLocationCoordinate2D
    let speed: CLLocationSpeed // м/с
    let course: CLLocationDirection // градусы, 0 = север
    let altitude: CLLocationDistance // метры
    let timestamp: Date
    let horizontalAccuracy: CLLocationAccuracy

    /// Создать из CLLocation
    static func from(_ location: CLLocation) -> LocationUpdate {
        LocationUpdate(
            coordinate: location.coordinate,
            speed: max(0, location.speed),
            course: location.course >= 0 ? location.course : 0,
            altitude: location.altitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy
        )
    }

    /// Создать CLLocation из LocationUpdate
    func toCLLocation() -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 0,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }
}

/// Протокол источника позиции
protocol LocationProviding {
    var currentLocation: LocationUpdate? { get }
    var locationPublisher: AnyPublisher<LocationUpdate, Never> { get }
    
    func start()
    func stop()
}
