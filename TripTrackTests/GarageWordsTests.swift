import XCTest
@testable import TripTrack

/// Слова гаража на тринадцати языках.
///
/// Все три инварианта ниже пойманы аудитом 0.6.4 уже ПОСЛЕ того, как код
/// уехал в релиз: они не ломают сборку, не роняют тесты и не видны на
/// русском телефоне разработчика. Ровно тот класс, ради которого эти тесты
/// и существуют.
final class GarageWordsTests: XCTestCase {

    private let all = LanguageManager.Language.allCases

    // MARK: - Силуэт: 122 модели из 521 подписывались «Седаном»

    /// `avatarStyleName` знала семь автомобильных силуэтов из десяти, а в
    /// `default` возвращала «Седан». Мотоциклы (64 модели справочника),
    /// велосипеды (41) и скутеры (17) становились седанами на всех языках.
    func testEverySilhouetteHasItsOwnName() {
        for style in VehicleAvatar.styles {
            for lang in all {
                let name = AppStrings.avatarStyleName(lang, style: style)
                XCTAssertFalse(name.isEmpty,
                               "\(style)/\(lang): пустая подпись — отсюда берётся метка VoiceOver")
                XCTAssertNotEqual(name, style,
                                  "\(style)/\(lang): вернулся сырой ключ — значит case не заведён")
            }
        }
    }

    /// Два колеса не должны называться легковыми словами ни на одном языке.
    func testTwoWheelersAreNotCars() {
        let car = Set(all.map { AppStrings.avatarStyleName($0, style: "car") })
        for style in ["motorcycle", "scooter", "bicycle"] {
            for lang in all {
                let name = AppStrings.avatarStyleName(lang, style: style)
                XCTAssertFalse(car.contains(name),
                               "\(style)/\(lang): «\(name)» — это название легковой")
            }
        }
    }

    /// Неизвестный силуэт обязан быть ЗАМЕТНО неправильным, а не тихо седаном:
    /// прежнее поведение прожило до аудита именно потому, что не бросалось в глаза.
    func testAnUnknownSilhouetteFailsLoudly() {
        let name = AppStrings.avatarStyleName(.ru, style: "hovercraft")
        XCTAssertEqual(name, "hovercraft")
        XCTAssertNotEqual(name, AppStrings.avatarStyleName(.ru, style: "car"))
    }

    // MARK: - Одометр: единственный формат, живший без языка

    /// `GarageFormat.odometer` жёстко ставила русский разделитель разрядов и
    /// уезжала с ним на немецкие и английские телефоны.
    func testOdometerGroupsByLanguage() {
        XCTAssertEqual(GarageFormat.odometer(143_500, lng: .en), "143,500")
        let ru = GarageFormat.odometer(143_500, lng: .ru)
        XCTAssertTrue(ru.hasPrefix("143") && ru.hasSuffix("500"))
        XCTAssertNotEqual(ru, GarageFormat.odometer(143_500, lng: .en),
                          "русский и английский не могут группировать одинаково")
    }

    /// Разделитель разрядов обязан быть НЕРАЗРЫВНЫМ. С обычным пробелом строка
    /// «Volkswagen Polo · 2019 · 12 000 км» переносится ВНУТРИ числа: «12»
    /// остаётся, «000 км» уезжает на следующую строку.
    func testThousandsSeparatorNeverBreaksTheLine() {
        for lang in all {
            let s = GarageFormat.odometer(143_500, lng: lang)
            XCTAssertFalse(s.contains(" "),
                           "\(lang): обычный пробел в числе «\(s)» — оно разорвётся при переносе")
        }
    }

    func testOdometerRoundsRatherThanTruncates() {
        XCTAssertEqual(GarageFormat.odometer(12_345.6, lng: .en), "12,346")
    }

    // MARK: - Годы: механизма для чисел словами в проекте нет

    /// В русском «лет» — форма от другого корня, и никакое правило вида
    /// «основа + окончание» её не даст.
    func testYearsRussianUsesTheSuppletiveForm() {
        XCTAssertEqual(AppStrings.nounYears(.ru, 1), "год")
        XCTAssertEqual(AppStrings.nounYears(.ru, 2), "года")
        XCTAssertEqual(AppStrings.nounYears(.ru, 5), "лет")
        XCTAssertEqual(AppStrings.nounYears(.ru, 11), "лет")
        XCTAssertEqual(AppStrings.nounYears(.ru, 21), "год")
    }

    /// Польский расходится со славянской тройкой на 21 — там снова «lat».
    func testYearsPolishPartsWaysWithRussianAt21() {
        XCTAssertEqual(AppStrings.nounYears(.pl, 1), "rok")
        XCTAssertEqual(AppStrings.nounYears(.pl, 2), "lata")
        XCTAssertEqual(AppStrings.nounYears(.pl, 5), "lat")
        XCTAssertEqual(AppStrings.nounYears(.pl, 21), "lat")
    }

    func testYearsUkrainianHasItsOwnThreeForms() {
        XCTAssertEqual(AppStrings.nounYears(.uk, 1), "рік")
        XCTAssertEqual(AppStrings.nounYears(.uk, 2), "роки")
        XCTAssertEqual(AppStrings.nounYears(.uk, 5), "років")
    }

    func testYearsExistInEveryLanguage() {
        for lang in all {
            for n in [0, 1, 2, 5, 11, 21, 100] {
                XCTAssertFalse(AppStrings.nounYears(lang, n).isEmpty,
                               "\(lang)/\(n): пустое существительное")
            }
        }
    }

    /// Языки без числа форм не должны их изобретать.
    func testYearsAreInvariantWhereTheLanguageHasNoPlural() {
        for lang in [LanguageManager.Language.id, .tr, .kk, .fil] {
            let forms = Set([1, 2, 5, 21].map { AppStrings.nounYears(lang, $0) })
            XCTAssertEqual(forms.count, 1, "\(lang): форм быть не должно, а их \(forms)")
        }
    }
}
