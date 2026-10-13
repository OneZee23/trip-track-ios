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

    // Попадание пальцем по булавке проверяет `AtlasPlaceTapTests` — там оно
    // спрашивается ПОВЕДЕНИЕМ (тап по точке экрана открывает место), а не
    // геометрией вида. Прежние три теста мерили рамку `MKAnnotationView`, и
    // ровно на неё хит-тест и опирался — то есть проверяли ту самую
    // конструкцию, которая и промахивалась.
}
