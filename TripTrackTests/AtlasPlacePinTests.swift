import XCTest
import MapKit
@testable import TripTrack

/// Булавки своих мест на карте «Атласа» — правки владельца 26 сентября 2026.
///
/// Обе проверки про то, что видно и во что попадает палец, а не про состояние:
/// подпись и цель нажатия живут в UIKit, и «работает ли» у них спрашивается
/// только прямо.
@MainActor
final class AtlasPlacePinTests: XCTestCase {

    private let centre = CLLocationCoordinate2D(latitude: 45.04, longitude: 38.97)

    private func pin(name: String = "До моря") -> AtlasPlacePin {
        AtlasPlacePin(id: UUID(), coordinate: centre, name: name,
                      lastAt: Date(timeIntervalSince1970: 1_788_000_000),
                      passCount: 6, usual: 3_600, inPeriod: true)
    }

    /// Подпись у НЕвыбранной булавки не стоит.
    ///
    /// Доска S8 рисовала её всегда, и на живой карте наше «Геленджик» легло
    /// поверх «Gelendzhik» самой карты: одно слово дважды. Точка отвечает на
    /// «где», имя — на «что», и второй вопрос задают нажатием.
    func testAtlasPinIsBareUntilItIsSelected() {
        let place = pin()
        let annotation = AtlasPlaceAnnotation(pin: place, language: .ru)
        let view = PlacePinView(annotation: annotation, reuseIdentifier: PlacePinView.reuseID)
        let coordinator = MyMapRepresentable.Coordinator()

        coordinator.paint(view, with: annotation, selectedId: nil)
        XCTAssertFalse(view.isLabelled, "невыбранная булавка «Атласа» подписана")

        coordinator.paint(view, with: annotation, selectedId: place.id)
        XCTAssertTrue(view.isLabelled, "выбранная булавка осталась без подписи")
    }

    /// Безымянное место тоже молчит, пока его не выбрали.
    func testUnnamedAtlasPinIsBareToo() {
        let place = AtlasPlacePin(id: UUID(), coordinate: centre, name: nil, lastAt: nil,
                                  passCount: 1, usual: nil, inPeriod: true)
        let annotation = AtlasPlaceAnnotation(pin: place, language: .ru)
        let view = PlacePinView(annotation: annotation, reuseIdentifier: PlacePinView.reuseID)

        MyMapRepresentable.Coordinator().paint(view, with: annotation, selectedId: nil)
        XCTAssertFalse(view.isLabelled)
    }

    /// Цель нажатия у булавки места — не меньше сорока четырёх точек и ровно
    /// вокруг самой точки.
    ///
    /// Диск места 28 pt, с прежним запасом в 6 выходило 40 — меньше минимума
    /// HIG, и попасть по булавке можно было только сильно приблизившись.
    func testPlacePinTouchTargetClearsTheMinimumFinger() {
        let annotation = AtlasPlaceAnnotation(pin: pin(), language: .ru)
        let view = PlacePinView(annotation: annotation, reuseIdentifier: PlacePinView.reuseID)
        view.center = CGPoint(x: 200, y: 300)

        let target = MyMapRepresentable.Coordinator.touchTarget(of: view, annotation: annotation)

        XCTAssertGreaterThanOrEqual(target.width, 44)
        XCTAssertGreaterThanOrEqual(target.height, 44)
        XCTAssertEqual(target.midX, view.center.x, accuracy: 0.001, "цель съехала по горизонтали")
        XCTAssertEqual(target.midY, view.center.y, accuracy: 0.001, "цель съехала по вертикали")
        XCTAssertTrue(target.contains(CGPoint(x: 200, y: 300 - 21)),
                      "палец в 21 pt над точкой мимо цели")
    }

    /// Выбранная булавка несёт подпись ВЫШЕ диска — и цель нажатия от этого не
    /// уезжает вверх. Строится она вокруг центра вида, а не растяжением рамки.
    func testLabelDoesNotDragTheTouchTargetUpwards() {
        let place = pin(name: "Очень длинное имя места")
        let annotation = AtlasPlaceAnnotation(pin: place, language: .ru)
        let view = PlacePinView(annotation: annotation, reuseIdentifier: PlacePinView.reuseID)
        view.center = CGPoint(x: 120, y: 240)
        MyMapRepresentable.Coordinator().paint(view, with: annotation, selectedId: place.id)

        let target = MyMapRepresentable.Coordinator.touchTarget(of: view, annotation: annotation)
        XCTAssertEqual(target.midY, view.center.y, accuracy: 0.001)
    }

    /// Остальным булавкам цель не меняли: правило заведено ради мест, и
    /// раздача его всем подряд съела бы тапы по дорогам под ними.
    func testOtherAnnotationsKeepTheOldTarget() {
        let annotation = MKPointAnnotation()
        annotation.coordinate = centre
        let view = MKAnnotationView(annotation: annotation, reuseIdentifier: "x")
        view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        view.center = CGPoint(x: 50, y: 50)

        let target = MyMapRepresentable.Coordinator.touchTarget(of: view, annotation: annotation)
        XCTAssertEqual(target.width, 32, accuracy: 0.001, "запас перестал быть 6 pt")
    }
}
