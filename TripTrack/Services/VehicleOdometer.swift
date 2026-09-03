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
enum VehicleOdometer {
    static func tracked(from trips: [Trip], vehicleId: UUID) -> Double {
        trips.reduce(into: 0.0) { sum, trip in
            guard trip.vehicleId == vehicleId, !trip.isTransfer else { return }
            sum += trip.distanceKm
        }
    }

    /// Пробеги сразу по всем машинам — один проход вместо N.
    static func trackedByVehicle(from trips: [Trip]) -> [UUID: Double] {
        trips.reduce(into: [UUID: Double]()) { map, trip in
            guard let id = trip.vehicleId, !trip.isTransfer else { return }
            map[id, default: 0] += trip.distanceKm
        }
    }
}
