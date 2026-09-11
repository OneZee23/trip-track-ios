import XCTest
@testable import TripTrack

/// Граница процесса: локскрин, Dynamic Island и часы.
///
/// Всё, что здесь проверяется, нельзя увидеть в приложении и почти нельзя
/// увидеть на симуляторе — это два разных бинарника, которые разговаривают
/// одним `Codable`-состоянием и обязаны печатать одинаково.
///
/// Два свойства, и оба уже ломались:
///
/// 1. **Активность переживает обновление приложения.** Состояние, записанное
///    старым бинарником, декодируется НОВЫМ типом. Синтезированный Swift'ом
///    `Decodable` на пропущенный ключ бросает `keyNotFound` и не смотрит на
///    `= "km"` в объявлении — то есть каждое дописанное поле убивало живую
///    карточку посреди поездки, молча.
/// 2. **Виджет и приложение печатают одно и то же.** У виджета своя копия
///    форматтера (он не видит `Measure`) и своя копия слов (он не видит
///    `AppStrings`). Пока единица была одна и число короткое, копии совпадали
///    случайно: обе печатали «7.7». С милями расходятся и порог десятых, и
///    разряды, и разделитель, и склонение.
final class LiveActivityUnitTests: XCTestCase {

    private typealias State = TripActivityAttributes.ContentState

    private let langs = LanguageManager.Language.allCases

    /// Полный набор того, что рисуют карточка и остров: короткое (десятые),
    /// вокруг порога у обеих единиц, длинное (разряды) и ноль.
    private let kilometres: [Double] = [0, 0.4, 5, 9.6, 9.9, 10, 12.4, 16.09, 42.2, 128.4, 1240, 12_890]

    // MARK: - Старая активность переживает обновление

