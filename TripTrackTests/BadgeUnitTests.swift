import XCTest
@testable import TripTrack

/// Значки в милях: описание переводится, ПОРОГ НЕТ.
///
/// Разделение, ради которого написан весь файл: «42.2 км за одну поездку» —
/// это ЗАПИСЬ правила, и она обязана читаться «26.2 mi» у того, кто меряет
/// дорогу милями. А само правило — 42.195 км — одинаково для всех и не
/// двигается ни на метр: значок лежит в базе разблокированным, и сдвинутый
/// порог изменил бы достижения у всех задним числом. Это единственная поломка
/// версии, которую не чинит следующий релиз.
///
/// Вторая половина файла — про `String(format:)`. Описания стали шаблонами в
/// одиннадцати таблицах, и переводчик, потерявший `%@`, роняет не сборку, а
/// число со экрана; лишний `%` роняет уже процесс. Ни то ни другое не видно
/// по коду, поэтому проверяется перебором: 13 языков × 2 единицы × все значки.
final class BadgeUnitTests: XCTestCase {

    private let langs = LanguageManager.Language.allCases

    /// Один тест ниже трогает общий `UserDefaults` (иначе «выбор не влияет на
    /// правило» не проверить). Прежнее значение возвращается на место, чтобы
    /// прогон не уронил чужой класс: из этого же ключа читает
    /// `DistanceUnit.current`, то есть умолчание окружения всех экранов.
    private var savedUnit: String?

    override func setUp() {
        super.setUp()
        savedUnit = UserDefaults.standard.string(forKey: DistanceUnit.storageKey)
    }

    override func tearDown() {
        if let savedUnit {
            UserDefaults.standard.set(savedUnit, forKey: DistanceUnit.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: DistanceUnit.storageKey)
        }
        savedUnit = nil
        super.tearDown()
    }

    private func badge(_ id: String) -> Badge {
        Badge.all.first { $0.id == id }!
    }

    // MARK: - Порог не двигается

    /// Сводка без единого достижения — от неё пляшут пороги ниже.
    private func stats(
        totalDistanceKm: Double = 0,
        maxSpeedKmh: Double = 0,
        longestTripKm: Double = 0,
        maxAltitude: Double = 0,
        maxElevationGainSingleTrip: Double = 0,
        hasSingleTripMarathon: Bool = false,
        hasSingleTripIronButt: Bool = false
    ) -> BadgeStats {
        BadgeStats(
            totalTrips: 0, totalDistanceKm: totalDistanceKm, maxSpeedKmh: maxSpeedKmh,
            totalDurationHours: 0, uniqueRegions: 0, longestTripKm: longestTripKm,
            hasNightTrip: false, hasEarlyMorningTrip: false, hasLateNightTrip: false,
            maxAltitude: maxAltitude, maxLatitude: 0,
            maxElevationGainSingleTrip: maxElevationGainSingleTrip,
            currentStreak: 0, bestStreak: 0,
            hasSingleTripMarathon: hasSingleTripMarathon,
            hasSingleTripIronButt: hasSingleTripIronButt,
            longestSingleTripDuration: 0, hasSundayTrip: false, hasWeekendWarrior: false,
            hasWinterMountainTrip: false, hasSeaLevelTrip: false, countriesCount: 0,
            hasAfterMidnightTrip: false, distinctMonthsWithTrips: 0,
            maxTripsOnSingleVehicle: 0, privateTripCount: 0)
    }

    /// Экватор — это 40 075 км у всех, и американец получает значок на тех же
    /// сорока тысячах километров (24 901 миля), а не на сорока тысячах миль.
    func testThresholdsAreTheSameNumberOfKilometresForEveryone() {
        XCTAssertFalse(badge("equator").checkUnlocked(stats(totalDistanceKm: 40_074)))
        XCTAssertTrue(badge("equator").checkUnlocked(stats(totalDistanceKm: 40_075)))

        XCTAssertFalse(badge("marathon_100").checkUnlocked(stats(longestTripKm: 99)))
        XCTAssertTrue(badge("marathon_100").checkUnlocked(stats(longestTripKm: 100)))

        XCTAssertFalse(badge("speed_demon").checkUnlocked(stats(maxSpeedKmh: 119)))
        XCTAssertTrue(badge("speed_demon").checkUnlocked(stats(maxSpeedKmh: 120)))

        XCTAssertFalse(badge("mountain_goat")
            .checkUnlocked(stats(maxElevationGainSingleTrip: 999)))
        XCTAssertTrue(badge("mountain_goat")
            .checkUnlocked(stats(maxElevationGainSingleTrip: 1000)))

        XCTAssertFalse(badge("above_clouds").checkUnlocked(stats(maxAltitude: 1999)))
        XCTAssertTrue(badge("above_clouds").checkUnlocked(stats(maxAltitude: 2000)))
    }

