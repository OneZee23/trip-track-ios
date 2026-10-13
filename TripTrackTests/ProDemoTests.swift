import XCTest
import CoreLocation
@testable import TripTrack

/// Демонстрация показывает ЕГО данные, а когда их нет — честную замену, а не
/// пустое место и не картинку из стока.
final class ProDemoTests: XCTestCase {

    // MARK: - Страницы

    func testEveryFeatureHasItsPage() {
        for feature in PlusFeature.allCases {
            let page = ProDemoContent.page(
                for: feature, hasVehicle: true, hasTrips: true, lang: .ru)
            XCTAssertFalse(page.title.isEmpty, "\(feature): нет заголовка")
            XCTAssertFalse(page.text.isEmpty, "\(feature): нет объяснения")
            XCTAssertEqual(page.feature, feature)
        }
    }

    func testEveryPageIsTranslatedEverywhere() {
        for lang in LanguageManager.Language.allCases {
            for page in ProDemoContent.pages(hasVehicle: true, hasTrips: true, lang: lang) {
                XCTAssertFalse(page.title.isEmpty, "\(lang.rawValue) \(page.feature)")
                XCTAssertFalse(page.text.isEmpty, "\(lang.rawValue) \(page.feature)")
                XCTAssertFalse(page.title.contains("{"), page.title)
                XCTAssertFalse(page.text.contains("{"), page.text)
            }
        }
    }

    /// Порядок страниц тот же, что порядок набора на витрине: сначала то, что
    /// видно другим, потом то, что только себе. Два порядка на один список
    /// однажды разошлись бы.
    func testPageOrderMatchesTheFeatureSet() {
        XCTAssertEqual(ProDemoContent.order,
                       [.profileBackgrounds, .avatarFrame, .vehicleCardStyle,
                        .routeLineStyle, .manualTrip])
        XCTAssertEqual(Set(ProDemoContent.order), Set(PlusFeature.allCases),
                       "страница есть у каждой функции и ни одной лишней")
    }

    // MARK: - Состояние 3: данных нет

    func testNoVehicleGivesTheSilhouetteAndNoTripsGivesTheExampleRoute() {
        let card = ProDemoContent.page(
            for: .vehicleCardStyle, hasVehicle: false, hasTrips: true, lang: .ru)
        XCTAssertEqual(card.preview, .vehicleSilhouette)
        XCTAssertTrue(card.previewIsLabelledAsExample)

        let line = ProDemoContent.page(
            for: .routeLineStyle, hasVehicle: true, hasTrips: false, lang: .ru)
        XCTAssertEqual(line.preview, .exampleRoute)
        XCTAssertTrue(line.previewIsLabelledAsExample,
                      "пример обязан быть подписан примером")
    }

    /// Свои данные примером НЕ подписываются: подпись «пример» под его
    /// собственным маршрутом — это неправда в другую сторону.
    func testOwnDataIsNeverLabelledAsAnExample() {
        for feature in PlusFeature.allCases {
            let page = ProDemoContent.page(
                for: feature, hasVehicle: true, hasTrips: true, lang: .ru)
            XCTAssertFalse(page.previewIsLabelledAsExample, "\(feature)")
        }
    }

    /// Текст тоже меняется, а не только картинка: «Пока машины нет, показываем
    /// пример» — часть объяснения, и без неё силуэт читался бы поломкой.
    func testTheCopyItselfChangesWhenThereIsNothingToShow() {
        let with = ProDemoContent.page(
            for: .vehicleCardStyle, hasVehicle: true, hasTrips: true, lang: .ru)
        let without = ProDemoContent.page(
            for: .vehicleCardStyle, hasVehicle: false, hasTrips: true, lang: .ru)
        XCTAssertNotEqual(with.text, without.text)

        let trips = ProDemoContent.page(
            for: .routeLineStyle, hasVehicle: true, hasTrips: true, lang: .ru)
        let noTrips = ProDemoContent.page(
            for: .routeLineStyle, hasVehicle: true, hasTrips: false, lang: .ru)
        XCTAssertNotEqual(trips.text, noTrips.text)
    }

    /// Машина и поездки — РАЗНЫЕ развилки: пустой гараж не имеет права увести
    /// страницу маршрута в пример.
    func testTheTwoFallbacksDoNotLeakIntoEachOther() {
        let line = ProDemoContent.page(
            for: .routeLineStyle, hasVehicle: false, hasTrips: true, lang: .ru)
        XCTAssertEqual(line.preview, .route)
        let card = ProDemoContent.page(
            for: .vehicleCardStyle, hasVehicle: true, hasTrips: false, lang: .ru)
        XCTAssertEqual(card.preview, .vehicleCard)
    }

