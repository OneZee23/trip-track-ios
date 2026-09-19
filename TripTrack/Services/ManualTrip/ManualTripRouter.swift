import Foundation
import MapKit

/// Что может пойти не так при прокладке маршрута — типом, а не строкой.
///
/// Строка от Apple («The operation couldn't be completed») в лист не
/// показывается никогда: она приезжает на языке системы, а не приложения, и
/// ничего не советует. Экран берёт из этого перечисления свою фразу через
/// `AppStrings`, а сам текст ошибки уходит только в лог.
enum ManualTripRouteError: Error, Equatable {
    /// Между точками нет автомобильной дороги — острова, встречные берега,
    /// точка посреди озера.
    case noRoute
    /// Сеть. `MKDirections` без интернета отвечает именно этим, и это
    /// единственная ошибка, которую имеет смысл повторить той же кнопкой.
    case offline
    /// Промежуточных точек больше, чем разрешено. См. `maxViaPoints`.
    case tooManyStops
    /// Всё остальное. Текст Apple — в `debugDescription`, на экран не идёт.
    case failed(String)
}

/// Маршрут по дорогам между двумя точками — то, из чего собирается вписанная
/// рукой поездка.
///
/// `MKDirections` не умеет промежуточных точек вовсе: путь через три остановки
/// — это четыре отдельных запроса, склеенных встык. Склейка живёт здесь, а не
/// в листе, потому что у неё есть правило, которое надо помнить: конец плеча и
/// начало следующего — ОДНА И ТА ЖЕ точка, и повторять её в линии нельзя.
/// Дубль координаты сам по себе безвреден (пятиметровый шаг одометра его
/// проглотит), а вот у сборки трека он даёт две точки с разным временем в
/// одном месте — то есть стоянку там, где машина не останавливалась.
enum ManualTripRouter {

    /// Три — потолок из спеки §2. Не техническое ограничение: четвёртая
    /// остановка это уже не «заехал по дороге», а другой маршрут, и рисовать
    /// его надо отдельной поездкой.
    static let maxViaPoints = 3

    /// Линия маршрута и то, что о нём думает Apple.
    ///
    /// `appleDistance` и `expectedTravelTime` НЕ идут в поездку: расстояние
    /// считает `TripDistanceGate` по точкам (см. `ManualTripBuilder`), время
    /// набирает человек. Первое здесь для сверки в тестах, второе — чтобы лист
    /// мог ПРЕДЛОЖИТЬ длительность, которую человек тут же вправе переписать.
    struct Route {
        let coordinates: [CLLocationCoordinate2D]
        let appleDistance: Double
        let expectedTravelTime: TimeInterval
    }

    /// Плечи считаются последовательно, а не пачкой: `MKDirections` — сетевой
    /// сервис Apple с троттлингом, и четыре одновременных запроса от одного
    /// приложения он отвечает отказом чаще, чем четыре подряд.
    static func route(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        via: [CLLocationCoordinate2D] = []
    ) async throws -> Route {
        guard via.count <= maxViaPoints else { throw ManualTripRouteError.tooManyStops }

        let stops = [start] + via + [end]
        var coordinates: [CLLocationCoordinate2D] = []
        var distance: Double = 0
        var travelTime: TimeInterval = 0

        for index in 0..<(stops.count - 1) {
            let leg = try await leg(from: stops[index], to: stops[index + 1])
            let points = leg.polyline.coordinates
            // Стык плеч — одна точка на двоих. См. шапку типа.
            coordinates.append(contentsOf: coordinates.isEmpty ? points : Array(points.dropFirst()))
            distance += leg.distance
            travelTime += leg.expectedTravelTime
        }

        guard coordinates.count > 1 else { throw ManualTripRouteError.noRoute }
        return Route(coordinates: coordinates,
                     appleDistance: distance,
                     expectedTravelTime: travelTime)
    }

    private static func leg(
        from: CLLocationCoordinate2D, to: CLLocationCoordinate2D
    ) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        // «По дорогам» — весь смысл функции: прямая между двумя точками у нас
        // уже есть, и она никому не нужна.
        request.transportType = .automobile
        // Один маршрут: выбирать из трёх человеку здесь нечем — он вписывает
        // поездку, которая уже состоялась, а не планирует её.
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { throw ManualTripRouteError.noRoute }
            return route
        } catch let error as ManualTripRouteError {
            throw error
        } catch let error as NSError {
            throw translate(error)
        }
    }

    /// Ошибки MapKit — в наши три. Разбор по коду, а не по тексту: текст
    /// приходит на языке системы и меняется от версии к версии.
    static func translate(_ error: NSError) -> ManualTripRouteError {
        if error.domain == NSURLErrorDomain { return .offline }
        if error.domain == MKErrorDomain {
            switch MKError.Code(rawValue: UInt(max(0, error.code))) {
            case .loadingThrottled, .serverFailure:
                return .offline
            case .placemarkNotFound, .directionsNotFound:
                return .noRoute
            default:
                break
            }
        }
        return .failed(error.localizedDescription)
    }
}

extension MKPolyline {
    /// Координаты полилинии массивом. `getCoordinates(_:range:)` пишет в
    /// заранее выделенный буфер — единственный способ достать их из MapKit.
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