    /// Состояние, записанное версией до 0.6.7, декодируется и получает
    /// километры.
    ///
    /// Ключей `distanceUnit`, `checkpointCount`, `language`, `isDarkMode` и
    /// `isFinished` в том JSON нет вовсе — это ровно те пять полей, что
    /// дописывались в `ContentState` за время жизни проекта.
    func testStateFromBeforeTheUpdateDecodesAsKilometres() throws {
        let legacy = #"""
        {"speedKmh":62.5,"distanceKm":128.4,"isPaused":false,"pausedDuration":0}
        """#
        let state = try JSONDecoder().decode(State.self, from: Data(legacy.utf8))

        XCTAssertEqual(state.distanceUnit, DistanceUnit.km.rawValue)
        XCTAssertEqual(state.shownUnit, .km)
        // Заодно — остальные четыре, дописанные раньше. Они ломались так же
        // молча, и до 0.6.7 их никто не проверял.
        XCTAssertEqual(state.language, "en")
        XCTAssertFalse(state.isDarkMode)
        XCTAssertFalse(state.isFinished)
        XCTAssertEqual(state.checkpointCount, 0)
        // И то, ради чего активность вообще жива.
        XCTAssertEqual(state.speedKmh, 62.5)
        XCTAssertEqual(state.distanceKm, 128.4)
    }

    /// Обратное: состояние, записанное ВЕРСИЕЙ ИЗ БУДУЩЕГО, с единицей,
    /// которой мы не знаем, тоже не роняет карточку — читается как километры.
    /// Поэтому поле строкой, а не самим `DistanceUnit`: у enum'а с сырым
    /// значением `Decodable` на незнакомой строке бросает.
    func testUnknownUnitReadsAsKilometresInsteadOfThrowing() throws {
        let future = #"""
        {"speedKmh":0,"distanceKm":0,"isPaused":false,"pausedDuration":0,"distanceUnit":"furlongs"}
        """#
        let state = try JSONDecoder().decode(State.self, from: Data(future.utf8))
        XCTAssertEqual(state.shownUnit, .km)
    }

    /// Круговой ход: то, что записали мы, читается нами же без потерь.
    func testRoundTripKeepsTheUnit() throws {
        let state = State(
            speedKmh: 88, distanceKm: 42.2, isPaused: true, pausedDuration: 120,
            language: "ru", isDarkMode: true, checkpointCount: 3,
            distanceUnit: DistanceUnit.miles.rawValue
        )
        let back = try JSONDecoder().decode(State.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back, state)
        XCTAssertEqual(back.shownUnit, .miles)
    }

    // MARK: - Обе стороны границы печатают одно и то же

    /// Расстояние: число И подпись, во всех тринадцати языках и обеих
    /// единицах, побайтово.
    func testWidgetDistanceMatchesTheAppEverywhere() {
        for lang in langs {
            for unit in DistanceUnit.allCases {
                for km in kilometres {
                    let app = Measure.distanceParts(
                        km: km, unit: unit, lang: lang, style: .adaptive)
                    let widget = LiveActivityFormat.distanceParts(
                        km: km, unit: unit, code: lang.rawValue)
                    XCTAssertEqual(
                        widget.value, app.value,
                        "число разошлось: \(lang.rawValue)/\(unit.rawValue) на \(km) км")
                    XCTAssertEqual(
                        widget.unit, app.unit,
                        "подпись разошлась: \(lang.rawValue)/\(unit.rawValue) на \(km) км")
                }
            }
        }
    }

    /// Скорость — так же. Провод везёт км/ч, `Measure` берёт м/с, и перевод
    /// между ними обязан быть незаметен: «68» и «67» на одном и том же
    /// семпле — это ровно то, что человек видит, переводя взгляд с телефона
    /// на локскрин.
    func testWidgetSpeedMatchesTheAppEverywhere() {
        let speeds: [Double] = [0, 3, 13.4, 59.5, 67.9, 90, 112.6, 240]
        for lang in langs {
            for unit in DistanceUnit.allCases {
                for kmh in speeds {
                    let app = Measure.speedParts(ms: kmh / 3.6, unit: unit, lang: lang)
                    let widget = LiveActivityFormat.speedParts(
                        kmh: kmh, unit: unit, code: lang.rawValue)
                    XCTAssertEqual(
                        widget.value, app.value,
                        "скорость разошлась: \(lang.rawValue)/\(unit.rawValue) на \(kmh)")
                    XCTAssertEqual(widget.unit, app.unit,
                                   "подпись скорости: \(lang.rawValue)/\(unit.rawValue)")
                }
            }
        }
    }

    /// Незнакомый код языка падает на английский по обе стороны одинаково —
    /// то же правило, что у `AppStrings.tr`. Часы и локскрин получают код
    /// строкой, и однажды получат строку, которой мы не знаем.
    func testUnknownLanguageFallsBackToEnglishOnBothSides() {
        let widget = LiveActivityFormat.distanceParts(km: 128.4, unit: .miles, code: "zz")
        let app = Measure.distanceParts(km: 128.4, unit: .miles, lang: .en, style: .adaptive)
        XCTAssertEqual(widget.value, app.value)
        XCTAssertEqual(widget.unit, app.unit)
    }

    // MARK: - Таблица локалей — копия, и это видно

    /// `UnitNumber` держит свою таблицу локалей: `LanguageManager.Language` за
    /// границу таргета не ездит. Копия обязана совпадать с оригиналом — иначе
    /// добавленный язык печатает на локскрине английскими разрядами, и
    /// заметить это некому.
    func testLocaleTableMatchesTheApp() {
        for lang in langs {
            XCTAssertEqual(
                UnitNumber.locale(code: lang.rawValue).identifier,
                lang.locale.identifier,
                "локаль разошлась у \(lang.rawValue) — язык добавили в приложении и забыли здесь")
        }
    }

    /// Разряды и разделитель у `AppStrings` — теперь тот же `UnitNumber`.
    /// Тест держит делегирование: если кто-то вернёт в `AppStrings` свою
    /// таблицу форматтеров, локскрин начнёт печатать «1240» там, где
    /// приложение печатает «1 240».
    func testAppNumbersComeFromTheSharedTable() {
        for lang in langs {
            XCTAssertEqual(AppStrings.groupedNumber(12_890, lang),
                           UnitNumber.grouped(12_890, code: lang.rawValue))
            XCTAssertEqual(AppStrings.decimalSeparator(lang),
                           UnitNumber.decimalSeparator(code: lang.rawValue))
        }
    }

    // MARK: - Подписи за границей

    /// Слова у виджета свои (в его таргете нет `AppStrings`), и разойтись им
    /// нельзя. Здесь это проверяется в лоб — на числах, где форма слова
    /// меняется.
    func testMileWordMatchesTheAppInSlavicLanguages() {
        let cases: [(Double, Int)] = [(1, 0), (2, 0), (5, 0), (11, 0), (21, 0), (1.5, 1), (2.0, 1)]
        for lang in langs {
            for (value, digits) in cases {
                XCTAssertEqual(
                    LiveActivityStrings.distanceShort(
                        lang.rawValue, unit: .miles, value: value, fractionDigits: digits),
                    AppStrings.unitDistanceShort(
                        lang, unit: .miles, value: value, fractionDigits: digits),
                    "слово разошлось: \(lang.rawValue) на \(value)")
                XCTAssertEqual(
                    LiveActivityStrings.distanceShort(
                        lang.rawValue, unit: .km, value: value, fractionDigits: digits),
                    AppStrings.unitDistanceShort(
                        lang, unit: .km, value: value, fractionDigits: digits))
            }
            XCTAssertEqual(LiveActivityStrings.speedShort(lang.rawValue, unit: .miles),
                           AppStrings.unitSpeedShort(lang, unit: .miles))
            XCTAssertEqual(LiveActivityStrings.speedShort(lang.rawValue, unit: .km),
                           AppStrings.unitSpeedShort(lang, unit: .km))
        }
    }
}
