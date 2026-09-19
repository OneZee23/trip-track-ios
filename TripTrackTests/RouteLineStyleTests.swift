import XCTest
import CoreLocation
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
        XCTAssertEqual(RouteVeinRenderer.resolvedVeinColor(), RouteLineStyle.teal.uiColor)

        RouteLineStyle.rememberPlus(false)
        XCTAssertEqual(RouteVeinRenderer.resolvedVeinColor(), RouteVeinRenderer.defaultVeinColor)
    }

    // MARK: - Цена кадра

    private func makeVein() throws -> RouteVeinOverlay {
        try XCTUnwrap(RouteVeinOverlay(route: [
            CLLocationCoordinate2D(latitude: 45.03, longitude: 38.97),
            CLLocationCoordinate2D(latitude: 45.06, longitude: 39.02),
        ]))
    }

    /// Рендерер берёт цвет СНИМКОМ в `init` и больше его не переспрашивает.
    ///
    /// Проверяется это сменой выбора ПОСЛЕ создания: если бы `draw` ходил в
    /// `UserDefaults` (а он ходил до фикс-волны), поле поехало бы за ней. А
    /// поле — единственное, что `draw` читает, см. сторож ниже.
    func testTheRendererSnapshotsTheColourAtInit() throws {
        RouteLineStyle.rememberPlus(true)
        RouteLineStyle.stored = .teal
        let renderer = RouteVeinRenderer(vein: try makeVein())
        XCTAssertEqual(renderer.veinColor, RouteLineStyle.teal.uiColor)

        RouteLineStyle.stored = .lime
        XCTAssertEqual(
            renderer.veinColor, RouteLineStyle.teal.uiColor,
            "цвет пересчитался после init — значит его спрашивают на отрисовке")

        // Новый оверлей — новый снимок: именно так новый цвет и доезжает до
        // карты (`.routeLineStyleChanged` переставляет оверлей).
        XCTAssertEqual(RouteVeinRenderer(vein: try makeVein()).veinColor, RouteLineStyle.lime.uiColor)
    }

    /// Сторож на следующую версию: в `draw(_:zoomScale:in:)` не должно быть ни
    /// `RouteLineStyle`, ни `UserDefaults`. MapKit зовёт его много раз за кадр
    /// и параллельно на нескольких потоках — то же правило, по которому индекс
    /// путей строится в `init`, а не там («Дешёвые тайлы», 0.7.0).
    /// Читает ИСХОДНИК, потому что про строку, которую допишут в 0.9.0,
    /// поведенческий тест не скажет ничего.
    func testDrawNeverReadsUserDefaults() throws {
        let file = UnitGuard.repoRoot()
            .appendingPathComponent("TripTrack/Views/MyMap/RouteVeinOverlay.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let start = try XCTUnwrap(
            text.range(of: "override func draw(_ mapRect: MKMapRect"),
            "переименовали `draw` — сторож ослеп, поправьте его")
        // Тело до конца файла: `draw` в этом файле последний.
        let body = String(text[start.lowerBound...])
        // `Self.veinColor` — форма ИМЕННО того регресса, что чинила эта волна:
        // статическое вычисляемое свойство, за которым стоял `UserDefaults`.
        for token in ["RouteLineStyle", "UserDefaults", "currentUIColor",
                      "Self.veinColor", "resolvedVeinColor"] {
            XCTAssertFalse(
                body.contains(token),
                "`draw` жилки снова спрашивает \(token) — это чтение на каждом кадре")
        }
        // …а цвет он всё-таки берёт — из хранимого поля, а не заново.
        XCTAssertTrue(body.contains("veinColor"), "`draw` перестал красить жилку вовсе?")
        XCTAssertTrue(
            text.contains("let veinColor: UIColor"),
            "снимок цвета перестал быть хранимым полем")
    }

    /// Смена выбора обязана СКАЗАТЬ картам: рендереры держат снимок и сами
    /// ничего не переспрашивают, поэтому без уведомления новый цвет доехал бы
    /// только к следующему показу экрана.
    func testChangingTheChoiceAnnouncesIt() {
        RouteLineStyle.rememberPlus(true)
        RouteLineStyle.stored = .amber

        var heard = 0
        let token = NotificationCenter.default.addObserver(
            forName: .routeLineStyleChanged, object: nil, queue: nil) { _ in heard += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        RouteLineStyle.stored = .ice
        XCTAssertEqual(heard, 1)

        // Тот же выбор второй раз — не событие: переставлять оверлей не за чем.
        RouteLineStyle.stored = .ice
        XCTAssertEqual(heard, 1)

        // Погасшая подписка для карты — та же смена цвета.
        RouteLineStyle.rememberPlus(false)
        XCTAssertEqual(heard, 2)
    }
}