    /// Правило не читает единицу вовсе — ни прямо, ни через `BadgeFigure`.
    /// Проверяется тем же способом, каким проверяется одометр: выбор меняется,
    /// ответ не меняется.
    func testTheChoiceOfUnitCannotUnlockOrLockABadge() {
        let onTheLine = stats(totalDistanceKm: 40_075, maxSpeedKmh: 120,
                              longestTripKm: 300, maxAltitude: 2000,
                              maxElevationGainSingleTrip: 1000,
                              hasSingleTripMarathon: true, hasSingleTripIronButt: true)
        let before = Badge.all.map { $0.checkUnlocked(onTheLine) }
        for unit in DistanceUnit.allCases {
            UserDefaults.standard.set(unit.rawValue, forKey: DistanceUnit.storageKey)
            XCTAssertEqual(Badge.all.map { $0.checkUnlocked(onTheLine) }, before,
                           "выбор «\(unit.rawValue)» изменил набор значков")
        }
        UserDefaults.standard.removeObject(forKey: DistanceUnit.storageKey)
    }

    /// Число в тексте обязано совпадать с числом в правиле. Разойтись им проще
    /// всего: они стоят в одной строке кода, но читаются в разное время.
    func testTheFigureInTheTextIsTheFigureInTheRule() {
        XCTAssertEqual(badge("equator").figures.first?.value, 40_075)
        XCTAssertEqual(badge("speed_demon").figures.first?.value, 120)
        XCTAssertEqual(badge("mountain_goat").figures.first?.value, 1000)
        XCTAssertEqual(badge("above_clouds").figures.first?.value, 2000)
        XCTAssertEqual(badge("highway_wolf").figures.first?.value, 300)
        // Марафон — 42.195, а печатается «42.2»: порог точный, запись круглая.
        XCTAssertEqual(badge("marathon_42").figures.first?.value ?? 0, 42.195, accuracy: 1e-9)
    }

    // MARK: - Запись меняется

    func testMilesAreShownInTheDescription() {
        XCTAssertEqual(badge("marathon_42").description(.en, unit: .miles),
                       "26.2 mi in a single trip")
        XCTAssertEqual(badge("equator").description(.en, unit: .miles),
                       "24,901 mi — the equator")
        XCTAssertEqual(badge("speed_demon").description(.en, unit: .miles),
                       "Max speed over 75 mph")
    }

    /// «500+ км» — плюс стоит МЕЖДУ числом и подписью, и переживает перевод:
    /// «311+ mi», а не «500+ mi» и не «311 mi+».
    func testTheAtLeastPlusSurvivesTheConversion() {
        XCTAssertEqual(badge("iron_butt").description(.en, unit: .km),
                       "500+ km in a single trip")
        XCTAssertEqual(badge("iron_butt").description(.en, unit: .miles),
                       "311+ mi in a single trip")
    }

    /// Высота идёт той же настройкой — значок про метры читается в футах.
    func testElevationBadgesFollowTheUnitToo() {
        XCTAssertEqual(badge("mountain_goat").description(.en, unit: .km),
                       "1,000 m elevation gain in one trip")
        XCTAssertEqual(badge("mountain_goat").description(.en, unit: .miles),
                       "3,281 ft elevation gain in one trip")
        XCTAssertEqual(badge("above_clouds").description(.en, unit: .miles),
                       "Altitude 6,562+ ft reached")
    }

    /// Два числа в одном описании: сначала высота, потом расстояние. Порядок
    /// держится позиционными `%1$@`/`%2$@` — голые `%@` однажды поменялись бы
    /// местами в языке с другим порядком слов.
    func testTwoFiguresKeepTheirOrder() {
        XCTAssertEqual(badge("sea_level").description(.en, unit: .km),
                       "Along coastline (altitude <10 m, >20 km)")
        XCTAssertEqual(badge("sea_level").description(.en, unit: .miles),
                       "Along coastline (altitude <33 ft, >12 mi)")
    }

    /// Число в описании значка печатает общий форматтер, а не рука
    /// переводчика: одиннадцать таблиц писали марафон кто «42.2», кто «42,2».
    /// Разделитель с 0.6.7 один на приложение — точка (решение владельца).
    func testTheMarathonFigureComesFromTheSharedFormatter() {
        XCTAssertEqual(badge("marathon_42").description(.ru, unit: .km),
                       "42.2 км за одну поездку")
    }

