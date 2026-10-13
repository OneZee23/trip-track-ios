import XCTest

/// Кадры новых состояний «Мест»: поиск модальным состоянием и «ничего не
/// нашлось». Скелетон подсказок и «нет сети» кадром не снимаются: первый
/// живёт доли секунды, второму нужна выключенная сеть у симулятора.
final class PlacesStatesShotTests: XCTestCase {

    func testSearchStates() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-demo", "-seed-places-rich", "-seed-places-many",
            "-appLanguage", "ru", "-appThemeMode", "dark",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()

        let places = app.buttons["tab_places"].firstMatch
        XCTAssertTrue(places.waitForExistence(timeout: 30))
        places.tap()
        sleep(4)
        snap(app, "p1_half")

        // Поиск, порядок и группы живут в ПОЛНОМ списке, а вкладка
        // открывается половиной: сначала тянем панель вверх.
        app.otherElements["places_panel_handle"].firstMatch.swipeUp(velocity: .fast)
        usleep(1_500_000)
        snap(app, "p1b_list")

        let field = app.textFields["places_search"].firstMatch
        guard field.waitForExistence(timeout: 15) else {
            // Поиск появляется с восьми мест: у маленькой библиотеки его нет
            // вовсе, и это правило, а не сбой.
            snap(app, "p_no_search_small_library")
            return
        }
        field.tap()
        usleep(1_500_000)
        snap(app, "p2_search_focused")

        // Клавиатура на симуляторе приезжает не мгновенно, а без неё
        // `typeText` падает «нет фокуса» — ждём именно её, а не время.
        _ = app.keyboards.element.waitForExistence(timeout: 10)
        // СТОРОЖ ЧИСЛОМ, а не кадром: панель высокая, и с поднятой
        // клавиатурой она переставала помещаться в контейнер — SwiftUI
        // отвечал на это сдвигом содержимого ВВЕРХ, и поле поиска ложилось
        // на часы (кадр 28 сен, проба показала `top=115` при настоящем
        // `y = −81`). Сдвиг в сорок точек виден глазом, а в пять нет, и
        // поймать его можно только так.
        XCTAssertGreaterThan(field.frame.minY, 60,
                             "поле поиска уехало под часы: панель не поместилась в контейнер")

        field.typeText("Крас")
        usleep(1_200_000)
        snap(app, "p3_search_matches")

        field.typeText("щщщ")
        usleep(1_200_000)
        snap(app, "p4_nothing_found")

        let cancel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'тмен'")).firstMatch
        if cancel.waitForExistence(timeout: 5) {
            cancel.tap()
            usleep(1_200_000)
            snap(app, "p5_back_to_list")
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
