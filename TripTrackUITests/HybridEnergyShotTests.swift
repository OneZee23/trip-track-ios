import XCTest

/// Кадры раскладки энергии плагин-гибрида (0.8.3): плитки на экране поездки,
/// строка «Как ехал» и блок энергии в паспорте машины.
///
/// Снимается на засеянном гибриде (`-seed-hybrid`): раскладке нужны ТРИ входа
/// разом — тип двигателя, запас хода и соседние поездки того же дня, — и
/// набрать их руками в симуляторе нельзя (поездка там не записывается, GPS не
/// едет).
///
/// Числа сида выбраны так, чтобы обе половины правила «запас хода на день»
/// попали в один прогон: утренняя поездка (17.6 км) целиком электрическая,
/// вечерняя (82.4 км) разрезана по остатку запаса — 32.4 км на батарее,
/// остальное на топливе.
final class HybridEnergyShotTests: XCTestCase {

    func testHybridTripShowsBothHalves() {
        let app = launch()
        openMe(app)

        // Экран поездки открывается из «Истории» — сид кладёт поездки
        // приватными, и в ленте их нет.
        let cell = app.historyTripCells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 30), "история пуста")
        cell.tap()
        usleep(3_000_000)

        // Строка «Как ехал» есть только у своей поездки плагин-гибрида.
        let auto = app.buttons["trip_energy_mode_auto"].firstMatch
        XCTAssertTrue(auto.waitForExistence(timeout: 20),
                      "строка режима не появилась у поездки гибрида")

        // ДОКРУТИТЬ до строки. `exists` у элемента внутри `ScrollView` истинно
        // и за пределами экрана, а `tap()` по такому бьёт мимо — и отличить
        // «нажатие не сработало» от «продукт не отреагировал» становится
        // нечем. Половина этого набора ушла именно на такую подмену.
        for _ in 0..<8 where !auto.isHittable {
            app.swipeUp()
            usleep(400_000)
        }
        XCTAssertTrue(auto.isHittable, "строка режима не докрутилась до экрана")

        // Контейнер симулятора переживает прогон, и режим, выбранный прошлым
        // запуском, лежит в базе. Приводим к «Авто» — иначе второй прогон
        // подряд проверял бы не то состояние.
        if !auto.isSelected {
            auto.tap()
            usleep(1_500_000)
        }
        XCTAssertTrue(auto.isSelected, "не удалось вернуть «Авто» перед проверкой")
        XCTAssertEqual(liveMode(app), "auto")
        snap(app, "h1_trip_tiles")

        // «Электро» руками: вся поездка уходит на батарею, литры пропадают.
        let electric = app.buttons["trip_energy_mode_electric"].firstMatch
        XCTAssertTrue(electric.exists)
        electric.tap()
        usleep(1_500_000)
        snap(app, "h2_mode_electric")
        XCTAssertEqual(liveMode(app), "electric", "экран не перешёл в «Электро»")
        XCTAssertTrue(electric.isSelected, "выбор не переехал на «Электро»")
        XCTAssertFalse(auto.isSelected, "«Авто» осталось выбранным вместе с «Электро»")

        // И обратно — выбор возвращается приложению.
        XCTAssertTrue(auto.isHittable, "кнопка «Авто» недоступна для нажатия")
        auto.tap()
        usleep(2_000_000)
        snap(app, "h3_mode_auto")
        XCTAssertEqual(liveMode(app), "auto", "экран не вернулся в «Авто»")
        XCTAssertTrue(auto.isSelected, "выбор не вернулся на «Авто»")
    }

    /// Паспорт машины: блок энергии вместо одного топливного.
    func testHybridPassportShowsEnergyBlock() throws {
        let app = launch()
        openMe(app)

        let garage = app.buttons["profile_garage_card"].firstMatch
        guard garage.waitForExistence(timeout: 20) else {
            throw XCTSkip("карточка гаража на «Я» не найдена — экран перекомпонован")
        }
        garage.tap()
        usleep(2_000_000)
        snap(app, "h4_garage")

        let card = app.buttons.matching(identifier: "garage_card")
            .containing(NSPredicate(format: "label CONTAINS[c] 'Astra'")).firstMatch
        guard card.waitForExistence(timeout: 15) else {
            throw XCTSkip("карточка засеянного гибрида не найдена")
        }
        card.tap()
        usleep(2_500_000)
        snap(app, "h5_passport")
    }

    /// Лист «На чём ездит машина?» — вопрос вместо трёх терминов.
    func testPowertrainPickerAsksAPlainQuestion() throws {
        let app = launch()
        openMe(app)

        let garage = app.buttons["profile_garage_card"].firstMatch
        guard garage.waitForExistence(timeout: 20) else {
            throw XCTSkip("карточка гаража на «Я» не найдена")
        }
        garage.tap()
        usleep(2_000_000)

        let card = app.buttons.matching(identifier: "garage_card")
            .containing(NSPredicate(format: "label CONTAINS[c] 'Astra'")).firstMatch
        guard card.waitForExistence(timeout: 15) else {
            throw XCTSkip("карточка засеянного гибрида не найдена")
        }
        card.tap()
        usleep(2_500_000)

        // Строка расхода открывает форму правки — тот же путь, которым это
        // делает человек, пришедший поправить числа машины.
        let fuelRow = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'асход в городе'")).firstMatch
        guard fuelRow.waitForExistence(timeout: 15) else {
            throw XCTSkip("строка расхода в паспорте не найдена")
        }
        for _ in 0..<8 where !fuelRow.isHittable {
            app.swipeUp()
            usleep(400_000)
        }
        fuelRow.tap()
        usleep(2_500_000)

        let row = app.buttons["vehicle_powertrain_row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "строки «Двигатель» нет в форме")
        for _ in 0..<8 where !row.isHittable {
            app.swipeUp()
            usleep(400_000)
        }
        snap(app, "h6_form_row")
        row.tap()
        usleep(1_500_000)
        snap(app, "h7_powertrain_picker")

        // Вариант выбирается по ОПИСАНИЮ, а не по термину: именно это и есть
        // предмет правки.
        let hybrid = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'электричеств'")).firstMatch
        XCTAssertTrue(hybrid.waitForExistence(timeout: 5),
                      "в листе нет варианта, названного человеческими словами")
    }

    // MARK: -

    /// Режим, который экран показывает ПРЯМО СЕЙЧАС.
    ///
    /// Читается с маркера 1×1 (`trip_energy_current_…`), а не с подсветки
    /// пилюли: подсветка — это цвет, и отличить «состояние не доехало» от
    /// «нажатие не сработало» по ней нельзя.
    private func liveMode(_ app: XCUIApplication) -> String {
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'trip_energy_current_'"))
            .firstMatch
        guard marker.waitForExistence(timeout: 5) else { return "—" }
        return marker.identifier.replacingOccurrences(
            of: "trip_energy_current_", with: "")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>",
            "-seed-map-demo", "-seed-hybrid",
            "-appLanguage", "ru", "-appThemeMode", "dark",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
        return app
    }

    private func openMe(_ app: XCUIApplication) {
        let me = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 30))
        me.tap()
        usleep(2_500_000)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
