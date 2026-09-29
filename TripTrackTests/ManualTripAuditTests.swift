import XCTest
import CoreLocation
@testable import TripTrack

/// Три дыры, найденные разбором ручной поездки перед тем, как она стала
/// платной (29 сен 2026, `docs/releases/0.8.4/manual-trip-audit.md`).
///
/// Все три молчали: поездка с финишем в будущем ложилась в базу без единого
/// слова, пустая строка «Через» оставалась в форме после отмены поиска, а
/// неудачная запись не оставляла на экране НИЧЕГО. У бесплатной функции это
/// досада; у той, за которую заплатили, — «я купил, и оно сломано».
@MainActor
final class ManualTripAuditTests: XCTestCase {

    private let krasnodar = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)
    private let goryachy = CLLocationCoordinate2D(latitude: 44.6300, longitude: 39.1300)

    // MARK: - Поездка обязана быть законченной

    func testTripThatHasNotEndedYetIsRefused() {
        let now = Date()
        let draft = ManualTripBuilder.Draft(
            coordinates: [krasnodar, goryachy],
            // Выехал полчаса назад, ехал три часа — финиш через два с
            // половиной. Такой поездки ещё не было.
            startDate: now.addingTimeInterval(-1800),
            duration: 3 * 3600
        )
        XCTAssertNil(ManualTripBuilder.build(draft, now: now),
                     "поездка с финишем в будущем не должна собираться")
    }

    func testTripThatEndedIsBuilt() {
        let now = Date()
        let draft = ManualTripBuilder.Draft(
            coordinates: [krasnodar, goryachy],
            startDate: now.addingTimeInterval(-4 * 3600),
            duration: 3 * 3600
        )
        XCTAssertNotNil(ManualTripBuilder.build(draft, now: now))
    }

    /// Граница включающая: поездка, закончившаяся ровно сейчас, закончилась.
    func testATripEndingExactlyNowCounts() {
        let now = Date()
        XCTAssertTrue(ManualTripBuilder.hasEnded(
            startDate: now.addingTimeInterval(-3600), duration: 3600, now: now))
        XCTAssertFalse(ManualTripBuilder.hasEnded(
            startDate: now.addingTimeInterval(-3600), duration: 3601, now: now))
    }

    /// Экран и сборка считают правило ОДНОЙ функцией — иначе кнопка осталась
    /// бы живой у поездки, которую `build` молча отказывается собирать.
    func testTheSheetRefusesTheSameTripTheBuilderRefuses() {
        let model = ManualTripModel()
        model.startDate = Date().addingTimeInterval(-1800)
        model.duration = 3 * 3600
        XCTAssertTrue(model.endsLater)
        XCTAssertFalse(model.canCreate, "кнопка обязана быть выключена")

        model.startDate = Date().addingTimeInterval(-6 * 3600)
        XCTAssertFalse(model.endsLater)
    }

    // MARK: - Пустая заготовка «Через»

    func testCancellingTheSearchDropsTheEmptyStop() {
        let model = ManualTripModel()
        model.via.append(ManualTripPoint(name: "", coordinate: CLLocationCoordinate2D()))
        XCTAssertEqual(model.via.count, 1)

        XCTAssertTrue(model.discardPlaceholderVia(at: 0))
        XCTAssertTrue(model.via.isEmpty, "пустая строка «Через» осталась в форме")
    }

    /// Заполненную точку «Отмена» трогать не имеет права: человек её выбрал.
    func testCancellingTheSearchKeepsAStopThatHasAPlace() {
        let model = ManualTripModel()
        model.via.append(ManualTripPoint(name: "Горячий Ключ", coordinate: goryachy))

        XCTAssertFalse(model.discardPlaceholderVia(at: 0))
        XCTAssertEqual(model.via.count, 1)
    }

    /// Индекс приходит из состояния экрана и переживает удаление строки
    /// кнопкой «минус», пока открыт поиск, — выход за границы обязан быть
    /// отказом, а не падением.
    func testDiscardingOutOfRangeIsSafe() {
        let model = ManualTripModel()
        XCTAssertFalse(model.discardPlaceholderVia(at: 0))
        XCTAssertFalse(model.discardPlaceholderVia(at: -1))
        XCTAssertFalse(model.discardPlaceholderVia(at: 7))
    }

    // MARK: - Отказ записи называет себя

    /// Два случая с РАЗНЫМИ словами. Общее «не удалось» на оба заставило бы
    /// человека с кончившейся подпиской жать кнопку, пока не устанет.
    func testTheTwoRefusalsSayDifferentThings() {
        for lang in LanguageManager.Language.allCases {
            let noAccess = AppStrings.manualTripErrorNoAccess(lang)
            let notSaved = AppStrings.manualTripErrorNotSaved(lang)
            XCTAssertNotEqual(noAccess, notSaved, "\(lang): один текст на два отказа")
            XCTAssertFalse(noAccess.isEmpty)
            XCTAssertFalse(notSaved.isEmpty)
        }
    }

    /// Ключ без строки в таблице откатывается на АНГЛИЙСКИЙ — то есть
    /// выглядит рабочим и молчит. Ловится только сравнением.
    func testTheNewLinesAreTranslatedEverywhere() {
        let strings: [(String, (LanguageManager.Language) -> String)] = [
            ("manualTripErrorEndsLater", AppStrings.manualTripErrorEndsLater),
            ("manualTripErrorNotSaved", AppStrings.manualTripErrorNotSaved),
            ("manualTripErrorNoAccess", AppStrings.manualTripErrorNoAccess),
        ]
        for (name, fn) in strings {
            let en = fn(.en)
            for lang in [LanguageManager.Language.ru, .de, .es, .fr, .it,
                         .pl, .id, .tr, .fil, .uk, .kk, .pt] {
                XCTAssertNotEqual(fn(lang), en, "\(name): у \(lang) строка осталась английской")
            }
        }
    }

    // MARK: - Пустой поиск

    /// Пустой список означал три разных вещи сразу. Теперь «ищем» отделено от
    /// «не нашлось» — иначе экран краснел бы «Ничего не найдено» в ту долю
    /// секунды, пока `MKLocalSearchCompleter` ещё думает.
    func testSearchingIsToldApartFromFoundNothing() {
        let model = ManualTripModel()
        XCTAssertFalse(model.isSearching, "до набора ничего не ищется")

        model.updateSearch("Кр")
        XCTAssertTrue(model.isSearching, "запрос ушёл, ответа ещё нет")

        // Короткий запрос запроса не делает вовсе.
        model.updateSearch("К")
        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.completions.isEmpty)
    }
}
