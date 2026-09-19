import Foundation

/// Треканный пробег машины — сумма поездок, которые она реально проехала.
///
/// Вынесено из `GamificationManager.backfillVehicleOdometers` в чистую функцию
/// по двум причинам: правило «что считать» перестало быть однострочником, и
/// его надо было закрыть тестами. Правило одно, но с исключением:
///
///  - берём поездки, назначенные на эту машину;
///  - **кроме трансферов** — там человек был пассажиром, и наматывать этими
///    километрами чужую машину нельзя. Трансфер обычно и без машины, но флаг
///    проверяется отдельно: машину могли назначить до того, как поездку
///    пометили трансфером.
///
/// **Считается в метрах, делится один раз в конце.** Складывать километры по
/// поездкам — значит складывать двести уже округлённых чисел; в метрах
/// округления нет вовсе, а делить на тысячу можно и в самом конце. Ровно так
/// же устроен пересчёт в `TripRepository.recomputeOdometers`, и расходиться
/// этим двум нельзя: они считают ОДНО число.
///
/// Километры на выходе — потому что в километрах живёт `Vehicle.odometerKm`, и
/// против него уже записаны уровни машин в базе. Это НАГРАДНОЕ число, на
/// экран оно идёт только через `Measure.odometer(km:)`.
enum VehicleOdometer {
    static func tracked(from trips: [Trip], vehicleId: UUID) -> Double {
        let metres = trips.reduce(into: 0.0) { sum, trip in
            guard trip.vehicleId == vehicleId, !trip.isTransfer else { return }
            sum += trip.distance
        }
        return metres / 1000
    }

    /// Пробеги сразу по всем машинам — один проход вместо N.
    static func trackedByVehicle(from trips: [Trip]) -> [UUID: Double] {
        var metres: [UUID: Double] = [:]
        for trip in trips {
            guard let id = trip.vehicleId, !trip.isTransfer else { continue }
            metres[id, default: 0] += trip.distance
        }
        return metres.mapValues { $0 / 1000 }
    }

    /// НАГРАДНЫЕ километры по машинам — от чего считается уровень.
    ///
    /// Отдельная функция, а не флаг у первой: у одометра и у уровня разные
    /// вопросы. Одометр спрашивает «сколько машина проехала» (вписанная
    /// рукой поездка — проехала), уровень — «что приложение видело своими
    /// глазами». Складывать их в одну сумму значит отдать уровень тому, кто
    /// нарисовал маршрут по карте. Правило про «что даёт награды» живёт в
    /// `Trip.rewardKm` и больше нигде.
    static func rewardByVehicle(from trips: [Trip]) -> [UUID: Double] {
        var km: [UUID: Double] = [:]
        for trip in trips {
            guard let id = trip.vehicleId, !trip.isTransfer else { continue }
            km[id, default: 0] += trip.rewardKm
        }
        return km
    }
}
