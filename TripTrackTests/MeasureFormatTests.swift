import XCTest
@testable import TripTrack

/// `Measure` — единственный производитель строк расстояния, скорости и высоты.
///
/// Проверяется три стиля × две единицы × тринадцать языков, и главное здесь не
/// «красиво выглядит», а два свойства, которые нельзя увидеть глазами:
///
/// 1. **Порог точности стоит на одном и том же ФИЗИЧЕСКОМ расстоянии.** До
///    0.6.7 правило «до десяти — с десятыми» было переписано в проекте четыре
///    раза, и все четыре раза — про число «10». Если перенести его в мили как
///    есть, точность начнёт меняться на 16 километрах, то есть в другом месте
///    дороги.
/// 2. **Числовая часть в милях относится к километровой ровно как 1/1.609344.**
///    Это ловит подмену конверсии на «подпись поменяли, число оставили» —
///    поломку, которая уже случалась в этом проекте с расходом топлива.
final class MeasureFormatTests: XCTestCase {

    private let langs = LanguageManager.Language.allCases
    private let styles: [Measure.Style] = [.tenths, .grouped, .adaptive]

    // MARK: - Помощники

    /// Строка числа → число. Разряды бьются неразрывным пробелом, обычным
    /// пробелом, запятой или точкой в зависимости от языка, поэтому сначала
    /// убираем разряды, а потом ставим точку разделителем.
    private func parse(_ text: String, _ lang: LanguageManager.Language) -> Double? {
        let separator = AppStrings.decimalSeparator(lang)
        var cleaned = text
        for grouping in ["\u{00A0}", " ", "\u{202F}"] {
            cleaned = cleaned.replacingOccurrences(of: grouping, with: "")
        }
        if separator != "." { cleaned = cleaned.replacingOccurrences(of: ".", with: "") }
        if separator != "," { cleaned = cleaned.replacingOccurrences(of: ",", with: "") }
        cleaned = cleaned.replacingOccurrences(of: separator, with: ".")
        return Double(cleaned)
    }

    // MARK: - Ни одна комбинация не отдаёт мусор

    func testEveryLanguageAndUnitAndStyleProducesANumberWithALabel() {
        for lang in langs {
            for unit in DistanceUnit.allCases {
                for style in styles {
                    let text = Measure.distance(metres: 128_400, unit: unit, lang: lang, style: style)
                    XCTAssertFalse(text.isEmpty, "\(lang.rawValue)/\(unit.rawValue) пусто")
                    XCTAssertFalse(text.lowercased().contains("nan"), "\(lang.rawValue): \(text)")
                    XCTAssertFalse(text.lowercased().contains("inf"), "\(lang.rawValue): \(text)")
                    XCTAssertTrue(text.contains(" "), "число и подпись слиплись: \(text)")
                    XCTAssertTrue(text.rangeOfCharacter(from: .decimalDigits) != nil,
                                  "в строке нет числа: \(text)")
                }
            }
        }
    }

    /// Сломанный семпл GPS и битая запись приезжают в форматтер как `nan`, а
    /// `Int(nan)` — это не ноль, это падение процесса. Форматтер не имеет
    /// права ронять экран.
    func testNonFiniteInputDoesNotCrash() {
        for unit in DistanceUnit.allCases {
            for style in styles {
                XCTAssertFalse(
                    Measure.distanceValue(metres: .nan, unit: unit, lang: .ru, style: style).isEmpty)
                XCTAssertFalse(
                    Measure.distanceValue(metres: .infinity, unit: unit, lang: .ru, style: style).isEmpty)
            }
            XCTAssertFalse(Measure.speedValue(ms: .nan, unit: unit, lang: .en).isEmpty)
        }
    }

    // MARK: - Стили

    func testTenthsAlwaysShowsExactlyOneDecimal() {
        for lang in langs {
            for unit in DistanceUnit.allCases {
                for metres in [0.0, 400.0, 9_900.0, 128_400.0] {
                    let text = Measure.distanceValue(
                        metres: metres, unit: unit, lang: lang, style: .tenths)
                    let separator = AppStrings.decimalSeparator(lang)
                    let parts = text.components(separatedBy: separator)
                    XCTAssertEqual(parts.count, 2,
                                   "\(lang.rawValue): «\(text)» без разделителя «\(separator)»")
                    XCTAssertEqual(parts.last?.count, 1,
                                   "\(lang.rawValue): «\(text)» — не одна десятая")
                }
            }
        }
    }

    func testGroupedShowsNoDecimalsAtAll() {
        for lang in langs {
            for unit in DistanceUnit.allCases {
                let text = Measure.distanceValue(
                    metres: 128_400, unit: unit, lang: lang, style: .grouped)
                XCTAssertFalse(text.contains(AppStrings.decimalSeparator(lang)),
                               "\(lang.rawValue): у целого стиля десятые — «\(text)»")
            }
        }
    }

