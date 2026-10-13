import XCTest
import CoreLocation
@testable import TripTrack

/// Дом: что рисуется, что сохраняется и когда просыпается переотправка.
final class HomeSettingsTests: XCTestCase {

    private let home = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "home.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    /// Пережить перезапуск обязаны все четыре поля: координата, радиус и оба
    /// тумблера. Забытое поле здесь — это молча сброшенная приватность.
    func testEverySettingSurvivesARestart() {
        var settings = HomeSettings()
        settings.latitude = home.latitude
        settings.longitude = home.longitude
        settings.radius = .district
        settings.showsOnMap = false
        settings.trimsPublicTracks = true
        settings.save(defaults: defaults)

        let loaded = HomeSettings.load(defaults: defaults)
        XCTAssertEqual(loaded, settings)
        XCTAssertNotNil(loaded.activeZone)
        XCTAssertEqual(loaded.activeZone?.radius, 1000)
    }

    /// Пустые настройки — это «дома нет», а не нулевая координата в
    /// Гвинейском заливе.
    func testEmptySettingsMeanNoHomeAtAll() {
        let fresh = HomeSettings.load(defaults: defaults)
        XCTAssertFalse(fresh.isSet)
        XCTAssertNil(fresh.coordinate)
        XCTAssertNil(fresh.mapPin)
        XCTAssertNil(fresh.activeZone)
    }

    /// «Дом есть, но скрыт» и «дома нет» дают карте ОДИН ответ: она про
    /// разницу между ними знать не должна.
    func testHiddenHomeLooksTheSameToTheMapAsNoHome() {
        var settings = HomeSettings()
        settings.latitude = home.latitude
        settings.longitude = home.longitude
        XCTAssertNotNil(settings.mapPin)

        settings.showsOnMap = false
        XCTAssertNil(settings.mapPin, "метка снята — карте рисовать нечего")
        XCTAssertTrue(settings.isSet, "но сам дом на месте")

        // И косметика НЕ трогает зону: спрятанный дом продолжает резать треки.
        settings.trimsPublicTracks = true
        XCTAssertNotNil(settings.activeZone)
    }

    /// Стирание аккаунта забирает дом: это координата двора.
    func testWipeTakesTheHomeAway() {
        var settings = HomeSettings()
        settings.latitude = home.latitude
        settings.longitude = home.longitude
        settings.save(defaults: defaults)
        HomeSettings.wipe(defaults: defaults)
        XCTAssertFalse(HomeSettings.load(defaults: defaults).isSet)
    }

    // MARK: Когда просыпается переотправка

    private func zone(_ lat: Double, _ radius: Double)
    -> (centre: CLLocationCoordinate2D, radius: Double) {
        (CLLocationCoordinate2D(latitude: lat, longitude: home.longitude), radius)
    }

    /// Переотправку будит ИЗМЕНЕНИЕ САМОЙ ЗОНЫ, а не флага: сравниваются три
    /// поля, и забыть одно значит оставить на сервере треки, не
    /// соответствующие нынешней настройке.
    func testTheResendWakesUpOnEveryRealChangeOfTheZoneAndOnNothingElse() {
        XCTAssertFalse(HomeManager.zoneChanged(from: nil, to: nil),
                       "зоны не было и нет — переотправлять нечего")
        XCTAssertTrue(HomeManager.zoneChanged(from: nil, to: zone(45, 500)),
                      "зону включили")
        XCTAssertTrue(HomeManager.zoneChanged(from: zone(45, 500), to: nil),
                      "зону выключили: правило симметричное, треки возвращаются целыми")
        XCTAssertFalse(HomeManager.zoneChanged(from: zone(45, 500), to: zone(45, 500)),
                       "ничего не поменялось")
        XCTAssertTrue(HomeManager.zoneChanged(from: zone(45, 500), to: zone(45, 1000)),
                      "сменился радиус")
        XCTAssertTrue(HomeManager.zoneChanged(from: zone(45, 500), to: zone(45.01, 500)),
                      "дом переехал")
    }
}
