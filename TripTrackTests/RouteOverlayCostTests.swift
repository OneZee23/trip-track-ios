import XCTest
import MapKit
@testable import TripTrack

/// Во что обходится нарисовать маршрут.
///
/// Экран поездки рисует не одну линию, а по полилинии на каждый непрерывный
/// участок одной скоростной зоны. Чем подробнее упрощение, тем больше точек, а
/// значит и переходов между зонами — то есть цена растёт быстрее, чем число
/// точек. Порог упрощения поэтому нельзя двигать на глаз: здесь он меряется.
final class RouteOverlayCostTests: XCTestCase {

    /// Три часа городской езды на 1 Гц: светофоры, разгоны, дворы. Скорость
    /// гуляет через все зоны — то есть худший случай для группировки.
    private func cityTrip(hours: Double, noise: Double = 1.5) -> ([CLLocationCoordinate2D], [Double]) {
        let count = Int(hours * 3600)
        var coords: [CLLocationCoordinate2D] = []
        var speeds: [Double] = []
        var lat = 45.03, lon = 38.97
        // Шум обязателен: без него ломаная получается гладкой, RDP схлопывает
        // её вчетверо охотнее реального трека, и замер врёт в приятную сторону.
        var state: UInt64 = 20_260_906
        func jitter() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Double((state >> 33) % 10_000) / 10_000.0 * 2 - 1) * noise
        }
        for i in 0..<count {
            let t = Double(i)
            // Светофорный цикл: разгон, ход, торможение, стояние.
            let phase = (t / 90).truncatingRemainder(dividingBy: 1)
            let speed = phase < 0.7 ? 4 + 12 * sin(phase / 0.7 * .pi) : 0.5
            let heading = sin(t / 200) * 2
            lat += speed * cos(heading) / 111_320
            lon += speed * sin(heading) / (111_320 * cos(45.03 * .pi / 180))
            coords.append(CLLocationCoordinate2D(
                latitude: lat + jitter() / 111_320,
                longitude: lon + jitter() / (111_320 * cos(45.03 * .pi / 180))
            ))
            speeds.append(speed)
        }
        return (coords, speeds)
    }

    private func overlayCount(
        _ coords: [CLLocationCoordinate2D],
        _ speeds: [Double],
        epsilon: Double
    ) -> (overlays: Int, points: Int) {
        let simplified = RouteMapView.simplifyWithSpeeds(coords, speeds: speeds, epsilon: epsilon)
        let groups = RouteMapView.groupBySpeedZone(simplified)
        return (groups.count, simplified.coords.count)
    }

    /// Самая длинная поездка, какую человек делает за день, обязана рисоваться
    /// тем же порогом, что и получасовая. Это и есть причина, по которой в коде
    /// НЕТ потолка «на длинных треках упрощай грубее»: он там был, и замер
    /// показал, что он ничего не спасал.
    func testEightHoursDrawsAtTheSameThreshold() {
        let (coords, speeds) = cityTrip(hours: 8)
        let fine = overlayCount(coords, speeds, epsilon: RouteMapView.drawEpsilon)
        print("8ч: точек \(coords.count) → \(fine.points), оверлеев \(fine.overlays)")

        XCTAssertLessThan(fine.overlays, 2_000,
                          "восемь часов дают \(fine.overlays) оверлеев — карта поедет кусками")
    }

    /// Почему потолка нет: цену диктуют переходы между скоростными зонами, а не
    /// порог упрощения. Впятеро более подробная линия стоит процентов на
    /// двадцать дороже — и ради этих двадцати процентов не стоит отбирать у
    /// длинной поездки её дворы.
    ///
    /// Если это когда-нибудь перестанет выполняться — например, группировка
    /// начнёт дробить линию иначе, — потолок придётся вернуть, и тест об этом
    /// скажет раньше, чем человек с горячим телефоном.
    func testDetailIsCheapBecauseSpeedZonesDominate() {
        let (coords, speeds) = cityTrip(hours: 3)
        let fine = overlayCount(coords, speeds, epsilon: RouteMapView.drawEpsilon)
        let asBefore065 = overlayCount(coords, speeds, epsilon: 0.0001)
        print("2м: \(fine.points) точек / \(fine.overlays) оверлеев · 11м (до 0.6.5): \(asBefore065.points) / \(asBefore065.overlays)")

        XCTAssertGreaterThan(Double(fine.points), Double(asBefore065.points) * 3,
                             "подробность не выросла — порог опущен впустую")
        XCTAssertLessThan(Double(fine.overlays), Double(asBefore065.overlays) * 1.6,
                          "цена подробности выросла непропорционально — пора вернуть потолок")
    }
}
