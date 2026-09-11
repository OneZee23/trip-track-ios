import XCTest
@testable import TripTrack

/// Подписи единиц — три функции `AppStrings`, которые зовёт один `Measure`.
///
/// Между «км» и «милей» разница структурная, а не словарная: «км» — символ и
/// не склоняется нигде, а миля в русском и украинском — обычное
/// существительное женского рода. Подстановка одной строки вместо другой даёт
/// «5 миля» — то, что читается как машинный перевод и портит впечатление от
/// всего экрана сильнее, чем неверная цифра.
///
/// Отдельно проверяется то, чего не видно: у ДРОБНОГО числа своя форма. CLDR
/// смотрит на запись, а не на значение, поэтому «2,0» — дробное, и по-русски
/// это «2,0 мили», а не «2,0 миля».
final class UnitLabelTests: XCTestCase {

    private let langs = LanguageManager.Language.allCases

    private func miles(_ lang: LanguageManager.Language, _ value: Double, _ digits: Int = 0) -> String {
        AppStrings.unitDistanceShort(lang, unit: .miles, value: value, fractionDigits: digits)
    }

    private func feet(_ lang: LanguageManager.Language, _ value: Double, _ digits: Int = 0) -> String {
        AppStrings.unitElevationShort(lang, unit: .miles, value: value, fractionDigits: digits)
    }

    // MARK: - Миля склоняется

    func testRussianMileDeclines() {
        XCTAssertEqual(miles(.ru, 1), "миля")
        XCTAssertEqual(miles(.ru, 2), "мили")
        XCTAssertEqual(miles(.ru, 5), "миль")
        XCTAssertEqual(miles(.ru, 11), "миль")
        XCTAssertEqual(miles(.ru, 21), "миля")
        XCTAssertEqual(miles(.ru, 111), "миль")
        XCTAssertEqual(miles(.ru, 143), "мили")
    }

    func testUkrainianMileDeclines() {
        XCTAssertEqual(miles(.uk, 1), "миля")
        XCTAssertEqual(miles(.uk, 2), "милі")
        XCTAssertEqual(miles(.uk, 5), "миль")
        XCTAssertEqual(miles(.uk, 21), "миля")
    }

    /// Дробное число берёт свою форму, и решает её ЗАПИСЬ, а не значение:
    /// «2,0» — дробное, хотя после запятой ноль.
    func testFractionTakesItsOwnForm() {
        XCTAssertEqual(miles(.ru, 1.5, 1), "мили")
        XCTAssertEqual(miles(.ru, 8.4, 1), "мили")
        XCTAssertEqual(miles(.ru, 2.0, 1), "мили")
        XCTAssertEqual(miles(.ru, 21.0, 1), "мили")
        XCTAssertEqual(miles(.uk, 1.5, 1), "милі")
        // Тот же 21 без десятых — уже именительный.
        XCTAssertEqual(miles(.ru, 21.0, 0), "миля")
    }

    /// Украинский фут — единственное место, где дробная форма не совпала с
    /// формой для двух-четырёх. Ради этого расхождения дробь и заведена
    /// отдельной категорией, а не «сойдёт за `few`».
    func testUkrainianFootPartsWithTheFewForm() {
        XCTAssertEqual(feet(.uk, 2), "фути")
        XCTAssertEqual(feet(.uk, 1.5, 1), "фута")
        XCTAssertEqual(feet(.ru, 2), "фута")
        XCTAssertEqual(feet(.ru, 1.5, 1), "фута")
        XCTAssertEqual(feet(.ru, 1), "фут")
        XCTAssertEqual(feet(.ru, 5), "футов")
        XCTAssertEqual(feet(.uk, 5), "футів")
    }

    // MARK: - Одна форма и символ

    /// Казахский и индонезийский формы не считают вовсе — как `nounTrips` для
    /// них же.
    func testSingleFormLanguagesNeverChange() {
        for value in [0.0, 1, 2, 5, 21, 143] {
            XCTAssertEqual(miles(.kk, value), "миля")
            XCTAssertEqual(miles(.id, value), "mi")
            XCTAssertEqual(feet(.kk, value), "фут")
            XCTAssertEqual(feet(.id, value), "ft")
        }
        XCTAssertEqual(miles(.kk, 1.5, 1), "миля")
        XCTAssertEqual(miles(.id, 1.5, 1), "mi")
    }

    /// Там, где миля — символ, он один на все числа. Проверяется списком, а не
    /// «всё остальное», чтобы новый язык пришлось решить, а не унаследовать.
    func testSymbolLanguagesKeepTheSymbol() {
        for lang in [LanguageManager.Language.en, .de, .es, .fr, .it, .pl, .pt, .fil, .tr] {
            for value in [1.0, 2, 5, 21] {
                XCTAssertEqual(miles(lang, value), "mi", "\(lang.rawValue) на \(value)")
                XCTAssertEqual(feet(lang, value), "ft", "\(lang.rawValue) на \(value)")
            }
            XCTAssertEqual(miles(lang, 1.5, 1), "mi")
        }
    }

    // MARK: - Километр не склоняется никогда

    /// «км» — символ во всех тринадцати. Если однажды он начнёт меняться от
    /// числа, разъедется вся метрическая половина приложения разом.
    func testKilometreLabelNeverChanges() {
        for lang in langs {
            let reference = AppStrings.unitDistanceShort(
                lang, unit: .km, value: 1, fractionDigits: 0)
            for value in [0.0, 2, 5, 11, 21, 1234] {
                XCTAssertEqual(
                    AppStrings.unitDistanceShort(lang, unit: .km, value: value, fractionDigits: 0),
                    reference, "\(lang.rawValue) склонил километр на \(value)")
            }
            XCTAssertEqual(
                AppStrings.unitDistanceShort(lang, unit: .km, value: 1.5, fractionDigits: 1),
                reference)
            XCTAssertEqual(reference, AppStrings.km(lang))
        }
    }

