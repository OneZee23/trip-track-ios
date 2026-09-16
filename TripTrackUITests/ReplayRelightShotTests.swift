import XCTest

/// Возврат яркости маршрута после «×».
///
/// Находка владельца на устройстве: реплей закрыт, машинки нет, а маршрут
/// впереди ещё две-пять секунд остаётся приглушённым. Смена `alpha` у
/// рендерера помечает тайлы устаревшими, но перерисовывает их MapKit лениво.
/// Проверяется кадрами: сама яркость — свойство картинки, и ни возвращаемым
/// значением, ни состоянием её не выразить.
final class ReplayRelightShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo"
        ]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_route_relights_right_after_stop() {
        let profile = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        usleep(3_000_000)

        let row = app.historyTripCells.firstMatch
        var attempts = 0
        while !row.exists && attempts < 6 {
            app.swipeUp(velocity: .slow)
            usleep(900_000)
            attempts += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        usleep(5_000_000)

        let expand = app.buttons.matching(identifier: "detail_map_expand").firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 8))
        expand.tap()
        usleep(2_000_000)

        let play = app.buttons.matching(identifier: "fullscreen_replay_play").firstMatch
        guard play.waitForExistence(timeout: 5) else {
            print("NO_REPLAY: у поездки нет времён по точкам")
            return
        }
        play.tap()
        usleep(2_500_000)
        print("RELIGHT_PLAYING at \(Date().timeIntervalSince1970)")

        let stop = app.buttons.matching(identifier: "fullscreen_replay_stop").firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "«×» обязан быть у идущего реплея")
        stop.tap()
        print("RELIGHT_STOPPED at \(Date().timeIntervalSince1970)")
        usleep(6_000_000)
        print("RELIGHT_DONE at \(Date().timeIntervalSince1970)")
    }
}
