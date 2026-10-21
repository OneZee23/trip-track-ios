import XCTest
@testable import TripTrack

/// Три формы месяца и три разных предлога.
///
/// В этом релизе дважды подряд уехала кривая русская строка: сначала
/// «В гараже с апрель 2026 г.» (именительный вместо родительного, плюс «г.»
/// от ICU-шаблона), потом «Продана в сентября 2026» (родительный вместо
/// предложного). Оба раза сборка была зелёная, а увидел это человек на
/// устройстве — потому что проверять форму слова было нечем.
final class MonthCaseTests: XCTestCase {

    /// 12 сентября 2026 — месяц с «мягким» окончанием, на котором ломаются
    /// наивные правила вида «отбросить последнюю букву».
    private let september = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 9, day: 12))!
    private let april = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 4, day: 3))!
    private let may = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 5, day: 3))!
    private let august = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 8, day: 3))!

    // MARK: - Родительный: «с апреля 2026»

    func testGenitiveReadsAfterTheRussianPreposition() {
        let s = StatsPeriodFormat.monthYearGenitive(april, .ru)
        XCTAssertEqual(s, "апреля 2026")
        XCTAssertFalse(s.contains("г."), "«г.» от ICU-шаблона в подпись не годится")
    }

    func testWholeSentenceInGarageSince() {
        XCTAssertEqual(
            AppStrings.inGarageSince(.ru, when: StatsPeriodFormat.monthYearGenitive(april, .ru)),
            "В гараже с апреля 2026")
    }

    /// Третья такая строка, найдена на кадре статистики 21 окт 2026: плашка
    /// внизу экрана писала «С TripTrack с декабрь 2025 г.». Экран звал
    /// `monthYearInline`, хотя доккомментарий строки обещает дату, уже
    /// стоящую в падеже.
    func testStatsPlaqueSinceTakesTheGenitive() {
        let december = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2025, month: 12, day: 5))!
        XCTAssertEqual(
            AppStrings.statsWithTripTrackSince(.ru, date: StatsPeriodFormat.monthYearGenitive(december, .ru)),
            "С TripTrack с декабря 2025")
        let source = try! String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TripTrack/Views/Profile/StatsScreenView.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("statsWithTripTrackSince(\n                    l, date: StatsPeriodFormat.monthYearInline"),
                       "плашка снова получает месяц в именительном падеже")
        XCTAssertTrue(source.contains("date: StatsPeriodFormat.monthYearGenitive(first, l)"))
    }

    // MARK: - Сравнение под итогом статистики (0.9.1)

    /// «Меньше, чем месяцем раньше — 610 км»: месяц по имени не называется,
    /// поэтому падежа, который ICU не умеет, в строке нет ни на одном языке.
    /// Число прошлого периода приезжает вместе с единицей и стоит в строке
    /// ровно один раз; «больше» и «меньше» обязаны различаться.
    func testStatsComparisonNamesNoMonthAndCarriesTheNumber() {
        XCTAssertEqual(AppStrings.statsVsPrevious(.ru, more: false, year: false, previous: "610 км"),
                       "Меньше, чем месяцем раньше — 610 км")
        XCTAssertEqual(AppStrings.statsVsPrevious(.ru, more: true, year: true, previous: "4 210 км"),
                       "Больше, чем годом раньше — 4 210 км")
        for lang in LanguageManager.Language.allCases {
            for year in [false, true] {
                let more = AppStrings.statsVsPrevious(lang, more: true, year: year, previous: "{n}")
                let less = AppStrings.statsVsPrevious(lang, more: false, year: year, previous: "{n}")
                XCTAssertEqual(more.components(separatedBy: "{n}").count, 2, "\(lang.rawValue): \(more)")
                XCTAssertNotEqual(more, less, "\(lang.rawValue): «больше» и «меньше» совпали")
            }
            XCTAssertNotEqual(AppStrings.statsVsPrevious(lang, more: true, year: false, previous: "{n}"),
                              AppStrings.statsVsPrevious(lang, more: true, year: true, previous: "{n}"),
                              "\(lang.rawValue): месяц и год читаются одинаково")
        }
    }

    // MARK: - Предложный: «в сентябре 2026»

    func testPrepositionalIsNotTheGenitive() {
        let prep = StatsPeriodFormat.monthYearPrepositional(september, .ru)
        let gen = StatsPeriodFormat.monthYearGenitive(september, .ru)
        XCTAssertEqual(prep, "сентябре 2026")
        XCTAssertNotEqual(prep, gen, "две формы обязаны различаться, иначе одна из них лишняя")
    }

    /// «мае» и «августе» — те, на которых ломается правило «убрать последнюю
    /// букву и приписать -е».
    func testPrepositionalHandlesTheAwkwardMonths() {
        XCTAssertEqual(StatsPeriodFormat.monthYearPrepositional(may, .ru), "мае 2026")
        XCTAssertEqual(StatsPeriodFormat.monthYearPrepositional(august, .ru), "августе 2026")
    }

    func testWholeSentenceSold() {
        let s = AppStrings.vehicleSoldState(
            .ru, when: StatsPeriodFormat.monthYearPrepositional(september, .ru))
        XCTAssertTrue(s.hasPrefix("Продана в сентябре 2026"), "получилось: \(s)")
        XCTAssertFalse(s.contains("сентября"), "родительный после «в» — это «в сентября»")
    }

    func testUkrainianHasItsOwnPrepositional() {
        XCTAssertEqual(StatsPeriodFormat.monthYearPrepositional(september, .uk), "вересні 2026")
        XCTAssertNotEqual(StatsPeriodFormat.monthYearPrepositional(september, .uk),
                          StatsPeriodFormat.monthYearGenitive(september, .uk))
    }

    // MARK: - Языки без падежей

    /// Там, где месяц не склоняется, обе функции обязаны давать одно и то же —
    /// иначе где-то завелась вторая таблица, которая разъедется с первой.
    func testCaselessLanguagesGetTheSameStringFromBothForms() {
        for lang in [LanguageManager.Language.en, .de, .fr, .it, .es, .pt, .id, .tr, .fil, .kk, .pl] {
            XCTAssertEqual(StatsPeriodFormat.monthYearPrepositional(september, lang),
                           StatsPeriodFormat.monthYearGenitive(september, lang),
                           "\(lang): формы разошлись, хотя месяц не склоняется")
        }
    }

    /// Ни одна форма ни на одном языке не должна быть пустой или тащить
    /// сокращение вроде «г.».
    func testNoFormIsEmptyOrCarriesAnAbbreviation() {
        for lang in LanguageManager.Language.allCases {
            for s in [StatsPeriodFormat.monthYearGenitive(september, lang),
                      StatsPeriodFormat.monthYearPrepositional(september, lang)] {
                XCTAssertFalse(s.isEmpty, "\(lang): пустая форма месяца")
                XCTAssertTrue(s.contains("2026"), "\(lang): в «\(s)» потерялся год")
                XCTAssertFalse(s.contains("г."), "\(lang): «\(s)» тащит сокращение")
            }
        }
    }
}
