import XCTest

/// Карта-герой обязана ПЕРЕЖИТЬ поход на полный экран и обратно.
///
/// Владелец на устройстве 23 сентября: «нажимаю на полноэкранный формат карты,
/// захожу в неё, потом выхожу, попадаю в деталку — и карта уже просто чёрный
/// прямоугольник». Металл, на который карту поездки перевели накануне, тут ни
/// при чём — со снятым `FogMetalAvailability.isEnabled` прямоугольник ровно
/// тот же. Разбирая полноэкранное представление, SwiftUI снимал общую
/// `MKMapView` с родителя, которым к тому времени был уже слот героя (см.
/// `TripMapSlotView`).
///
/// Почему кадром, а не состоянием. «Карта видна» — это ровно про то, что на
/// экране: и хост, и координатор, и `visibleMapRect` у пустого героя остаются
/// правильными, отвечать на вопрос им нечем. А `FullscreenMapExpansionShotTests`
/// рядом кадры снимает, но ничего про них не утверждает — и эту поломку
/// пропустил молча, потому что его последний тап уходит в просмотрщик снимка.
final class TripHeroAfterFullscreenTests: XCTestCase {
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

    func test_hero_map_survives_the_trip_to_fullscreen_and_back() {
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

        // Точка отсчёта: насколько герой РАЗНЫЙ до похода. Средний свет тут
        // не годится вовсе — пустая тёмная плашка и ночная карта светят почти
        // одинаково, и первая редакция этого теста именно поэтому прошла на
        // сломанном экране. Разброс различает их сразу: у карты есть маршрут,
        // подписи и подпись Apple, у плашки нет ничего.
        let beforeGrid = HeroMapProbe.heroGrid(XCUIScreen.main.screenshot())
        let before = HeroMapProbe.contrast(beforeGrid)
        snap("hero_before")
        XCTAssertGreaterThan(before, HeroMapProbe.flat,
                             "герой пустой ещё ДО полного экрана — сломано раньше")

        let expand = app.buttons.matching(identifier: "detail_map_expand").firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 8), "нет кнопки «развернуть»")
        expand.tap()

        let close = app.buttons.matching(identifier: "fullscreen_map_close").firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8), "полный экран не открылся")
        usleep(1_500_000)
        close.tap()
        // Пружина возврата — 0.38/0.9; двух секунд хватает и ей, и кадру,
        // который карта обязана нарисовать, вернувшись в слот.
        usleep(2_000_000)

        let afterGrid = HeroMapProbe.heroGrid(XCUIScreen.main.screenshot())
        let after = HeroMapProbe.contrast(afterGrid)
        snap("hero_after")
        XCTAssertGreaterThan(after, HeroMapProbe.flat,
                             "на месте карты пустой прямоугольник: разброс \(after)")
        XCTAssertGreaterThan(after, before * 0.5,
                             "герой обеднел вдвое после возврата: было \(before), стало \(after)")

        // И камера обязана вернуться ТУДА ЖЕ. Это не придирка к пикселям:
        // маршрут, вписанный в размер полного экрана, а показанный в рамке
        // героя, уезжает узкой полоской под верхний край — карта на месте, а
        // поездки на ней не видно. Один и тот же маршрут при одной и той же
        // камере даёт почти один и тот же кадр, и разойтись этим двум нечем.
        let drift = HeroMapProbe.difference(beforeGrid, afterGrid)
        print("HERO_DRIFT \(drift)")
        XCTAssertLessThan(drift, HeroMapProbe.maxDrift,
                          "камера не вернулась в рамку героя: расхождение \(drift)")
    }

    // Замер кадра — общий с `TripJourneyNavigationTests`: см. `HeroMapProbe`.

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
