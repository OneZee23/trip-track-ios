import XCTest
@testable import TripTrack

/// Цвет линии маршрута (0.8.0, спека §2, пункт 4) — единственная косметика,
/// которая никуда не уезжает: выбор локальный, в `UserDefaults`.
final class RouteLineStyleTests: XCTestCase {

    private var savedStyle: String?
    private var savedMirror: Bool!

    override func setUp() {
        super.setUp()
        // Тест пишет в ОБЩИЙ `UserDefaults` — другого хранилища у этого
        // выбора нет, — поэтому прежние значения снимаются и возвращаются:
        // не отпущенное состояние роняет чужой класс через три буквы
        // алфавита (ловушка из CLAUDE.md).
        savedStyle = UserDefaults.standard.string(forKey: RouteLineStyle.storageKey)
        savedMirror = UserDefaults.standard.bool(forKey: RouteLineStyle.plusMirrorKey)
    }

    override func tearDown() {
        if let savedStyle {
            UserDefaults.standard.set(savedStyle, forKey: RouteLineStyle.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RouteLineStyle.storageKey)
        }
        UserDefaults.standard.set(savedMirror, forKey: RouteLineStyle.plusMirrorKey)
        savedStyle = nil
        savedMirror = nil
        super.tearDown()
    }

    func testSixColoursPlusTheFreeGradient() {
        XCTAssertEqual(RouteLineStyle.allCases.filter(\.isPlus).count, 6)
        XCTAssertFalse(RouteLineStyle.speed.isPlus)
        // У градиента ОДНОГО цвета не существует — и именно этим `nil` места
        // отрисовки отличают два режима, без второго флага рядом.
        XCTAssertNil(RouteLineStyle.speed.uiColor)
        for style in RouteLineStyle.allCases.filter(\.isPlus) {
            XCTAssertNotNil(style.uiColor, "\(style.rawValue)")
            XCTAssertFalse(style.displayName.isEmpty, "\(style.rawValue)")
        }
    }

    func testChoiceSurvivesInUserDefaults() {
        RouteLineStyle.stored = .violet
        XCTAssertEqual(RouteLineStyle.stored, .violet)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: RouteLineStyle.storageKey), "violet")

        RouteLineStyle.stored = .speed
        XCTAssertEqual(RouteLineStyle.stored, .speed)
    }

    func testUnknownStoredValueFallsBackToTheGradient() {
        UserDefaults.standard.set("sparkle", forKey: RouteLineStyle.storageKey)
        XCTAssertEqual(RouteLineStyle.stored, .speed)
    }

    func testWithoutPlusTheLineIsTheSpeedGradientAgain() {
        for style in RouteLineStyle.allCases.filter(\.isPlus) {
            XCTAssertEqual(style.effective(isPlus: false), .speed, "\(style.rawValue)")
            XCTAssertEqual(style.effective(isPlus: true), style, "\(style.rawValue)")
        }
    }

    /// «Плюс» кончился — рисуется градиент, но ВЫБОР В ХРАНИЛИЩЕ ЦЕЛ: продлил
    /// подписку, и цвет вернулся сам (спека §2, «когда Плюс кончился»).
    func testTheChoiceIsNotErasedWhenPlusLapses() {
        RouteLineStyle.stored = .crimson
        RouteLineStyle.rememberPlus(false)

        XCTAssertNil(RouteLineStyle.currentUIColor, "без подписки — градиент")
        XCTAssertEqual(RouteLineStyle.stored, .crimson, "выбор стёрли")

        RouteLineStyle.rememberPlus(true)
        XCTAssertEqual(RouteLineStyle.currentUIColor, RouteLineStyle.crimson.uiColor)
    }

    /// Жилка «Атласа» и маршрут на экране поездки красятся ОДНИМ цветом: две
    /// карты в одном приложении не имеют права рисовать пройденное по-разному.
    func testTheAtlasVeinTakesTheSameColour() {
        RouteLineStyle.stored = .teal
        RouteLineStyle.rememberPlus(true)
        XCTAssertEqual(RouteVeinRenderer.veinColor, RouteLineStyle.teal.uiColor)

        RouteLineStyle.rememberPlus(false)
        XCTAssertEqual(RouteVeinRenderer.veinColor, RouteVeinRenderer.defaultVeinColor)
    }
}