    /// Решение о превью существует ОТДЕЛЬНО от копии, и отвечает то же
    /// самое: контекстный лист спрашивает только картинку, и собирать ради
    /// неё три строки перевода, чтобы выбросить их, не надо.
    func testThePreviewDecisionMatchesThePageItComesFrom() {
        for feature in PlusFeature.allCases {
            for hasVehicle in [true, false] {
                for hasTrips in [true, false] {
                    let page = ProDemoContent.page(
                        for: feature, hasVehicle: hasVehicle,
                        hasTrips: hasTrips, lang: .ru)
                    let alone = ProDemoContent.preview(
                        for: feature, hasVehicle: hasVehicle, hasTrips: hasTrips)
                    XCTAssertEqual(page.preview, alone,
                                   "\(feature) машина=\(hasVehicle) поездки=\(hasTrips)")
                }
            }
        }
    }

    // MARK: - Маршрут в коробке превью

    func testRouteFillsTheBoxInBothDirections() throws {
        let coords = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 38.0),
            CLLocationCoordinate2D(latitude: 45.5, longitude: 38.4),
            CLLocationCoordinate2D(latitude: 46.0, longitude: 39.0)
        ]
        let points = ProDemoData.unitPoints(from: coords)
        XCTAssertEqual(points.count, 3)
        // Развёрнуто, а не `min()` в утверждении: `min()` у коллекции отдаёт
        // опционал, и `accuracy:` его не принимает.
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        XCTAssertEqual(try XCTUnwrap(xs.min()), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(xs.max()), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(ys.min()), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(ys.max()), 1, accuracy: 0.0001)
        for point in points {
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y),
                          "точка вышла за коробку: \(point)")
        }
    }

    /// Дорога строго с запада на восток даёт НУЛЕВУЮ широтную рамку. Ошибка
    /// здесь не падает, а рисует: без защиты маршрут либо исчезает, либо
    /// уезжает за край.
    func testAStraightRoadDoesNotDivideByZero() {
        let flat = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 38.0),
            CLLocationCoordinate2D(latitude: 45.0, longitude: 39.0)
        ]
        let points = ProDemoData.unitPoints(from: flat)
        XCTAssertEqual(points.count, 2)
        for point in points {
            XCTAssertFalse(point.y.isNaN, "деление на ноль по широте")
            XCTAssertEqual(point.y, 0.5, accuracy: 0.0001, "плоская дорога — посередине")
        }

        let vertical = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 38.0),
            CLLocationCoordinate2D(latitude: 46.0, longitude: 38.0)
        ]
        for point in ProDemoData.unitPoints(from: vertical) {
            XCTAssertFalse(point.x.isNaN, "деление на ноль по долготе")
            XCTAssertEqual(point.x, 0.5, accuracy: 0.0001)
        }
    }

    /// Одна точка — не маршрут. Рисовать из неё линию нечем, и пустой ответ
    /// уводит страницу в нарисованный пример.
    func testASinglePointIsNotARoute() {
        XCTAssertTrue(ProDemoData.unitPoints(from: []).isEmpty)
        XCTAssertTrue(ProDemoData.unitPoints(from: [
            CLLocationCoordinate2D(latitude: 45, longitude: 38)
        ]).isEmpty)
    }

    /// Ось Y перевёрнута на ПОКАЗЕ, а не здесь: в единичном пространстве
    /// широта растёт вверх, как в географии.
    func testLatitudeGrowsUpwardsInUnitSpace() {
        let points = ProDemoData.unitPoints(from: [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 38.0),
            CLLocationCoordinate2D(latitude: 46.0, longitude: 38.5)
        ])
        XCTAssertLessThan(points[0].y, points[1].y, "северная точка обязана быть выше")
    }

    /// Нарисованные примеры лежат В коробке: точка за её пределами вылезла бы
    /// из-под скругления превью.
    func testDrawnExamplesStayInsideTheBox() {
        for points in [ProDemoData.exampleRoute, ProDemoData.manualRoute] {
            XCTAssertGreaterThan(points.count, 1)
            for point in points {
                XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y),
                              "нарисованная точка вне коробки: \(point)")
            }
        }
    }
}