    /// Метрический человек не должен заметить версию: слова те же, число то
    /// же. Пробел в разрядах при этом стал НЕРАЗРЫВНЫМ — это та же правка, что
    /// у всех чисел 0.6.7, и ради неё сравнение нормализует пробелы.
    func testMetricWordingDidNotChange() {
        let expected: [(String, LanguageManager.Language, String)] = [
            ("equator", .ru, "40 075 км — длина экватора"),
            ("equator", .en, "40,075 km — the equator"),
            ("thousand", .ru, "1 000 км суммарно"),
            ("million", .en, "1,000,000 km in a lifetime"),
            ("marathon_100", .ru, "Поездка длиннее 100 км"),
            ("iron_butt", .ru, "500+ км за одну поездку"),
            ("speed_demon", .ru, "Макс. скорость > 120 км/ч"),
            ("speed_demon", .uk, "Макс. швидкість > 120 км/год"),
            ("expedition", .ru, "50 000 км в сумме"),
        ]
        for (id, lang, was) in expected {
            let now = badge(id).description(lang, unit: .km)
            XCTAssertEqual(spaces(now), spaces(was), "\(id)/\(lang.rawValue)")
        }
    }

    private func spaces(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Единственное, что у метрического человека всё-таки изменилось, и
    /// изменилось к лучшему: число печатает общий форматтер, а не рука
    /// переводчика. Поэтому тысяча наконец разделена по правилам языка —
    /// «1 000 м» по-русски, «1,000 m» по-английски, «1.000 m» по-немецки, — а
    /// не так, как её записали в одиннадцати таблицах вразнобой.
    func testTheNumberNowGroupsByLanguage() {
        XCTAssertEqual(badge("above_clouds").description(.uk, unit: .km),
                       "Висота 2\u{00A0}000+ м")
        XCTAssertEqual(badge("mountain_goat").description(.de, unit: .km),
                       "1.000 m Höhenmeter in einer Fahrt")
        XCTAssertEqual(badge("thousand").description(.de, unit: .km), "1.000 km insgesamt")
    }

    // MARK: - Шаблоны целы во всех тринадцати языках

    /// Потерянный переводчиком `%@` не роняет сборку — он молча роняет число
    /// со экрана. Лишний `%` роняет уже процесс, на `String(format:)`.
    func testEveryTemplateHasExactlyAsManyPlaceholdersAsFigures() {
        let specifier = try! NSRegularExpression(pattern: "%(\\d+\\$)?@")
        for badge in Badge.all {
            for lang in langs {
                let template = AppStrings.tr(
                    lang, "badge.\(badge.id).desc",
                    ru: badge.descriptionRu, en: badge.descriptionEn)
                let range = NSRange(template.startIndex..., in: template)
                let found = specifier.numberOfMatches(in: template, range: range)
                XCTAssertEqual(found, badge.figures.count,
                               "\(badge.id)/\(lang.rawValue): «\(template)»")
                // Любой другой процент — это либо забытый `%d`, либо опечатка,
                // и оба падают внутри `String(format:)`, а не здесь.
                XCTAssertEqual(template.filter { $0 == "%" }.count, badge.figures.count,
                               "\(badge.id)/\(lang.rawValue): лишний «%» в «\(template)»")
            }
        }
    }

    /// Итог перебором: ни одно описание ни на одном языке и ни в одной единице
    /// не отдаёт остатков форматирования.
    func testNoDescriptionLeaksFormattingInAnyLanguageOrUnit() {
        for badge in Badge.all {
            for lang in langs {
                for unit in DistanceUnit.allCases {
                    let text = badge.description(lang, unit: unit)
                    XCTAssertFalse(text.contains("%"),
                                   "\(badge.id)/\(lang.rawValue)/\(unit.rawValue): \(text)")
                    XCTAssertFalse(text.contains("(null)"),
                                   "\(badge.id)/\(lang.rawValue)/\(unit.rawValue): \(text)")
                    XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty,
                                   "\(badge.id)/\(lang.rawValue): пустое описание")
                }
            }
        }
    }

    /// А в милях — ещё и ни одного километра в тексте. Ровно это и было бы
    /// видно человеку, если бы шаг «значки» вырезали: единственное метрическое
    /// место приложения.
    func testNoBadgeWithAFigureStillSaysKilometres() {
        for badge in Badge.all where !badge.figures.isEmpty {
            for lang in langs {
                let text = badge.description(lang, unit: .miles)
                XCTAssertFalse(text.contains("км"), "\(badge.id)/\(lang.rawValue): \(text)")
                XCTAssertFalse(text.lowercased().contains("km"),
                               "\(badge.id)/\(lang.rawValue): \(text)")
            }
        }
    }
}
