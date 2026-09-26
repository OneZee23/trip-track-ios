import XCTest

/// Кадры вкладки «Места» (0.8.0): она перестала быть одной строкой на пустом
/// экране.
///
/// Проверять это можно только снимком: «экран выглядит пустым» — жалоба
/// владельца с устройства, и ни одно возвращаемое значение на неё не
/// отвечает. Два кадра — два состояния библиотеки: одно место (как на
/// скриншоте жалобы) и несколько.
///
/// Места заводит сверка на запуске (`PlaceManager.reconcile`), поэтому
/// карточки приезжают позже самой вкладки — как в `PlaceDetailShotTests`.
private func snapshot(_ test: XCTestCase, _ app: XCUIApplication, _ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    test.add(shot)
}

/// Второй запуск, а не первый: на симуляторе `CLGeocoder` молчит, и
/// `TripManager` кладёт это молчание в кэш геокодера поверх засеянных имён
/// (`saveGeocodeCache` пишет `nil`). Сид чинит пустую строку при следующем
/// старте — и только тогда подсказки называются «Краснодар», а не «Точка на
/// карте». На телефоне кэш тёплый и без этого.
private func relaunchWithWarmGeocodeCache(_ app: XCUIApplication) {
    app.terminate()
    app.launch()
}

private func openPlaces(_ test: XCTestCase, _ app: XCUIApplication) {
    let recovery = app.buttons.matching(identifier: "recovery_continue").firstMatch
    if recovery.waitForExistence(timeout: 3), recovery.isHittable {
        recovery.tap(); sleep(2)
    }
    let tab = app.buttons.matching(identifier: "tab_places").firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 20), "нет вкладки «Места»")
    tab.tap()
    // Подсказки считаются после сверки и с окном склейки — секунды хватает
    // и сверке библиотеки демо-сида, и первому пересчёту.
    let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place_card_'")).firstMatch
    _ = card.waitForExistence(timeout: 60)
    sleep(4)
}

/// Одно место — ровно то состояние, на которое пожаловался владелец.
///
/// Кадр получается таким только на ЧИСТОМ контейнере: сиды идемпотентны и
/// ничего не досевают поверх уже засеянной базы, поэтому прогон следом за
/// соседним классом (у того `-seed-places-rich`) покажет три места вместо
/// одного. Перед прогоном — `xcrun simctl uninstall <udid> <bundle id>`.
final class PlacesTabShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-places-demo",
        ]
        app.launch()
    }

    func test_places_tab_one_place() {
        relaunchWithWarmGeocodeCache(app)
        openPlaces(self, app)
        let suggestion = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'place_suggestion_'")).firstMatch
        XCTAssertTrue(suggestion.exists,
                      "под единственным местом пусто — ради этого волна и делалась\n\(app.debugDescription)")
        snapshot(self, app, "w080_places_one")
    }
}

/// Несколько мест: список, подсказки под ним, булавки обоих видов на карте.
final class PlacesTabRichShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-demo", "-seed-places-rich", "-seed-segment-demo",
        ]
        app.launch()
    }

    func test_places_tab_rich() {
        relaunchWithWarmGeocodeCache(app)
        openPlaces(self, app)
        snapshot(self, app, "w080_places_rich")
        // Подсказки стоят ПОД списком — до них надо доскроллить.
        app.swipeUp()
        sleep(1)
        snapshot(self, app, "w080_places_rich_suggestions")
    }
}

/// Пустая вкладка (S2): ни мест, ни подсказок, ни поездок.
///
/// Кадр получается таким только на ЧИСТОМ контейнере и без единого сида —
/// `simctl uninstall <udid> com.onezee.TripTrack.dev` перед прогоном, иначе
/// база соседнего класса покажет список вместо пустоты.
final class PlacesEmptyShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>"]
        app.launch()
    }

    func test_places_tab_empty() {
        let tab = app.buttons.matching(identifier: "tab_places").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "нет вкладки «Места»")
        tab.tap()
        let empty = app.otherElements["places_empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 20), "пустая вкладка не показалась\n\(app.debugDescription)")
        sleep(2)
        snapshot(self, app, "w081_places_empty")
        // Карточка-образец и три шага обязаны быть в кадре: ради них экран и
        // перестал быть одной надписью «Мест пока нет».
        XCTAssertTrue(app.otherElements["places_how_card"].exists
                      || app.staticTexts["places_how_card"].exists,
                      "нет карточки «как появляются места»")
    }
}
