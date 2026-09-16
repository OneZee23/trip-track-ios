import XCTest

/// Раскрытие карты поездки, кадр за кадром.
///
/// Жалоба владельца на устройстве: «заход на полный экран карты поездки
/// тяжёлый, с тяжёлой анимацией». Причина была не в анимации, а в том, что за
/// едущей системной шторкой собиралась ВТОРАЯ `MKMapView`. Проверить, что
/// теперь карта одна и та же и что она вырастает из своей рамки, можно только
/// кадрами: ни возвращаемое значение, ни состояние этого не покажут.
final class FullscreenMapExpansionShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>",
            "-seed-map-demo", "-seed-places-rich"
        ]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func test_fullscreen_map_expansion() {
        let profile = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "нет входа в «Я»")
        profile.tap()
        usleep(3_000_000)

        let row = app.historyTripCells.firstMatch
        var attempts = 0
        while !row.exists && attempts < 6 {
            app.swipeUp(velocity: .slow)
            usleep(900_000)
            attempts += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8), "в истории нет ни одной поездки")
        row.tap()
        usleep(5_000_000)
        snap("w070_fsmap_hero")

        let expand = app.buttons.matching(identifier: "detail_map_expand").firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 8), "нет кнопки «развернуть»")

        // Кадры раскрытия. Снимок экрана сам стоит десятки миллисекунд,
        // поэтому шаг задаётся ПОСЛЕ него, а настоящее время каждого кадра
        // печатается — по нему и читается длительность на симуляторе.
        let started = Date()
        expand.tap()
        for i in 1...6 {
            let image = XCUIScreen.main.screenshot()
            let a = XCTAttachment(screenshot: image)
            a.name = String(format: "w070_fsmap_expanding_%d", i)
            a.lifetime = .keepAlways
            add(a)
            print("EXPAND_FRAME \(i) at \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            usleep(80_000)
        }
        usleep(900_000)
        print("EXPAND_SETTLED at \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        snap("w070_fsmap_expanded")

        // Хром обязан быть на месте у СТОЯЩЕЙ карты — и это первое, что
        // видно на кадре «expanded».
        let close = app.buttons.matching(identifier: "fullscreen_map_close").firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "хром не проявился")

        // Снимок на карте — только если на маршруте есть булавка. Сид
        // (`-seed-map-demo`) фотографий не заводит вовсе, поэтому на
        // симуляторе эта половина обычно пропускается.
        let pin = app.descendants(matching: .any)
            .matching(identifier: "map_photo_pin").firstMatch
        if pin.waitForExistence(timeout: 3) {
            pin.tap()
            usleep(700_000)
            snap("w070_fsmap_photo_preview")
            let card = app.descendants(matching: .any)
                .matching(identifier: "map_photo_preview").firstMatch
            if card.waitForExistence(timeout: 3) {
                card.tap()
                usleep(1_200_000)
                snap("w070_fsmap_photo_viewer")
            }
        } else {
            print("NO_PHOTO_PIN: сид не заводит фотографий — карточка и просмотрщик не сняты")
        }

        // И обратно: карта возвращается в рамку героя.
        close.tap()
        usleep(1_500_000)
        snap("w070_fsmap_back_to_hero")
    }
}
