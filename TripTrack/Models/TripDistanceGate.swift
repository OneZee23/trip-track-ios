import Foundation
import CoreLocation

/// Single source of truth for "should this GPS segment count toward distance?".
///
/// Used by every distance/stat path so they can't diverge:
///  - the live accumulator (`TripManager.handleNewLocation`)
///  - the finalize recompute (`TripManager.updateEntityStats`)
///  - the post-trip processor (`PostTripTrackProcessor.recalculateStats`)
///  - the moving-average split (`Trip.movementSplit`)
///
/// Previously the same predicate + magic numbers were copy-pasted in all four.
enum TripDistanceGate {
    /// Max plausible vehicle speed (m/s ≈ 300 km/h). A segment implying more is a
    /// GPS teleport jump (multipath / dropout snap-back) and is excluded.
    static let maxPlausibleSpeed: Double = 83.0
    /// Absolute fallback cap (m) for segments with no usable time delta — without
    /// `dt` we can't judge implied speed, so reject anything over 1 km as a jump.
    static let maxSegmentDistance: Double = 1000.0

    /// Whether a segment covering `meters` over `dt` seconds should count.
    ///
    /// With a usable `dt` (> 0) it gates on IMPLIED SPEED, so a real sparse-GPS /
    /// dead-zone bridge (minutes apart, >1 km, but a sane speed) is KEPT while a
    /// true teleport (huge distance, tiny dt → impossible speed) is rejected.
    /// Without a usable `dt` it falls back to the absolute distance cap.
    static func isPlausibleSegment(meters: Double, dt: TimeInterval) -> Bool {
        if dt > 0 { return meters / dt <= maxPlausibleSpeed }
        return meters < maxSegmentDistance
    }

    // MARK: - Шаг, которым набегают километры

    /// Ближе этого к предыдущему ЗАЧТЁННОМУ месту точка километров не приносит.
    ///
    /// С 0.6.5 форма трека и километры разошлись: точек пишется втрое больше,
    /// чтобы во дворе был виден каждый манёвр, — а вот считать по ним подряд
    /// нельзя. На пяти километрах в час машина проезжает за секунду метр с
    /// небольшим, тогда как GPS шумит на два-три; сложи такие отрезки подряд —
    /// и одометр вырастет на ровном месте. Это ровно та беда, которую ловили в
    /// 0.5.7–0.5.8, и возвращать её нельзя.
    ///
    /// Поэтому расстояние живёт на своём якоре: он стоит, пока машина не отошла
    /// на пять метров, и шум внутри этого круга в километры не попадает.
    static let minStep: Double = 5.0

    /// Точка трека в виде, достаточном для подсчёта расстояния.
    struct Sample {
        let latitude: Double
        let longitude: Double
        let timestamp: Date?

        init(latitude: Double, longitude: Double, timestamp: Date?) {
            self.latitude = latitude
            self.longitude = longitude
            self.timestamp = timestamp
        }
    }

    /// Сумма пути по точкам — тем же шагом, каким её набирает живая запись.
    ///
    /// Три места считали расстояние своим циклом «каждая точка минус
    /// предыдущая»: запись, финализация поездки и пост-обработка. Пока точки
    /// лежали в пяти метрах друг от друга, три копии давали одно и то же. С
    /// плотной записью они разъезжаются — причём финализация ПЕРЕЗАПИСЫВАЕТ то,
    /// что набрала запись, так что победил бы самый шумный из трёх.
    /// Отсюда одна функция на всех.
    static func totalDistance(_ samples: [Sample], minStep: Double = minStep) -> Double {
        guard samples.count > 1 else { return 0 }

        var total: Double = 0
        var anchor = samples[0]

        for sample in samples.dropFirst() {
            let from = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            let to = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
            let meters = to.distance(from: from)
            guard meters >= minStep else { continue }

            var dt: TimeInterval = 0
            if let a = anchor.timestamp, let b = sample.timestamp {
                dt = b.timeIntervalSince(a)
            }
            if isPlausibleSegment(meters: meters, dt: dt) {
                total += meters
            }
            // Якорь переносим и на отклонённом отрезке: телепорт GPS не должен
            // навсегда приковать счёт к точке, с которой машина давно уехала.
            anchor = sample
        }

        return total
    }
}