    /// Порог живёт в единицах ПОКАЗА: 9 900 метров — это 9.9 км (ещё с
    /// десятыми) и 6.2 мили (уже целое). Если порог перенести в мили числом
    /// «10», мильная строка на этом же расстоянии покажет «6.2» — тест падает.
    func testAdaptiveThresholdIsTenKilometresAndSixMiles() {
        let metres = 9_900.0
        let inKm = Measure.distanceValue(metres: metres, unit: .km, lang: .ru, style: .adaptive)
        let inMiles = Measure.distanceValue(metres: metres, unit: .miles, lang: .ru, style: .adaptive)
        XCTAssertEqual(inKm, "9.9")
        XCTAssertEqual(inMiles, "6")

        // Чуть ближе — десятые у обеих; чуть дальше — целые у обеих. Расстояние
        // взято НЕ круглое нарочно: на ровных девяти километрах обе стороны
        // ответили бы «9», и тест перестал бы видеть порог, о котором он.
        XCTAssertEqual(Measure.distanceValue(metres: 9_300, unit: .km, lang: .ru, style: .adaptive), "9.3")
        XCTAssertEqual(Measure.distanceValue(metres: 9_300, unit: .miles, lang: .ru, style: .adaptive), "5.8")
        XCTAssertEqual(Measure.distanceValue(metres: 11_000, unit: .km, lang: .ru, style: .adaptive), "11")
        XCTAssertEqual(Measure.distanceValue(metres: 11_000, unit: .miles, lang: .ru, style: .adaptive), "7")
    }

    // MARK: - Локаль

    /// Разделитель дробной части — ТОЧКА во всех тринадцати языках.
    ///
    /// Решение владельца от 11 сентября 2026 («всегда числа когда идут
    /// десятичными, разделялись точкой, просто для красоты»), а не забытая
    /// локализация: по правилам локали русский, немецкий и ещё восемь пишут
    /// здесь запятую. Тест перебирает ВСЕ языки, а не три показательных, ровно
    /// потому, что вернуть запятую попытаются добросовестно — как починку
    /// локализации, языку за языком.
    func testDecimalSeparatorIsADotInEveryLanguage() {
        for lang in langs {
            XCTAssertEqual(AppStrings.decimalSeparator(lang), ".", lang.rawValue)
            for unit in DistanceUnit.allCases {
                let text = Measure.distanceValue(
                    metres: 8_400, unit: unit, lang: lang, style: .tenths)
                XCTAssertTrue(text.contains("."),
                              "\(lang.rawValue)/\(unit.rawValue): «\(text)» без точки")
                XCTAssertFalse(text.contains(","),
                               "\(lang.rawValue)/\(unit.rawValue): «\(text)» с запятой")
            }
        }
        XCTAssertEqual(
            Measure.distanceValue(metres: 8_400, unit: .km, lang: .ru, style: .tenths), "8.4")
        XCTAssertEqual(
            Measure.distanceValue(metres: 8_400, unit: .km, lang: .de, style: .tenths), "8.4")
    }

    func testGroupingComesFromTheLanguage() {
        // Русский разряд — НЕРАЗРЫВНЫЙ пробел: с обычным строка «12 000 км»
        // переносится внутри числа.
        XCTAssertEqual(
            Measure.distanceValue(metres: 12_345_000, unit: .km, lang: .ru, style: .grouped),
            "12\u{00A0}345")
        XCTAssertEqual(
            Measure.distanceValue(metres: 12_345_000, unit: .km, lang: .en, style: .grouped),
            "12,345")
    }

    // MARK: - Одна десятая, и только если она есть

    /// То же правило вне расстояния: расход, цена топлива, редкость значка,
    /// скорость реплея.
    ///
    /// Живёт оно в `UnitNumber.upToTenth`, а не тремя копиями по экранам, —
    /// копии уже разошлись: старая `GarageFormat.fuel` на 9.96 печатала
    /// «10.0» (она смотрела на целость ДО округления), а `Badge.unlockShareText`
    /// на том же числе — «10».
    func testUpToTenthPrintsTheTenthOnlyWhenThereIsOne() {
        XCTAssertEqual(UnitNumber.upToTenth(1, code: "ru"), "1")
        XCTAssertEqual(UnitNumber.upToTenth(1.5, code: "ru"), "1.5")
        XCTAssertEqual(UnitNumber.upToTenth(9.96, code: "ru"), "10")
        XCTAssertEqual(UnitNumber.upToTenth(0.44, code: "de"), "0.4")
        XCTAssertEqual(UnitNumber.upToTenth(0, code: "en"), "0")
        // Разделитель — тот же один на приложение.
        for lang in langs {
            XCTAssertEqual(UnitNumber.upToTenth(8.4, code: lang.rawValue), "8.4", lang.rawValue)
        }
    }

