import XCTest
import MapKit
@testable import TripTrack

/// «Открыто» читается ПЛОЩАДЬЮ, а не ниткой, — и решает это ровно одна
/// функция.
///
/// До 0.7.0 ширина коридора была «±50 м, но не тоньше двенадцати экранных
/// точек»: на улице это площадь, на городе и стране — волосок. Владелец на
/// устройстве: «всё скудно, тонкие линии… просто тупо тёмная зона, на которой
/// тоненькие оранжевые полоски». Таблица ниже и есть ответ: одно и то же
/// правило даёт двор на улице и полосу на трассе.
///
/// Проверять это можно только таблицей. На экране разница между «±50 м» и
/// «±1.8 км» видна сразу, а между двумя формулами, дающими то и другое, —
/// нет; поэтому числа записаны здесь, а не выведены из самой формулы.
final class HaloWidthTests: XCTestCase {

    /// Три точки шкалы из спеки: улица, город, страна.
    func testHaloHalfWidthTable() {
        XCTAssertEqual(FogVeilRenderer.haloHalfWidth(metresPerPoint: 1), 50, accuracy: 0.001,
                       "улица: ±50 м, между своими улицами обязана остаться темнота")
        XCTAssertEqual(FogVeilRenderer.haloHalfWidth(metresPerPoint: 100), 1_800, accuracy: 0.001,
                       "город: проезженный район обязан выйти пятном в 1.8 км")
        XCTAssertEqual(FogVeilRenderer.haloHalfWidth(metresPerPoint: 1_000), 18_000, accuracy: 0.001,
                       "страна: трасса обязана читаться полосой в 18 км")
    }

    /// Пол в метрах держится ровно до 2.78 м/pt (50 / 18) и ни точкой дальше.
    ///
    /// Это и есть точка, где правило меняет хозяина, и она обязана быть
    /// непрерывной: скачок ширины на зуме читался бы как мигание коридора.
    func testFloorHandsOverToPointsWithoutAJump() {
        let hinge = FogVeilRenderer.streetHalfWidthMetres / FogVeilRenderer.haloHalfWidthPoints
        XCTAssertEqual(hinge, 50.0 / 18.0, accuracy: 1e-9)
        XCTAssertEqual(FogVeilRenderer.haloHalfWidth(metresPerPoint: hinge - 0.01),
                       FogVeilRenderer.streetHalfWidthMetres, accuracy: 1e-9,
                       "чуть ближе точки перелома побеждают метры")
        XCTAssertEqual(FogVeilRenderer.haloHalfWidth(metresPerPoint: hinge),
                       FogVeilRenderer.haloHalfWidth(metresPerPoint: hinge - 1e-9), accuracy: 1e-3,
                       "в самой точке перелома ширина обязана совпасть — скачка нет")
    }

    /// Функция монотонна: отдаляясь, коридор не имеет права стать уже.
    func testHaloNeverShrinksAsYouZoomOut() {
        var previous = 0.0
        for metresPerPoint in stride(from: 0.5, through: 2_000, by: 0.5) {
            let halo = FogVeilRenderer.haloHalfWidth(metresPerPoint: metresPerPoint)
            XCTAssertGreaterThanOrEqual(halo, previous,
                                        "на \(metresPerPoint) м/pt ореол сузился")
            previous = halo
        }
    }

    /// Сверх пола ореол — ровно 18 экранных точек на сторону, на любой широте.
    ///
    /// Широта здесь не декорация: `corridorWidth` живёт в координатах
    /// рендерера, где метр стоит разное число точек карты в Сочи и в
    /// Мурманске, и ошибка в переводе была бы видна только на карте севера.
    func testCorridorOnScreenIsThirtySixPointsWhereverYouAre() {
        for latitude in [0.0, 45.035, 68.97] {
            let metre = MKMapPointsPerMeterAtLatitude(latitude)
            for zoom: MKZoomScale in [1e-3, 3e-4, 1e-4, 3e-5] {
                let width = FogVeilRenderer.corridorWidth(zoomScale: zoom, metre: metre)
                let metresPerPoint = 1 / (Double(zoom) * metre)
                guard metresPerPoint > FogVeilRenderer.streetHalfWidthMetres
                        / FogVeilRenderer.haloHalfWidthPoints else { continue }
                XCTAssertEqual(Double(width) * Double(zoom),
                               FogVeilRenderer.haloHalfWidthPoints * 2, accuracy: 0.001,
                               "широта \(latitude), зум \(zoom): коридор обязан быть 36 pt")
            }
        }
    }

    /// Вырожденный вход не роняет и не рисует бесконечную полосу.
    func testDegenerateInputsGiveNoCorridor() {
        XCTAssertEqual(FogVeilRenderer.corridorWidth(zoomScale: 0, metre: 1), 0)
        XCTAssertEqual(FogVeilRenderer.corridorWidth(zoomScale: 1e-4, metre: 0), 0)
    }
}
