import XCTest
@testable import TripTrack

/// На «Атласе» положение человека знает КАРТА, а не наш `LocationManager`.
///
/// Источников два, и работает там только один. Синюю точку рисует сама
/// `MKMapView` (`showsUserLocation`) своей геолокацией. А наш
/// `LocationManager` на этой вкладке не запущен вовсе:
/// `MapViewModel.requestLocationPermission` — единственный, кто зовёт
/// `startRealGPS`, — не зовётся из приложения ни разу, и `currentLocation`
/// пуст ВСЕГДА, пока не пишется поездка. Кнопка «где я», спросившая его,
/// отвечала «местоположение пока недоступно» при любом раскладе, глядя на
/// человека, которого карта прямо сейчас показывает («обман или баг
/// какой-то», владелец на устройстве 27 сентября).
///
/// Сторож читает ИСХОДНИКИ, как `UnitsDisciplineTests`, и вот почему не
/// экраном: экранный тест на это падает или проходит в зависимости от того,
/// выдана ли симулятору геолокация (`simctl privacy … location`), — с
/// запрещённой жалоба ВЕРНА. Вердикт, который переключается скрытой
/// настройкой окружения, сторожем быть не может.
final class AtlasLocationSourceTests: XCTestCase {

    func testAtlasScreensNeverAskOurLocationManagerForAFix() throws {
        let atlas = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TripTrack/Views/MyMap")

        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: atlas, includingPropertiesForKeys: nil),
            "не нашёл экранов «Атласа» по пути \(atlas.path)")

        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("locationManager.currentLocation") {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertGreaterThan(scanned, 10, "экраны «Атласа» не прочитались — сторож ничего не проверил")
        XCTAssertEqual(offenders, [], """
            Экран «Атласа» спрашивает наш LocationManager: \(offenders.joined(separator: ", ")).
            Его GPS на этой вкладке никто не заводит, и ответ будет пустым всегда.
            Спрашивай разрешение (MapViewModel.locationDenied), а ехать доверь карте.
            """)
    }
}