    // MARK: - Свойство перевода

    /// Числовая часть в милях относится к километровой ровно как 1/1.609344.
    /// Берутся расстояния от сорока километров, где округление до десятых уже
    /// не искажает отношение.
    func testMilesNumberIsKilometresOverTheMileConstant() {
        for metres in [42_195.0, 100_000.0, 250_000.0, 1_000_000.0] {
            guard
                let km = parse(Measure.distanceValue(
                    metres: metres, unit: .km, lang: .en, style: .tenths), .en),
                let miles = parse(Measure.distanceValue(
                    metres: metres, unit: .miles, lang: .en, style: .tenths), .en),
                miles > 0
            else {
                return XCTFail("не разобрали число на \(metres) м")
            }
            XCTAssertEqual(km / miles, DistanceUnit.metresPerMile / 1000, accuracy: 0.005,
                           "\(metres) м: \(km) км против \(miles) миль")
        }
    }

    // MARK: - Число и подпись

    /// Подпись приезжает вместе с числом и склоняется ПО НЕМУ. Разлучить их —
    /// значит однажды сложить «5» с «мили»: ровно так сегодня устроен постер,
    /// где число форматируется на одном экране, а подпись дописывается на
    /// другом.
    func testLabelAgreesWithTheNumberItStandsNextTo() {
        XCTAssertEqual(Measure.distance(metres: 8_400, unit: .miles, lang: .ru, style: .tenths),
                       "5.2 мили")
        XCTAssertEqual(Measure.distance(metres: 8_000, unit: .miles, lang: .ru, style: .grouped),
                       "5 миль")
        // 21 миля — та самая, на которой русский расходится с польским.
        XCTAssertEqual(
            Measure.distance(metres: 21 * DistanceUnit.metresPerMile,
                             unit: .miles, lang: .ru, style: .grouped),
            "21 миля")
        XCTAssertEqual(Measure.distance(metres: 128_400, unit: .km, lang: .ru, style: .grouped),
                       "128 км")
        XCTAssertEqual(Measure.distance(metres: 128_400, unit: .miles, lang: .en, style: .grouped),
                       "80 mi")
    }

    func testDistanceIsValuePlusLabel() {
        for lang in langs {
            for unit in DistanceUnit.allCases {
                let whole = Measure.distance(metres: 128_400, unit: unit, lang: lang, style: .adaptive)
                let value = Measure.distanceValue(metres: 128_400, unit: unit, lang: lang, style: .adaptive)
                XCTAssertTrue(whole.hasPrefix(value + " "),
                              "\(lang.rawValue): «\(whole)» не начинается с «\(value)»")
            }
        }
    }

    // MARK: - Скорость, высота, одометр

    func testSpeedTakesMetresPerSecondAndTheSameSetting() {
        XCTAssertEqual(Measure.speed(ms: 100 / 3.6, unit: .km, lang: .ru), "100 км/ч")
        XCTAssertEqual(Measure.speed(ms: 100 / 3.6, unit: .miles, lang: .en), "62 mph")
        XCTAssertEqual(Measure.speed(ms: 0, unit: .miles, lang: .ru), "0 миль/ч")
    }

    /// Высота идёт отдельной функцией, а не через одометр: сегодня она
    /// форматируется функцией про пробег, и конверсия, встроенная туда, увезла
    /// бы метры в мили ×0.621 молча.
    func testElevationGoesToFeetAndNotToMiles() {
        XCTAssertEqual(Measure.elevation(metres: 640, unit: .km, lang: .ru), "640 м")
        XCTAssertEqual(Measure.elevation(metres: 640, unit: .miles, lang: .en), "2,100 ft")
        // 640 м — это 2 100 футов, а не 398 (то есть не «мили от высоты»).
        XCTAssertEqual(
            parse(Measure.elevationValue(metres: 640, unit: .miles, lang: .en), .en) ?? 0,
            2099.7, accuracy: 1)
    }

    /// Единственный вход, где километры — это километры: `Vehicle.odometerKm`
    /// хранится в них и в 0.6.7 в метры не мигрирует, потому что против него
    /// уже записаны уровни машин в базе.
    func testOdometerTakesKilometresAndGroups() {
        XCTAssertEqual(Measure.odometer(km: 38_420, unit: .km, lang: .ru), "38\u{00A0}420 км")
        XCTAssertEqual(Measure.odometer(km: 38_420, unit: .miles, lang: .en), "23,873 mi")
    }
}
