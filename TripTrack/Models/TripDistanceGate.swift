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

    /// A corrupt filter estimate is not a speed record. Discard it instead of
    /// clamping it to the ceiling, which would invent a 300 km/h achievement.
    static func isPlausibleSpeed(_ speed: Double) -> Bool {
        speed.isFinite && speed >= 0 && speed <= FixGate.maxSpeedMS
    }

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

    // MARK: - Кому одометр верит

    /// Хуже этого фикс в километры не идёт (спека §2.2). Число — прежний
    /// потолок записи, поэтому километры старых поездок пересчитываются в то же
    /// самое: у их точек лежит оценка фильтра, и она не больше 65 м по
    /// построению (на 38 896 точках базы владельца максимум — 63.98).
    static let odometerAccuracyLimit: Double = 65

    /// Вправе ли точка двигать одометр, рекорд скорости, высоту и проезды мест.
    ///
    /// Одна дверь на все счётчики пути: запись, финализация, пост-обработка,
    /// `Trip.movementSplit`, `TripRouteLocator.distancePrefix`, пейлоад синка,
    /// значки, графики поездки и `PlaceMatcher`. Точность 0 — у вписанной рукой
    /// поездки, и такая точка считается, как считалась.
    static func countsForDistance(horizontalAccuracy: Double, isInterpolated: Bool) -> Bool {
        !isInterpolated && horizontalAccuracy <= odometerAccuracyLimit
    }

    /// Точка трека в виде, достаточном для подсчёта расстояния.
    struct Sample {
        let latitude: Double
        let longitude: Double
        let timestamp: Date?
        let recordingSegmentIndex: Int
        let speed: Double?

        init(latitude: Double, longitude: Double, timestamp: Date?, recordingSegmentIndex: Int = 0,
             speed: Double? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.timestamp = timestamp
            self.recordingSegmentIndex = recordingSegmentIndex
            self.speed = speed
        }
    }

    /// Maximum supported by trusted, chronologically ordered recorded samples.
    /// Include the first actual speed: a two-point drive may start moving and
    /// finish stopped. A missing interval >10s can also establish a lower bound
    /// on the real maximum via displacement/time, even when both endpoint
    /// speeds are zero or unknown. This is not an instantaneous arrival speed.
    /// Never infer it across an explicit pause or an implausible GPS jump.
    static func maximumRecordedSpeed(_ samples: [Sample]) -> Double {
        var maximum = samples.reduce(0.0) { current, sample in
            guard let speed = sample.speed, isPlausibleSpeed(speed) else { return current }
            return max(current, speed)
        }

        for (from, to) in zip(samples, samples.dropFirst()) {
            guard from.recordingSegmentIndex == to.recordingSegmentIndex,
                  let start = from.timestamp, let end = to.timestamp else { continue }
            let dt = end.timeIntervalSince(start)
            guard dt > 10, dt.isFinite else { continue }
            let fromCoordinate = CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)
            let toCoordinate = CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)
            guard CLLocationCoordinate2DIsValid(fromCoordinate), CLLocationCoordinate2DIsValid(toCoordinate)
            else { continue }
            let meters = CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
            guard meters > 0, meters.isFinite, isPlausibleSegment(meters: meters, dt: dt) else { continue }
            maximum = max(maximum, meters / dt)
        }
        return maximum
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
            // A user pause is not a GPS gap. Start the next recorded section
            // with a fresh anchor, even if the missing journey looks plausible.
            guard sample.recordingSegmentIndex == anchor.recordingSegmentIndex else {
                anchor = sample
                continue
            }
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