    // MARK: - Скорость

    /// mph — символ, и склонять его нечем. Зато сокращение часа разное, и оно
    /// ровно то же, что в метрической таблице рядом.
    func testSpeedLabels() {
        XCTAssertEqual(AppStrings.unitSpeedShort(.en, unit: .miles), "mph")
        XCTAssertEqual(AppStrings.unitSpeedShort(.de, unit: .miles), "mph")
        XCTAssertEqual(AppStrings.unitSpeedShort(.ru, unit: .miles), "миль/ч")
        XCTAssertEqual(AppStrings.unitSpeedShort(.uk, unit: .miles), "миль/год")
        XCTAssertEqual(AppStrings.unitSpeedShort(.kk, unit: .miles), "миль/сағ")
        XCTAssertEqual(AppStrings.unitSpeedShort(.tr, unit: .miles), "mil/sa")
        for lang in langs {
            XCTAssertEqual(AppStrings.unitSpeedShort(lang, unit: .km), AppStrings.kmh(lang))
        }
    }

    // MARK: - Пустых подписей не бывает

    /// Пустая подпись — это «128» без единицы, то есть число, которое ничего
    /// не значит. Английский фолбэк здесь не спасает: подписи собраны
    /// переключателем, а не таблицей, и забытый язык не соберётся вовсе —
    /// но забытый ПРОБЕЛ соберётся.
    func testNoLanguageReturnsAnEmptyLabel() {
        for lang in langs {
            for unit in DistanceUnit.allCases {
                for digits in [0, 1] {
                    for value in [0.0, 1, 2, 5, 21] {
                        XCTAssertFalse(
                            AppStrings.unitDistanceShort(
                                lang, unit: unit, value: value, fractionDigits: digits)
                                .trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(lang.rawValue)/\(unit.rawValue) без подписи расстояния")
                        XCTAssertFalse(
                            AppStrings.unitElevationShort(
                                lang, unit: unit, value: value, fractionDigits: digits)
                                .trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(lang.rawValue)/\(unit.rawValue) без подписи высоты")
                    }
                }
                XCTAssertFalse(
                    AppStrings.unitSpeedShort(lang, unit: unit)
                        .trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(lang.rawValue)/\(unit.rawValue) без подписи скорости")
            }
        }
    }

    // MARK: - Единица ВНУТРИ слова

    /// Заголовок «Километры по месяцам» стоит НАД мильным графиком, если не
    /// спросить у него единицу. Это не опечатка и не мелочь: подпись и число
    /// здесь разнесены по разным строкам экрана, и разойтись им нечему
    /// помешать, кроме этого теста.
    func testMonthlyChartTitleFollowsTheUnit() {
        for lang in langs {
            let km = AppStrings.statsKmByMonth(lang, unit: .km)
            let mi = AppStrings.statsKmByMonth(lang, unit: .miles)
            XCTAssertFalse(km.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(lang.rawValue): пустой заголовок")
            XCTAssertFalse(mi.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(lang.rawValue): пустой заголовок в милях")
            XCTAssertNotEqual(km, mi,
                              "\(lang.rawValue): в милях заголовок не изменился")
        }
        XCTAssertEqual(AppStrings.statsKmByMonth(.ru, unit: .km), "Километры по месяцам")
        XCTAssertEqual(AppStrings.statsKmByMonth(.ru, unit: .miles), "Мили по месяцам")
        XCTAssertEqual(AppStrings.statsKmByMonth(.en, unit: .miles), "Miles by month")
    }

    /// «212-й км» → «132-я миля»: меняется И число, И род порядкового.
    ///
    /// Вторая функция написана целиком, а не вторым аргументом к первой,
    /// именно из-за рода: «миля» в русском и украинском женского, и подстановка
    /// слова дала бы «212-й миля».
    func testChartMarkConvertsTheNumberAndDeclinesTheWord() {
        // 212 км — это 131.7 мили.
        XCTAssertEqual(AppStrings.chartDistanceMark(.ru, unit: .km, km: 212), "212-й км")
        XCTAssertEqual(AppStrings.chartDistanceMark(.ru, unit: .miles, km: 212), "132-я миля")
        XCTAssertEqual(AppStrings.chartDistanceMark(.uk, unit: .miles, km: 212), "132-та миля")
        XCTAssertEqual(AppStrings.chartDistanceMark(.kk, unit: .miles, km: 212), "132-миля")
        XCTAssertEqual(AppStrings.chartDistanceMark(.en, unit: .miles, km: 212), "mi 132")
        // Ни один язык не отдаёт пустое и ни один не оставляет «km» в мильной
        // подписи — вот это и было живой поломкой до 0.6.7.
        for lang in langs {
            let mark = AppStrings.chartDistanceMark(lang, unit: .miles, km: 212)
            XCTAssertFalse(mark.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(lang.rawValue): пустая подпись графика")
            XCTAssertFalse(mark.lowercased().contains("km"),
                           "\(lang.rawValue): в милях осталось «km» — \(mark)")
            XCTAssertFalse(mark.contains("км"),
                           "\(lang.rawValue): в милях осталось «км» — \(mark)")
            XCTAssertTrue(mark.contains("132"),
                          "\(lang.rawValue): число не перевелось — \(mark)")
        }
    }
}
