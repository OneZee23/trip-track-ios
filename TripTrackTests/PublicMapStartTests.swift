import XCTest
import CoreLocation
@testable import TripTrack

/// Чужая карта по варианту A (0.9.1): камера на загрузке, названия поездок
/// в списках региона и маршрута, высота шторки числом.
@MainActor
final class PublicMapStartTests: XCTestCase {

    // MARK: - Название поездки

    func testTitleRidesFromTheWireIntoTheTrip() throws {
        let json = Data("""
        {"id":"D37A2001-0000-4000-8000-000000000001","startDate":"2026-10-20T09:11:00Z",
         "endDate":"2026-10-20T15:00:00Z","distance":418000,"duration":20000,
         "region":"Киров","title":"Сыктывкар → Киров","previewPolyline":null}
        """.utf8)

        let dto = try Self.decoder.decode(PublicTripDTO.self, from: json)

        XCTAssertEqual(dto.asTrip().title, "Сыктывкар → Киров")
    }

    func testAServerWithoutTitlesStillDecodes() throws {
        let json = Data("""
        {"id":"D37A2001-0000-4000-8000-000000000002","startDate":"2026-10-20T09:11:00Z",
         "endDate":null,"distance":1000,"duration":null,"region":null,"previewPolyline":null}
        """.utf8)

        let dto = try Self.decoder.decode(PublicTripDTO.self, from: json)

        XCTAssertNil(dto.asTrip().title)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Рамка камеры на загрузке

    func testStartBoundsCoverEveryRecentRoute() throws {
        let kirov = CLLocationCoordinate2D(latitude: 58.60, longitude: 49.66)
        let syktyvkar = CLLocationCoordinate2D(latitude: 61.67, longitude: 50.84)
        let ufa = CLLocationCoordinate2D(latitude: 54.74, longitude: 55.97)

        let bounds = try XCTUnwrap(PublicMapView.startBounds(previews: [[kirov, syktyvkar], [], [ufa]]))

        XCTAssertEqual(bounds.minLat, 54.74, accuracy: 1e-9)
        XCTAssertEqual(bounds.maxLat, 61.67, accuracy: 1e-9)
        XCTAssertEqual(bounds.minLon, 49.66, accuracy: 1e-9)
        XCTAssertEqual(bounds.maxLon, 55.97, accuracy: 1e-9)
    }

    func testNoPreviewsLeaveTheCameraToTheRoutes() {
        XCTAssertNil(PublicMapView.startBounds(previews: []))
        XCTAssertNil(PublicMapView.startBounds(previews: [[], []]))
    }

    func testTheBoundsSurviveTheNavigationPath() {
        let a = GeoBounds(minLat: 54.7, maxLat: 61.7, minLon: 49.6, maxLon: 56.0)
        let b = GeoBounds(minLat: 54.7, maxLat: 61.7, minLon: 49.6, maxLon: 56.0)

        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        let id = UUID(uuidString: "D37A2000-0000-4000-8000-000000000081")!
        XCTAssertEqual(ProfilePreviewDest.publicMap(id, "A", a), ProfilePreviewDest.publicMap(id, "A", b))
    }

    // MARK: - Первый кадр по маршрутам

    func testRoutesBoundsTakeEveryPointNotTheMiddles() throws {
        // Two drives down France: their middles sit in the centre of the
        // country, their ends in Toulouse and Lille.
        let down = [CLLocationCoordinate2D(latitude: 43.4, longitude: 1.0),
                    CLLocationCoordinate2D(latitude: 47.0, longitude: 2.0),
                    CLLocationCoordinate2D(latitude: 50.65, longitude: 3.1)]
        let back = [CLLocationCoordinate2D(latitude: 50.6, longitude: 3.0),
                    CLLocationCoordinate2D(latitude: 48.2, longitude: 2.1),
                    CLLocationCoordinate2D(latitude: 45.8, longitude: 1.3)]

        let routes = try XCTUnwrap(GeoBounds(coveringRoutes: [down, [], back]))
        let middles = try XCTUnwrap(GeoBounds(covering: [down[1], back[1]]))

        XCTAssertEqual(routes, GeoBounds(minLat: 43.4, maxLat: 50.65, minLon: 1.0, maxLon: 3.1))
        XCTAssertLessThan(middles.maxLat - middles.minLat, 2, "the middles alone frame the centre only")
        XCTAssertNil(GeoBounds(coveringRoutes: [[], []]))
    }

    // MARK: - Высота шторки поездок

    func testTripsPanelGrowsWithRowsAndStopsAtFourAndAHalf() {
        let one = PublicMapView.tripsPanelHeight(count: 1)
        let four = PublicMapView.tripsPanelHeight(count: 4)
        let five = PublicMapView.tripsPanelHeight(count: 5)
        let fifty = PublicMapView.tripsPanelHeight(count: 50)

        XCTAssertEqual(four - one, 3 * AtlasTripRow.height, accuracy: 0.001)
        // Пятая строка видна наполовину — знак, что список листается.
        XCTAssertEqual(five - four, AtlasTripRow.height / 2, accuracy: 0.001)
        XCTAssertEqual(fifty, five, accuracy: 0.001)
        XCTAssertEqual(PublicMapView.tripsPanelHeight(count: 0), one, accuracy: 0.001)
    }
}
