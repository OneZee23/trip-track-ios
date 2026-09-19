import Foundation
import CoreLocation

/// Из линии маршрута — поездка, вписанная рукой (0.8.0, «Плюс»).
///
/// Чистая функция, и это не эстетика: здесь единственное место в приложении,
/// где километры и время поездки берутся НЕ у GPS, а у человека. Проверять
/// такое открытым экраном значит не проверять вовсе — тот же довод, по
/// которому `AutoTripPolicy` и `JourneyEditSheet.startBounds` вынесены из
/// своих экранов.
///
/// Три правила, которые здесь держатся, записаны в CLAUDE.md и нарушаются
/// молча:
///
/// 1. **Расстояние считает `TripDistanceGate.totalDistance`, и только оно.**
///    Соблазн взять `MKRoute.distance` («сервер Apple уже посчитал») велик, а
///    цена его — второй счёт километров в приложении: `MKRoute.distance`
///    считает по СВОЕЙ геометрии, а одометр поездки, статистика, атлас и
///    уровень машины будут потом набираться пятиметровым шагом по тем точкам,
///    которые легли в базу. Разойдясь однажды, эти два числа не сойдутся
///    никогда — ровно та поломка, из-за которой в 0.6.5 четыре подсчёта
///    свели в один.
/// 2. **Время равномерно, скорость постоянна.** Придумывать ускорения и
///    пробки значило бы придумывать данные: у вписанной рукой поездки нет
///    ни одного измерения, и единственная честная форма трека — та, которая
///    не утверждает ничего сверх «выехал тогда-то, ехал столько-то».
///    Отсюда же `maxSpeed == averageSpeed`: максимума здесь нет, и печатать
///    вместо него выдуманное число нельзя (экран поездки плитку «макс.» у
///    такой поездки не показывает вовсе).
/// 3. **`elevation` — ноль, а не догадка.** Высоту `MKRoute` не везёт, а
///    «набрал 0 м» честнее, чем набор, посчитанный по рельефу, которого мы не
///    видели.
enum ManualTripBuilder {

    /// Что человек набрал в листе. Всё, кроме координат, приходит с экрана
    /// как есть — сборка не правит ни дату, ни длительность: границы полей
    /// стоят в листе, а здесь стоит отказ.
    struct Draft {
        var coordinates: [CLLocationCoordinate2D]
        var startDate: Date
        var duration: TimeInterval
        var vehicleId: UUID?
        var title: String?

        init(coordinates: [CLLocationCoordinate2D], startDate: Date,
             duration: TimeInterval, vehicleId: UUID? = nil, title: String? = nil) {
            self.coordinates = coordinates
            self.startDate = startDate
            self.duration = duration
            self.vehicleId = vehicleId
            self.title = title
        }
    }

    /// Нижняя граница длительности. Минута — не «красивое число»: короче неё
    /// поездка попадает под `Trip.isJunk` (<500 м И <2 мин) и была бы удалена
    /// автоматикой сразу после создания.
    static let minimumDuration: TimeInterval = 60
    /// Верхняя — сутки. Дальше начинается путешествие, а оно в приложении уже
    /// есть и собирается из поездок (`Journey`, 0.6.6).
    static let maximumDuration: TimeInterval = 24 * 3600

    /// Быстрее этого маршрут не проезжается — и это НЕ вкусовое ограничение.
    ///
    /// `TripDistanceGate` отбрасывает отрезок, подразумевающий больше
    /// 300 км/ч, как телепорт GPS. Поставь человек на стокилометровый маршрут
    /// десять минут — гейт выбросил бы КАЖДЫЙ отрезок, и в базу легла бы
    /// поездка на ноль километров: молча, без единой ошибки, и дальше её
    /// забрал бы фильтр мусорных. Поэтому нижняя граница длительности зависит
    /// от длины маршрута, а лист не даёт опустить её ниже — собирай так, чтобы
    /// перевернуть было НЕЛЬЗЯ (то же правило, что у
    /// `JourneyEditSheet.startBounds`).
    static func feasibleDuration(forRouteMetres metres: Double) -> TimeInterval {
        max(minimumDuration, metres / maxPlausibleAverage)
    }

