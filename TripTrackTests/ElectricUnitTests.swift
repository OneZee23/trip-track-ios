import XCTest
@testable import TripTrack

/// Единица электричества: перевод туда и обратно, ноль и границы.
///
/// Тот же набор проверок, что у `ConsumptionUnit`, и по той же причине: число,
/// переведённое не в ту сторону, не роняет ничего — оно просто врёт, и увидеть
/// это можно только глазами на экране либо здесь.
final class ElectricUnitTests: XCTestCase {

    // MARK: - Диалект выводится из приборки

    func testDialectFollowsTheDashboard() {
        XCTAssertEqual(ElectricUnit.forDashboard(.km), .per100kWh)
        XCTAssertEqual(ElectricUnit.forDashboard(.miles), .miPerKWh)
    }

    // MARK: - Перевод

    /// Опорное число: 16 кВт·ч на сотню километров — обычный электромобиль.
    /// Сто километров это 62.137119 мили, значит на киловатт-час приходится
    /// 62.137119 / 16 = 3.8836 мили.
    func testKWhPer100BecomesMilesPerKWh() {
        let shown = ElectricUnit.miPerKWh.display(fromPer100: 16)
        XCTAssertEqual(shown, 62.137119 / 16, accuracy: 0.0001)
    }

    func testMetricDialectShowsTheStoredNumberUntouched() {
        XCTAssertEqual(ElectricUnit.per100kWh.display(fromPer100: 16), 16)
        XCTAssertEqual(ElectricUnit.per100kWh.toPer100(16), 16)
    }

    /// Обратимость — то, ради чего у типа две функции, а не одна: человек
    /// открывает форму, ничего не трогает и закрывает, а число обязано
    /// остаться тем же.
    func testRoundTripKeepsTheStoredValue() {
        for stored in [1.0, 12.5, 16.0, 23.7, 60.0] {
            let shown = ElectricUnit.miPerKWh.display(fromPer100: stored)
            let back = ElectricUnit.miPerKWh.toPer100(shown)
            XCTAssertEqual(back, stored, accuracy: 0.000001,
                           "\(stored) кВт·ч/100 км не вернулись из \(shown) mi/kWh")
        }
    }

    /// Ноль — это «не задано», и у «не задано» нет миль на киловатт-час.
    /// Деление вместо этой проверки печатает «inf» (правило
    /// `ConsumptionUnit.display`).
    func testZeroStaysZeroInBothDirections() {
        XCTAssertEqual(ElectricUnit.miPerKWh.display(fromPer100: 0), 0)
        XCTAssertEqual(ElectricUnit.miPerKWh.toPer100(0), 0)
        XCTAssertEqual(ElectricUnit.per100kWh.display(fromPer100: 0), 0)
        XCTAssertEqual(ElectricUnit.per100kWh.toPer100(0), 0)
    }

    func testNegativeInputDoesNotProduceGarbage() {
        XCTAssertEqual(ElectricUnit.miPerKWh.display(fromPer100: -5), 0)
        XCTAssertEqual(ElectricUnit.miPerKWh.toPer100(-5), 0)
    }

    // MARK: - Единственный держатель мили

    /// Своей константы 1609.344 у типа нет — перевод идёт через `DistanceUnit`.
    /// Проверяется следствием: показанное число обязано совпасть с тем, что
    /// даёт сам `DistanceUnit` на том же расстоянии.
    func testMilesArithmeticComesFromDistanceUnit() {
        let metresPerKWh = 100_000.0 / 16
        XCTAssertEqual(ElectricUnit.miPerKWh.display(fromPer100: 16),
                       DistanceUnit.miles.distance(fromMetres: metresPerKWh),
                       accuracy: 0.000001)
    }

    // MARK: - Потолок поля ввода

    /// Потолок в единицах ПОКАЗА: 60 кВт·ч/100 км — электрический грузовик,
    /// 60 mi/kWh — число, которого не бывает. Общий потолок отверг бы у
    /// мильного человека нормальный расход или пропустил бы у метрического
    /// опечатку.
    func testInputCeilingIsStatedInTheShownUnit() {
        XCTAssertEqual(ElectricUnit.per100kWh.inputCeiling, 60)
        XCTAssertEqual(ElectricUnit.miPerKWh.inputCeiling, 12)
        // И потолок обязан пропускать реальную машину: 16 кВт·ч/100 км это
        // 3.88 mi/kWh, обе стороны внутри своих границ.
        XCTAssertLessThan(ElectricUnit.miPerKWh.display(fromPer100: 16),
                          ElectricUnit.miPerKWh.inputCeiling)
        XCTAssertLessThan(16, ElectricUnit.per100kWh.inputCeiling)
    }

    // MARK: - Подписи

    func testLabelsAreNotEmptyAndDifferBetweenDialects() {
        for lang in LanguageManager.Language.allCases {
            let metric = ElectricUnit.per100kWh.valueUnit(lang)
            let imperial = ElectricUnit.miPerKWh.valueUnit(lang)
            XCTAssertFalse(metric.isEmpty, "пустая подпись кВт·ч у \(lang)")
            XCTAssertEqual(imperial, "mi/kWh", "у \(lang) символ подменили словом")
            XCTAssertNotEqual(metric, imperial, "две единицы подписаны одинаково у \(lang)")
        }
    }

    /// Подпись метрического диалекта собирается, а не лежит строкой: в ней
    /// склоняемая сотня километров и киловатт-час, который пишется не
    /// латиницей у казахского и украинского.
    func testMetricLabelCarriesBothHalves() {
        XCTAssertTrue(ElectricUnit.per100kWh.valueUnit(.ru).contains("кВт·ч"))
        XCTAssertTrue(ElectricUnit.per100kWh.valueUnit(.ru).contains("100"))
        XCTAssertTrue(ElectricUnit.per100kWh.valueUnit(.kk).contains("кВт·сағ"))
        XCTAssertTrue(ElectricUnit.per100kWh.valueUnit(.uk).contains("кВт·год"))
    }
}
