import XCTest
@testable import TripTrack

/// Арифметика `ConsumptionUnit` — переключателя «литры на сотню ↔ мили на
/// галлон».
///
/// Тесты существуют, потому что этот экран уже шипал свою поломку: прошлая
/// версия подписала хранимые километровые числа словом «mpg», ничего не
/// переведя, — а шкала у mpg идёт в ДРУГУЮ сторону, и экономичная машина
/// стала выглядеть грузовиком. Всё, что вернёт «переподписать вместо
/// перевести», обязано падать здесь.
///
/// Про то, откуда диалект берётся у конкретной машины, и про оба сценария
/// владельца — соседний `VehicleConsumptionUnitTests`. Здесь только сам тип.
final class ConsumptionUnitTests: XCTestCase {

    // MARK: - Две стороны

    /// Опорная цифра: 9.4 л/100 км ≈ 25 mpg (US).
    func testConvertsToMpg() {
        XCTAssertEqual(ConsumptionUnit.mpg.display(fromPer100: 9.4), 25.02, accuracy: 0.05)
        XCTAssertEqual(ConsumptionUnit.mpg.display(fromPer100: 5.6), 42.0, accuracy: 0.05)
    }

    func testConvertsBackFromMpg() {
        XCTAssertEqual(ConsumptionUnit.mpg.toPer100(25), 9.41, accuracy: 0.01)
        XCTAssertEqual(ConsumptionUnit.mpg.toPer100(42), 5.6, accuracy: 0.01)
    }

    /// `per100` — единица ХРАНЕНИЯ, поэтому проходит насквозь в обе стороны.
    /// Падает, если кто-нибудь «на всякий случай» переведёт и её: с 0.6.7
    /// сотня в ней всегда километровая, и переводить нечего.
    func testPer100IsIdentity() {
        for value in [0.0, 4.2, 9.1, 22.0] {
            XCTAssertEqual(ConsumptionUnit.per100.display(fromPer100: value), value)
            XCTAssertEqual(ConsumptionUnit.per100.toPer100(value), value)
        }
    }

    /// Набрал, переключил, переключил обратно — та же машина. Ровно это делает
    /// форма на каждой смене приборки.
    func testRoundTripSurvivesTheSwitch() {
        for unit in ConsumptionUnit.allCases {
            for stored in [4.2, 6.0, 7.8, 9.1, 14.5, 22.0] {
                XCTAssertEqual(unit.toPer100(unit.display(fromPer100: stored)), stored,
                               accuracy: 0.0001,
                               "\(stored) л/100 км не пережили круг через \(unit.rawValue)")
            }
        }
    }

    // MARK: - Сама инверсия

    /// Причина, по которой тип вообще существует: больше литров — хуже, больше
    /// миль на галлон — лучше. Переподписывание сохранило бы порядок и соврало.
    func testTheScaleIsInverted() {
        XCTAssertLessThan(ConsumptionUnit.mpg.display(fromPer100: 15),
                          ConsumptionUnit.mpg.display(fromPer100: 5),
                          "прожорливая машина обязана показывать МЕНЬШЕ mpg")
    }

    // MARK: - Вырожденный вход

    /// Машина, у которой расход ещё не заполнен. Деление на него дало бы
    /// бесконечность, а она печатается в поле как «inf».
    func testZeroStaysZero() {
        for unit in ConsumptionUnit.allCases {
            XCTAssertEqual(unit.display(fromPer100: 0), 0)
            XCTAssertEqual(unit.toPer100(0), 0)
            XCTAssertFalse(unit.display(fromPer100: 0).isInfinite)
        }
    }

    /// Потолок поля ввода — В ЕДИНИЦАХ ПОКАЗА: 50 л/100 км — абсурдная машина,
    /// 50 mpg — обычная, и общее число отвергло бы у мильного человека вполне
    /// нормальный расход.
    func testInputCeilingSpeaksTheUnitOnScreen() {
        XCTAssertEqual(ConsumptionUnit.per100.inputCeiling, 50)
        XCTAssertEqual(ConsumptionUnit.mpg.inputCeiling, 250)
    }

    // MARK: - Подписи

