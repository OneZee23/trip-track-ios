import XCTest
import CoreLocation
@testable import TripTrack

/// Приватная зона у дома: что уезжает с телефона, а что нет.
final class PrivacyZoneTests: XCTestCase {

    private let home = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)

    /// Смещение на `metres` строго на север — широта считается без долготной
    /// поправки, поэтому число точное на любой широте.
    private func north(_ metres: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: home.latitude + metres / 111_320.0,
                               longitude: home.longitude)
    }

    /// Граница — это уже «не дома»: ровно на радиусе точка остаётся.
    func testTheEdgeItselfStaysOutside() {
        XCTAssertTrue(PrivacyZone.hides(north(150), centre: home, radius: 200))
        XCTAssertFalse(PrivacyZone.hides(north(250), centre: home, radius: 200))
        XCTAssertFalse(PrivacyZone.hides(north(201), centre: home, radius: 200),
                       "точка за радиусом обязана уехать")
    }

    /// Дом посреди поездки вырезается ТОЖЕ: заехал в обед переодеться —
    /// двор не должен появиться в чужой ленте.
    func testHomeInTheMiddleIsCutOutAsWell() {
        let points = [north(3000), north(1500), north(50), north(1500), north(3000)]
            .map { TrackPoint(latitude: $0.latitude, longitude: $0.longitude) }
        let left = PrivacyZone.trim(points: points, centre: home, radius: 500)
        XCTAssertEqual(left.count, 4)
        XCTAssertFalse(left.contains { PrivacyZone.hides($0.coordinate, centre: home, radius: 500) })
    }

    /// Превью режется тем же правилом: необрезанное превью выдало бы двор
    /// даже при обрезанном треке — карточку в ленте рисует именно оно.
    func testThePreviewIsCutByTheSameRule() {
        let route = [north(80), north(400), north(2000)]
        XCTAssertEqual(PrivacyZone.trim(coordinates: route, centre: home, radius: 500).count, 1)
    }

    /// Поездка целиком внутри зоны уезжает БЕЗ трека, а не с огрызком.
    func testATripEntirelyInsideTheZoneLosesItsTrackCompletely() {
        let points = [north(10), north(60), north(120)]
            .map { TrackPoint(latitude: $0.latitude, longitude: $0.longitude) }
        let left = PrivacyZone.trim(points: points, centre: home, radius: 200)
        XCTAssertTrue(left.isEmpty)
        XCTAssertFalse(PrivacyZone.isDrawable(left.count))
    }

    /// Зона работает, только когда есть И точка, И включённая обрезка: иначе
    /// где-нибудь проверят один флаг и обрежут по нулевой координате.
    func testTheZoneNeedsBothAPointAndTheSwitch() {
        var settings = HomeSettings()
        settings.trimsPublicTracks = true
        XCTAssertNil(settings.activeZone, "точки нет — резать нечем")

        settings.latitude = home.latitude
        settings.longitude = home.longitude
        XCTAssertNotNil(settings.activeZone)

        settings.trimsPublicTracks = false
        XCTAssertNil(settings.activeZone, "тумблер снят — трек уезжает целым")
    }

    /// Ступени радиуса — метры, и они лежат в `UserDefaults`.
    func testRadiusStepsAreTheThreeAgreedNumbers() {
        XCTAssertEqual(HomeSettings.Radius.allCases.map(\.rawValue), [200, 500, 1000])
        XCTAssertEqual(HomeSettings().radius, .block, "умолчание — квартал")
        XCTAssertFalse(HomeSettings().trimsPublicTracks,
                       "обрезка включается человеком: включение переотправляет публичные")
    }
}
