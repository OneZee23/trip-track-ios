import XCTest
@testable import TripTrack

/// Слова электро-версии на тринадцати языках.
///
/// Тот же набор проверок, что у `VehicleDashboardPickerTests`, и по той же
/// причине: выбор из трёх вариантов, у которого два названия совпали, — это
/// экран, на котором нельзя выбрать. Компилятор про это не скажет ничего, а
/// открытая форма скажет только на одном языке из тринадцати.
final class PowertrainCopyTests: XCTestCase {

    private let languages = LanguageManager.Language.allCases

    // MARK: - Три варианта различимы

    func testEveryLanguageNamesAllThreeChoicesDifferently() {
        for lang in languages {
            let names = Powertrain.allCases.map { $0.label(lang) }
            XCTAssertEqual(Set(names).count, names.count,
                           "\(lang): названия типов двигателя совпали — \(names)")
            for name in names {
                XCTAssertFalse(name.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(lang): пустое название типа двигателя")
            }
        }
    }

    /// «Auto» по-немецки и по-испански значит «машина». Режим поездки, который
    /// в списке рядом с «Электро» и «Топливо» читается как «автомобиль», —
    /// это не перевод, а другой смысл.
    func testAutoModeIsNotTheWordForCar() {
        XCTAssertEqual(AppStrings.energyModeAuto(.de), "Automatisch")
        XCTAssertEqual(AppStrings.energyModeAuto(.es), "Automático")
        XCTAssertEqual(AppStrings.energyModeAuto(.pt), "Automático")
        XCTAssertEqual(AppStrings.energyModeAuto(.fr), "Automatique")
        XCTAssertEqual(AppStrings.energyModeAuto(.it), "Automatico")
    }

    /// Три режима поездки — СВОИ короткие слова, и они тоже обязаны
    /// различаться. С типом двигателя их больше не делят: там теперь вопрос
    /// «на чём ездит машина» и ответы вроде «Бензин или дизель», которым в
    /// сегменте шириной в треть строки места нет.
    func testEveryLanguageNamesAllThreeModesDifferently() {
        for lang in languages {
            let names = [AppStrings.energyModeAuto(lang),
                         AppStrings.energyModeElectric(lang),
                         AppStrings.energyModeFuel(lang)]
            XCTAssertEqual(Set(names).count, names.count,
                           "\(lang): названия режимов поездки совпали — \(names)")
            for name in names {
                XCTAssertFalse(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// Слово режима КОРОТКОЕ: три сегмента делят одну строку, и длинный ответ
    /// из листа двигателя туда не помещается.
    func testModeWordsStayShort() {
        for lang in languages {
            for name in [AppStrings.energyModeElectric(lang), AppStrings.energyModeFuel(lang)] {
                XCTAssertLessThanOrEqual(name.count, 14,
                                         "\(lang): «\(name)» не влезет в сегмент")
            }
        }
    }

    // MARK: - Пояснения под вариантами

    /// У КАЖДОГО варианта своё пояснение, и они разные: одинаковая подпись у
    /// двух строк — это выбор, который нечем сделать.
    func testEveryPowertrainHasItsOwnHint() {
        for lang in languages {
            let hints = Powertrain.allCases.map { $0.hint(lang) }
            XCTAssertEqual(Set(hints).count, hints.count,
                           "\(lang): пояснения типов двигателя совпали")
            for hint in hints {
                XCTAssertFalse(hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(lang): пустое пояснение")
            }
        }
    }

    /// Заголовок листа — вопрос, и он переведён везде.
    func testThePickerAsksAQuestionInEveryLanguage() {
        let english = AppStrings.powertrainPickerTitle(.en)
        for lang in languages where lang != .en {
            XCTAssertNotEqual(AppStrings.powertrainPickerTitle(lang), english,
                              "\(lang): заголовок листа остался английским")
        }
    }

    // MARK: - Подвал и подписи

    func testTheFootnoteIsWrittenInEveryLanguage() {
        let english = AppStrings.powertrainPickerFootnote(.en)
        for lang in languages where lang != .en {
            let text = AppStrings.powertrainPickerFootnote(lang)
            XCTAssertFalse(text.isEmpty, "\(lang): пустой подвал листа")
            XCTAssertNotEqual(text, english, "\(lang): подвал остался английским")
        }
    }

    func testEveryNewStringHasARowInEveryTable() {
        let english: [(String, (LanguageManager.Language) -> String)] = [
            ("vehiclePowertrainTitle", AppStrings.vehiclePowertrainTitle),
            ("vehiclePowertrainSubtitle", AppStrings.vehiclePowertrainSubtitle),
            ("electricSectionLabel", AppStrings.electricSectionLabel),
            ("electricPriceSection", AppStrings.electricPriceSection),
            ("electricRangeLabel", AppStrings.electricRangeLabel),
            ("electricRangeHint", AppStrings.electricRangeHint),
            ("statElectricity", AppStrings.statElectricity),
            ("statCostFuel", AppStrings.statCostFuel),
            ("statCostElectricity", AppStrings.statCostElectricity),
            ("tripEnergyModeTitle", AppStrings.tripEnergyModeTitle),
            ("powertrainPickerTitle", AppStrings.powertrainPickerTitle),
            ("powertrainFuelHint", AppStrings.powertrainFuelHint),
            ("powertrainElectricHint", AppStrings.powertrainElectricHint),
            ("powertrainHybridHint", AppStrings.powertrainHybridHint),
        ]
        // `unitKWhShort` в этот список НЕ входит: «kWh» — символ СИ, и на
        // половине языков он совпадает с английским по праву. Его держит
        // отдельный `testKilowattHourIsNotLatinEverywhere` — там названы ровно
        // те три языка, где он обязан отличаться.
        //
        // Ключ без строки в таблице откатывается на АНГЛИЙСКИЙ — то есть
        // выглядит рабочим и молчит. Ловится только сравнением.
        for (name, fn) in english {
            let en = fn(.en)
            for lang in [LanguageManager.Language.ru, .de, .es, .fr, .it, .pl, .tr, .uk, .kk] {
                XCTAssertNotEqual(fn(lang), en,
                                  "\(name): у \(lang) строка осталась английской")
            }
        }
    }

    /// «кВт·ч» пишется латиницей не везде: у казахского «сағ» вместо «ч», у
    /// украинского «год». Это и есть причина, по которой строка переводится, а
    /// не лежит символом в коде.
    func testKilowattHourIsNotLatinEverywhere() {
        XCTAssertEqual(AppStrings.unitKWhShort(.ru), "кВт·ч")
        XCTAssertEqual(AppStrings.unitKWhShort(.uk), "кВт·год")
        XCTAssertEqual(AppStrings.unitKWhShort(.kk), "кВт·сағ")
        XCTAssertEqual(AppStrings.unitKWhShort(.en), "kWh")
    }

    // MARK: - Подстановка

    /// Расстояние приходит УЖЕ напечатанным и подставляется токеном: строка с
    /// интерполяцией внутри `tr()` молча теряет значение на одиннадцати языках
    /// (CLAUDE.md, «Localization»).
    func testOnBatteryLineSubstitutesTheDistance() {
        for lang in languages {
            let text = AppStrings.tripOnBattery(lang, distance: "50 км")
            XCTAssertTrue(text.contains("50 км"),
                          "\(lang): расстояние не подставилось — «\(text)»")
            XCTAssertFalse(text.contains("{distance}"),
                           "\(lang): токен остался в строке — «\(text)»")
        }
    }

    // MARK: - Жетоны листа

    /// У жетона в листе — SF Symbol, и у трёх вариантов он разный: одинаковый
    /// значок у «Электро» и «Плагин-гибрида» превратил бы список в две
    /// одинаковые строки с разными подписями.
    func testEveryPowertrainHasItsOwnSymbol() {
        let symbols = Powertrain.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count, "значки типов двигателя совпали")
        for symbol in symbols {
            XCTAssertFalse(symbol.isEmpty)
        }
    }
}
