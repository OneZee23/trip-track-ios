import XCTest

/// Состояния «Атласа» 13, 22, 24 и 26 по спеке v3.
///
/// Состояние 23 («Не удалось обновить») здесь не снимается: атлас считается
/// по СВОЕЙ базе, сети ему не нужно вовсе, и отказа, который можно было бы
/// повторить, у него не бывает. Рисовать кнопку «Повторить» там, где нечего
/// повторять, — это нажатие, которое ничего не делает.
final class AtlasStatesShotTests: XCTestCase {

    /// 24: строка «Нет сети» над сводкой и «Поделиться» вторичного цвета.
    func testOfflineRowAndDisabledShare() {
        let app = launch(extra: ["-debug-offline"])
        openAtlas(app)

        let row = app.staticTexts["atlas_offline_row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "строки «Нет сети» нет")
        snap(app, "a24_offline")

        // «Поделиться» отвечает той же строкой, а не молчит.
        app.buttons["atlas_share"].firstMatch.tap()
        usleep(1_200_000)
        snap(app, "a24_share_unavailable")
    }

    /// 22: пока атлас считается — скелетон на месте чисел.
    ///
    /// Ловится БЕЗ пауз: `isLoading` снимается первым же ответом, и любое
    /// ожидание тут съедает предмет проверки. На стресс-сиде окно шире, но
    /// гонять ради одного кадра четыреста поездок дороже, чем ловить его
    /// здесь.
    func testLoadingSkeleton() {
        let app = launch(extra: ["-debug-atlas-loading"])
        openAtlas(app)
        XCTAssertTrue(app.otherElements["atlas_stats_skeleton"].firstMatch
            .waitForExistence(timeout: 15), "скелетона нет на месте чисел")
        // Карта и кнопки при этом ЖИВЫЕ — так написано в спеке.
        XCTAssertTrue(app.buttons["atlas_appearance"].firstMatch.isHittable)
        XCTAssertTrue(app.buttons["atlas_locate"].firstMatch.isHittable)
        snap(app, "a22_loading")
    }

    /// 13: диалог у перечёркнутой кнопки «где я».
    func testLocationDeniedDialog() {
        let app = launch(extra: ["-debug-location-denied"])
        openAtlas(app)

        app.buttons["atlas_locate"].firstMatch.tap()
        usleep(1_500_000)
        snap(app, "a13_location_denied")

        // Диалог домашний: у него есть «Позже», и она закрывает без ухода
        // в настройки.
        let later = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'озже'")).firstMatch
        XCTAssertTrue(later.waitForExistence(timeout: 5), "в диалоге нет «Позже»")
        later.tap()
        usleep(1_000_000)

        // Второй тап больше не спрашивает — показывает весь атлас.
        app.buttons["atlas_locate"].firstMatch.tap()
        usleep(1_500_000)
        XCTAssertFalse(later.exists, "«Позже» спросили второй раз за один запуск")
        snap(app, "a13_after_later")
    }

    /// 26: карточка дома. Дом ставится РУКАМИ — другого входа нет.
    func testHomeCard() {
        let app = launch(extra: [])
        openAtlas(app)

        app.buttons["atlas_appearance"].firstMatch.tap()
        XCTAssertTrue(app.buttons["atlas_home_row"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["atlas_home_row"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["home_sheet"].firstMatch.waitForExistence(timeout: 15))
        usleep(1_500_000)
        app.otherElements["home_map"].firstMatch.tap()
        // Дом поставлен — в пикере появилась СВОЯ метка с собственным именем.
        XCTAssertTrue(app.otherElements["home_pin_picker"].firstMatch
            .waitForExistence(timeout: 10), "дом не встал по тапу в пикере")

        // Закрываем лист и УБЕЖДАЕМСЯ, что он закрылся: прежняя редакция
        // теста этого не проверяла, тыкала в метку ПИКЕРА и проходила на
        // экране, где карточки не было вовсе.
        let close = app.buttons["atlas_controls_close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "у листа дома нет кнопки ×")
        close.tap()
        usleep(2_500_000)
        XCTAssertFalse(app.otherElements["home_sheet"].firstMatch.exists,
                       "лист дома не закрылся — до карты не добраться")

        let pin = app.otherElements["home_pin"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 15), "метки дома нет на «Атласе»")
        pin.tap()
        XCTAssertTrue(app.otherElements["atlas_home_card"].firstMatch.waitForExistence(timeout: 10),
                      "карточка дома не открылась по нажатию на метку")
        usleep(1_000_000)
        snap(app, "a26_home_card")
    }

    // MARK: -

    private func launch(extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-appLanguage", "ru", "-appThemeMode", "dark",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ] + extra
        app.launch()
        return app
    }

    private func openAtlas(_ app: XCUIApplication) {
        let atlas = app.buttons["tab_maps"].firstMatch
        XCTAssertTrue(atlas.waitForExistence(timeout: 30))
        atlas.tap()
        sleep(4)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