    /// 50 м/с — 180 км/ч. Не «примерно как у гейта, только поменьше»: гейт
    /// судит КАЖДЫЙ отрезок, а отрезки линии `MKDirections` неравной длины
    /// (в развязке точки густые, на трассе редкие), и средняя ровно на пороге
    /// означала бы, что половина отрезков его перешагнула. Запас в полтора
    /// раза покрывает эту неравномерность, а поездки быстрее 180 км/ч в
    /// среднем на дорогах не бывает.
    static let maxPlausibleAverage: Double = 50

    /// `nil` значит «собрать не из чего»: меньше двух точек или неположительная
    /// длительность. Отказ, а не поездка нулевой длины, — такую пришлось бы
    /// потом отличать от настоящей на каждом экране.
    static func build(_ draft: Draft) -> Trip? {
        let coords = draft.coordinates
        guard coords.count > 1, draft.duration > 0 else { return nil }

        let endDate = draft.startDate.addingTimeInterval(draft.duration)
        let stamps = timestamps(count: coords.count,
                                startDate: draft.startDate,
                                duration: draft.duration)

        // Километры — ТЕМ ЖЕ шагом, которым их набирает живая запись и которым
        // их потом пересчитает всё остальное. См. правило 1 в шапке.
        let distance = TripDistanceGate.totalDistance(
            zip(coords, stamps).map {
                TripDistanceGate.Sample(latitude: $0.0.latitude,
                                        longitude: $0.0.longitude,
                                        timestamp: $0.1)
            }
        )
        let speed = distance / draft.duration

        var points: [TrackPoint] = []
        points.reserveCapacity(coords.count)
        for (index, coord) in coords.enumerated() {
            points.append(TrackPoint(
                latitude: coord.latitude,
                longitude: coord.longitude,
                altitude: 0,
                speed: speed,
                course: course(at: index, in: coords),
                // Точность у выдуманной точки не «пять метров» и не ноль, а
                // отсутствует. `-1` — то же, чем `CoreLocation` отвечает на
                // «координата есть, а за точность не ручаюсь».
                horizontalAccuracy: -1,
                timestamp: stamps[index]
            ))
        }

        let trimmed = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = (trimmed?.isEmpty == false) ? trimmed : nil

        return Trip(
            startDate: draft.startDate,
            endDate: endDate,
            distance: distance,
            // Максимум равен средней: см. правило 2. Ноль здесь был бы хуже —
            // его читают как «не измерили», а не как «постоянная».
            maxSpeed: speed,
            averageSpeed: speed,
            trackPoints: points,
            title: named,
            titleIsCustom: named != nil,
            elevation: 0,
            // Как и записанная: приватная, пока владелец не решит иначе.
            isPrivate: true,
            vehicleId: draft.vehicleId,
            source: .manual
        )
    }

    /// Равномерно от старта до финиша. Последняя точка попадает ровно в
    /// конец — иначе длительность поездки и последняя её отметка времени
    /// разошлись бы на шаг, и `trimmedEndDate` подрезал бы хвост у поездки,
    /// у которой хвоста нет.
    static func timestamps(count: Int, startDate: Date, duration: TimeInterval) -> [Date] {
        guard count > 1 else { return [startDate] }
        let step = duration / Double(count - 1)
        return (0..<count).map { startDate.addingTimeInterval(Double($0) * step) }
    }

    /// Курс — на следующую точку; у последней он повторяет предыдущий.
    /// `-1` («неизвестен») оставлять нельзя: курс читают места
    /// (`PlacePass.course`) и стрелка машинки на реплее.
    private static func course(at index: Int, in coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count > 1 else { return -1 }
        let i = min(index, coords.count - 2)
        return bearing(from: coords[i], to: coords[i + 1])
    }

    private static func bearing(from: CLLocationCoordinate2D,
                                to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}