    /// `per100` — это сотня КИЛОМЕТРОВ на всех тринадцати языках, и никогда
    /// сотня миль. Проверяется во всех, потому что подпись — последнее, что
    /// видит человек: число, подписанное чужой сотней, от правильного уже не
    /// отличить.
    func testPer100AlwaysSaysHundredKilometres() {
        for lang in LanguageManager.Language.allCases {
            let label = ConsumptionUnit.per100.valueUnit(lang)
            let km = AppStrings.unitDistanceShort(lang, unit: .km, value: 100, fractionDigits: 0)
            let mile = AppStrings.unitDistanceShort(lang, unit: .miles, value: 100, fractionDigits: 0)

            XCTAssertTrue(label.hasSuffix("100" + km),
                          "\(lang.rawValue): «\(label)» не заканчивается сотней километров")
            XCTAssertFalse(label.contains(mile),
                           "\(lang.rawValue): в подписи расхода появилась миля — «\(label)»")
        }
        XCTAssertEqual(ConsumptionUnit.per100.valueUnit(.ru), "л/100км")
        XCTAssertEqual(ConsumptionUnit.per100.valueUnit(.en), "L/100km")
    }

    /// mpg — символ, а не существительное: он одинаков во всех языках и не
    /// склоняется.
    func testMpgIsTheSameWordEverywhere() {
        for lang in LanguageManager.Language.allCases {
            XCTAssertEqual(ConsumptionUnit.mpg.valueUnit(lang), "mpg")
        }
    }

    // MARK: - Цена топлива

    /// Мильная панель — это галлоны. «Мили на галлон» рядом с «рублями за
    /// литр» не набор единиц, которым кто-то пользуется.
    func testMpgImpliesGallons() {
        XCTAssertEqual(ConsumptionUnit.mpg.volumeUnit, .gallons)
        XCTAssertEqual(ConsumptionUnit.per100.volumeUnit, .liters)
    }

    /// Цена ХРАНИТСЯ за литр — на неё умножаются литры поездки. Настройка
    /// галлонов когда-то меняла только подпись, и «65 ₽/л» становились
    /// «65 ₽/gal» одним нажатием, а каждая поездка молча оставалась
    /// посчитанной по литровой цене.
    func testPriceConvertsToGallons() {
        XCTAssertEqual(ConsumptionUnit.mpg.displayPrice(fromPerLitre: 65), 246.05, accuracy: 0.01)
        XCTAssertEqual(ConsumptionUnit.per100.displayPrice(fromPerLitre: 65), 65)
    }

    func testPriceRoundTrips() {
        for perLitre in [42.0, 56.0, 65.0, 98.5] {
            let shown = ConsumptionUnit.mpg.displayPrice(fromPerLitre: perLitre)
            XCTAssertEqual(ConsumptionUnit.mpg.priceToPerLitre(shown), perLitre, accuracy: 0.0001)
        }
    }

    /// Цена и расход идут через одно переключение в РАЗНЫЕ стороны: галлон
    /// дороже литра, а машина проезжает на галлоне больше, чем сотня
    /// километров стоит ей литров. Падает, если кто-то переиспользует одну
    /// конверсию на обе.
    func testPriceAndConsumptionAreNotTheSameConversion() {
        XCTAssertGreaterThan(ConsumptionUnit.mpg.displayPrice(fromPerLitre: 65), 65)
        XCTAssertGreaterThan(ConsumptionUnit.mpg.display(fromPer100: 9.4), 9.4)
        XCTAssertNotEqual(ConsumptionUnit.mpg.displayPrice(fromPerLitre: 9.4),
                          ConsumptionUnit.mpg.display(fromPer100: 9.4), accuracy: 0.001)
    }

    /// Галлон АМЕРИКАНСКИЙ по обе стороны экрана.
    ///
    /// Британский микс (мили + литры + imperial mpg) — осознанный пропуск
    /// 0.6.7: имперский галлон это 4.546 л, и стой его константа в расходе,
    /// одно и то же слово значило бы в расходе одно, а в поле цены рядом —
    /// другое. Разошлись бы они молча, числами.
    func testTheGallonIsAmericanOnBothSidesOfTheScreen() {
        XCTAssertEqual(ConsumptionUnit.litresPerGallon, 3.785411784)
        // 235.214583 = 100 × 3.785411784 ÷ 1.609344. Имперская константа —
        // 282.48.
        XCTAssertEqual(ConsumptionUnit.mpgConstant, 235.214583, accuracy: 1e-6)
    }
}
