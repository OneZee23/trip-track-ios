import XCTest
import CoreLocation
@testable import TripTrack

/// «N поездок отсюда» на карточке дома.
final class AtlasHomeTests: XCTestCase {

    private let home = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)

    private func north(_ metres: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: home.latitude + metres / 111_320.0,
                               longitude: home.longitude)
    }

    /// Считается СТАРТ. Поездка, начавшаяся в другом конце города, не
    /// становится «отсюда» оттого, что проехала мимо дома.
    func testOnlyTripsThatStartedAtHomeCount() {
        let starts = [north(10), north(120), north(400), north(5_000)]
        XCTAssertEqual(AtlasHome.tripsStarted(at: home, starts: starts), 2)
    }

    /// Граница радиуса включительно: ровно на 150 м поездка ещё «отсюда» —
    /// иначе парковка через дорогу считалась бы чужим местом.
    func testTheEdgeOfTheRadiusStillCounts() {
        XCTAssertEqual(AtlasHome.tripsStarted(at: home, starts: [north(150)]), 1)
        XCTAssertEqual(AtlasHome.tripsStarted(at: home, starts: [north(151)]), 0)
    }

    /// Радиус — размер ячейки, которой приложение меряет «то же место».
    func testRadiusMatchesTheAppsIdeaOfTheSameSpot() {
        XCTAssertEqual(AtlasHome.radius, 150)
    }

    /// Пустая библиотека — ноль, а не пустая строка на карточке: решение, что
    /// делать с нулём, принимает экран.
    func testNoTripsIsZero() {
        XCTAssertEqual(AtlasHome.tripsStarted(at: home, starts: []), 0)
    }
}
