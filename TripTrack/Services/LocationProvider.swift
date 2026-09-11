import Foundation
import CoreLocation
import Combine

/// Унифицированные данные о позиции
struct LocationUpdate {
    let coordinate: CLLocationCoordinate2D
    let speed: CLLocationSpeed // м/с
    /// Градусы, 0 = север. `nil` — курс неизвестен, и это НЕ ноль.
    ///
    /// До 0.6.7 здесь стояло `location.course >= 0 ? location.course : 0`, то
    /// есть «не знаю» превращалось в «строго на север». Разницу было не видно,
    /// пока курс никто не показывал: маркер был видом сбоку и умел только
    /// зеркалиться. Маркер сверху показал бы её сразу — машина на парковке
    /// демонстративно смотрит на север. И тихо портилось не только это:
    /// `toCLLocation()` отдаёт эти данные фильтру Калмана, а тот отличает
    /// известный курс от неизвестного ровно по знаку и с нулём считал выдумку
    /// за настоящее измерение.
    let course: CLLocationDirection?
    let altitude: CLLocationDistance // метры
    let timestamp: Date
    let horizontalAccuracy: CLLocationAccuracy

    /// Создать из CLLocation
    static func from(_ location: CLLocation) -> LocationUpdate {
        LocationUpdate(
            coordinate: location.coordinate,
            speed: max(0, location.speed),
            course: location.course >= 0 ? location.course : nil,
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
            // −1 — это язык CoreLocation для «курс неизвестен»; его и понимают
            // все, кто читает эти точки дальше.
            course: course ?? -1,
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
