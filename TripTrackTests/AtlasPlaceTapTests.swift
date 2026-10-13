import XCTest
import MapKit
@testable import TripTrack

/// Попадание пальцем по булавке места на «Атласе».
///
/// На НАСТОЯЩЕЙ проекции `MKMapView`, как у `RiddleHintTapTests`: разбор «что
/// под пальцем» — это геометрия экрана, и арифметикой по широте он разошёлся
/// бы с картой.
@MainActor
final class AtlasPlaceTapTests: XCTestCase {

    private let centre = CLLocationCoordinate2D(latitude: 44.60, longitude: 38.71)

    private func map() -> MKMapView {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        map.region = MKCoordinateRegion(
            center: centre, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        return map
    }

    private func pin() -> AtlasPlacePin {
        AtlasPlacePin(id: UUID(), coordinate: centre, name: "До моря",
                      lastAt: Date(timeIntervalSince1970: 1_788_000_000),
                      passCount: 6, usual: 3_600, inPeriod: true)
    }

    /// Палец в 20 pt от точки — это попадание.
    ///
    /// Двадцать точек это меньше половины минимальной цели HIG (44 pt), то
    /// есть заведомо внутри неё. Владелец 26 сен: «надо очень хорошо
    /// приблизить, чтобы по ним попасть» — вот это и проверяется.
    func testFingerTwentyPointsOffTheDotStillOpensThePlace() {
        let map = map()
        let place = pin()
        let coordinator = MyMapRepresentable.Coordinator()
        coordinator.syncPlaces(map, pins: [place], selectedId: nil, language: .ru)

        var asked: [UUID] = []
        coordinator.onSelectPlace = { asked.append($0) }

        let origin = map.convert(centre, toPointTo: map)
        coordinator.handleTap(at: CGPoint(x: origin.x + 20, y: origin.y), on: map)

        XCTAssertEqual(asked, [place.id], "булавка не поймала палец в 20 pt от себя")
    }

    /// Прямо по точке — тем более.
    func testFingerOnTheDotOpensThePlace() {
        let map = map()
        let place = pin()
        let coordinator = MyMapRepresentable.Coordinator()
        coordinator.syncPlaces(map, pins: [place], selectedId: nil, language: .ru)

        var asked: [UUID] = []
        coordinator.onSelectPlace = { asked.append($0) }

        coordinator.handleTap(at: map.convert(centre, toPointTo: map), on: map)
        XCTAssertEqual(asked, [place.id])
    }

    /// Промах далеко за целью места не открывает — иначе булавка съела бы
    /// нажатия по дороге под ней.
    func testFingerWellAwayDoesNotOpenThePlace() {
        let map = map()
        let coordinator = MyMapRepresentable.Coordinator()
        coordinator.syncPlaces(map, pins: [pin()], selectedId: nil, language: .ru)

        var asked: [UUID] = []
        coordinator.onSelectPlace = { asked.append($0) }

        let origin = map.convert(centre, toPointTo: map)
        coordinator.handleTap(at: CGPoint(x: origin.x + 90, y: origin.y), on: map)
        XCTAssertTrue(asked.isEmpty)
    }

    /// С отдаления булавок нет — и нажать их нельзя.
    ///
    /// Цель считается радиусом от координаты и рамки вида не спрашивает,
    /// поэтому без своего гейта место открывалось бы с карты края, где самой
    /// булавки на экране не нарисовано.
    func testFarZoomHasNoPlacesToTap() {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        map.region = MKCoordinateRegion(
            center: centre, span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8))
        XCTAssertGreaterThan(map.region.span.latitudeDelta, 3.0, "карта не отдалилась — тест ни о чём")

        let coordinator = MyMapRepresentable.Coordinator()
        coordinator.syncPlaces(map, pins: [pin()], selectedId: nil, language: .ru)
        var asked: [UUID] = []
        coordinator.onSelectPlace = { asked.append($0) }

        coordinator.handleTap(at: map.convert(centre, toPointTo: map), on: map)
        XCTAssertTrue(asked.isEmpty, "место открылось с масштаба, где булавки не видно")
    }

    /// Порог видимости — словами: край карты молчит, регион и двор говорят.
    func testPlacesAppearFromRegionZoomIn() {
        XCTAssertFalse(MyMapRepresentable.Coordinator.placesVisible(span: 8.0))
        XCTAssertFalse(MyMapRepresentable.Coordinator.placesVisible(span: 3.01))
        XCTAssertTrue(MyMapRepresentable.Coordinator.placesVisible(span: 3.0))
        XCTAssertTrue(MyMapRepresentable.Coordinator.placesVisible(span: 0.4))
        XCTAssertTrue(MyMapRepresentable.Coordinator.placesVisible(span: 0.02))
    }
}
