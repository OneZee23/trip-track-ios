import XCTest
import CoreLocation
import MapKit
@testable import TripTrack

/// Карточка нерешённой загадки: что она печатает и чего в ней нет.
///
/// «Чего нет» здесь важнее «что есть»: карточка стоит на волосок от того,
/// чтобы выдать ответ, ради которого загадка и существует. Координаты в модели
/// нет ни в каком виде, и держит это тест, а не внимательность.
final class RiddleHintCardTests: XCTestCase {

    private func riddle(metres: Double) -> Journal.NearbyRiddle {
        Journal.NearbyRiddle(id: "lighthouse:u0h2w1q", type: .lighthouse,
                             metresToEdge: metres)
    }

    /// Строка загадки, правило и расстояние — тремя готовыми строками.
    func testCardCarriesTheLineTheRuleAndTheDistance() {
        let model = RiddleHintCardModel.make(
            riddle: riddle(metres: 12_400), unit: .km, lang: .ru)

        XCTAssertEqual(model.id, "lighthouse:u0h2w1q")
        XCTAssertEqual(model.kindLabel, AppStrings.sealKind(.ru, kind: .riddle))
        XCTAssertEqual(model.line, RiddleCopy.line(for: .lighthouse, .ru))
        XCTAssertEqual(model.ruleLine, AppStrings.cardSolvedByDriving(.ru))
        XCTAssertEqual(model.distanceLine,
                       AppStrings.journalRiddleDistance(
                           .ru, distance: Measure.distance(
                               metres: 12_400, unit: .km, lang: .ru)))
    }

    /// Единица приходит из `Measure` и МЕНЯЕТСЯ вместе с выбором человека.
    ///
    /// Своей арифметики у карточки нет и быть не может (канон «честные
    /// единицы»): расстояние приезжает напечатанным, а два разных выбора
    /// обязаны дать две разные строки — иначе где-то забыли единицу.
    func testDistanceSpeaksThePersonsUnit() {
        let metric = RiddleHintCardModel.make(
            riddle: riddle(metres: 12_400), unit: .km, lang: .en)
        let imperial = RiddleHintCardModel.make(
            riddle: riddle(metres: 12_400), unit: .miles, lang: .en)

        XCTAssertNotEqual(metric.distanceLine, imperial.distanceLine)
        XCTAssertEqual(imperial.distanceLine,
                       AppStrings.journalRiddleDistance(
                           .en, distance: Measure.distance(
                               metres: 12_400, unit: .miles, lang: .en)))
    }

    /// Внутри круга расстояния НЕТ: «0 км до круга» — это не ответ, а след
    /// формулы. То же правило, что у строки журнала.
    func testNoDistanceWhenTheOpenedWorldIsAlreadyInsideTheCircle() {
        let model = RiddleHintCardModel.make(
            riddle: riddle(metres: 0), unit: .km, lang: .ru)
        XCTAssertNil(model.distanceLine)
    }

    /// В модели нет НИ ОДНОГО числа-координаты — только строки.
    ///
    /// Проверяется отражением, а не чтением полей глазами: поле, добавленное
    /// «чтобы нарисовать кружок на мини-карте», выдало бы точку загадки, и
    /// заметить это можно было бы только в диффе.
    func testModelCarriesNoCoordinateAtAll() {
        let model = RiddleHintCardModel.make(
            riddle: riddle(metres: 12_400), unit: .km, lang: .ru)
        for child in Mirror(reflecting: model).children {
            let value = child.value
            XCTAssertFalse(value is CLLocationCoordinate2D,
                           "\(child.label ?? "?") — координата в карточке загадки")
            XCTAssertFalse(value is CLLocationDegrees,
                           "\(child.label ?? "?") — градусы в карточке загадки")
            XCTAssertTrue(value is String || value is String?,
                          "\(child.label ?? "?") — в карточке только напечатанные строки")
        }
    }
}

/// Нажатие на подсказку: значок, кольцо и то, что из этого открывается.
///
/// Координатор, а не экран: разбор «что под пальцем» живёт в нём, и проверить
/// его можно только точкой на настоящей проекции `MKMapView` — арифметикой по
/// широте он разошёлся бы с картой, как разошлись бы два счёта километров.
final class RiddleHintTapTests: XCTestCase {

    private let centre = CLLocationCoordinate2D(latitude: 45.04, longitude: 38.97)

    private func map() -> MKMapView {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        map.region = MKCoordinateRegion(
            center: centre, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        return map
    }

    private func hint() -> RiddleHint {
        RiddleHint(id: "lighthouse:u0h2w1q", type: .lighthouse,
                   centre: centre, radiusMetres: 5_000)
    }

    /// Палец на самом кольце — карточка этой загадки.
    @MainActor
    func testTapOnTheRingAsksForTheCard() {
        let map = map()
        let coordinator = MyMapRepresentable.Coordinator()
        coordinator.syncHints(map, hints: [hint()], language: .ru)

        var asked: [String] = []
        coordinator.onSelectHint = { asked.append($0) }

        let origin = map.convert(centre, toPointTo: map)
        let metresPerPoint = map.metersPerScreenPoint
        XCTAssertGreaterThan(metresPerPoint, 0)
        let radiusPoints = CGFloat(5_000 / metresPerPoint)
        coordinator.handleTap(at: CGPoint(x: origin.x + radiusPoints, y: origin.y), on: map)

        XCTAssertEqual(asked, ["lighthouse:u0h2w1q"])
    }

    /// Промах мимо кольца больше чем на запас — не карточка.
    ///
    /// Запас нужен (кольцо толщиной в точку пальцем не взять), но он же и есть
    /// цена: всё, что шире, съедало бы тапы по дорогам под кругом.
    @MainActor
    func testTapWellOffTheRingDoesNotAskForTheCard() {
        let map = map()
        let coordinator = MyMapRepresentable.Coordinator()
        coordinator.syncHints(map, hints: [hint()], language: .ru)

        var asked: [String] = []
        coordinator.onSelectHint = { asked.append($0) }

        let origin = map.convert(centre, toPointTo: map)
        let metresPerPoint = map.metersPerScreenPoint
        let radiusPoints = CGFloat(5_000 / metresPerPoint)
        let slack = MyMapRepresentable.Coordinator.hintRingTouchPoints
        coordinator.handleTap(
            at: CGPoint(x: origin.x + radiusPoints + slack * 3, y: origin.y), on: map)

        XCTAssertTrue(asked.isEmpty)
        XCTAssertNotNil(
            coordinator.hint(at: CGPoint(x: origin.x + radiusPoints + slack - 1, y: origin.y),
                             on: map),
            "внутри запаса кольцо обязано ловиться")
    }
}
