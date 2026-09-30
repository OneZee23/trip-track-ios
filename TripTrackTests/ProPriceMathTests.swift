import XCTest
@testable import TripTrack

/// Подписи выгоды считаются из `Decimal` цен витрины, а не берутся из макета.
///
/// «−44 %» верно ровно для пары 19,99 / 2,99. В иене, форинте и рупии Apple
/// округляет иначе, и захардкоженный чип соврал бы; посчитать нечем — подписи
/// нет вовсе. Это единственное место, где мы считаем деньги сами, и цена
/// ошибки здесь — отказ ревью 3.1.2 или неверное обещание человеку.
final class ProPriceMathTests: XCTestCase {

    /// Форматтер без локали нарочно: `String(format:)` печатает точку всегда,
    /// а `.formatted()` взял бы разделитель симулятора и сделал тест шатким.
    private func euro(_ v: Decimal) -> String {
        String(format: "%.2f €", NSDecimalNumber(decimal: v).doubleValue)
    }

    func testDesignPairGivesTheDesignNumbers() {
        XCTAssertEqual(ProPriceMath.savingPercent(yearly: 19.99, monthly: 2.99), 44)
        XCTAssertEqual(ProPriceMath.perMonth(yearly: 19.99, format: euro), "1.67 €")
    }

    /// Валюта без дробной части и с другим отношением цен: число ДРУГОЕ, и оно
    /// обязано быть посчитанным, а не нарисованным.
    func testOtherCurrenciesGetTheirOwnNumber() {
        XCTAssertEqual(ProPriceMath.savingPercent(yearly: 2900, monthly: 400), 39)
    }

    /// Округление ВНИЗ, и это не мелочь: 39.58 % нельзя объявлять сороковыми.
    /// Обещание выгоды не имеет права быть больше настоящей.
    func testSavingIsRoundedDownSoItNeverOverstates() {
        // 1900 / 4800 = 39.58 %
        XCTAssertEqual(ProPriceMath.savingPercent(yearly: 2900, monthly: 400), 39)
        // 1 / 12 = 8.33 %
        XCTAssertEqual(ProPriceMath.savingPercent(yearly: 11, monthly: 1), 8)
    }

    /// Год дороже двенадцати месяцев или ровно равен им — выгоды нет, и чипа
    /// тоже. Ноль процентов на витрине читался бы как сбой, а не как «нет».
    func testNoChipWhenThereIsNoSaving() {
        XCTAssertNil(ProPriceMath.savingPercent(yearly: 40, monthly: 2.99))
        XCTAssertNil(ProPriceMath.savingPercent(yearly: 3000, monthly: 250),
                     "год ровно равен двенадцати месяцам — выгоды нет")
    }

    /// Цены не приехали — обе подписи молчат, а не печатают ноль.
    func testNothingIsPrintedWithoutPrices() {
        XCTAssertNil(ProPriceMath.savingPercent(yearly: nil, monthly: 2.99))
        XCTAssertNil(ProPriceMath.savingPercent(yearly: 19.99, monthly: nil))
        XCTAssertNil(ProPriceMath.perMonth(yearly: nil, format: euro))
        XCTAssertNil(ProPriceMath.perMonth(yearly: 19.99, format: nil))
    }

    /// Нулевая и отрицательная цена — не «бесплатно», а мусор на входе:
    /// делить на такое нельзя, и обещать нечего.
    func testGarbageInputsAreRefused() {
        XCTAssertNil(ProPriceMath.perMonth(yearly: 0, format: euro))
        XCTAssertNil(ProPriceMath.savingPercent(yearly: 0, monthly: 2.99))
        XCTAssertNil(ProPriceMath.savingPercent(yearly: 19.99, monthly: 0))
        XCTAssertNil(ProPriceMath.savingPercent(yearly: -1, monthly: 2.99))
    }

    /// Неделя обещается только годовому и только тому, кому Apple её даст.
    func testTrialCopyOnlyOnYearlyAndOnlyWhenEligible() {
        let yearly = PlusProductInfo(id: PlusStore.yearlyID, displayPrice: "19,99 €",
                                     period: .yearly, trialDays: 7)
        let monthly = PlusProductInfo(id: PlusStore.monthlyID, displayPrice: "2,99 €",
                                      period: .monthly, trialDays: 7)

        let eligible = PlusPaywallModel.plans([yearly, monthly],
                                              eligibleForIntro: true, lang: .ru)
        XCTAssertNotNil(eligible[0].caption, "годовому неделя положена")
        XCTAssertNil(eligible[1].caption, "у месячного недели нет НИКОГДА")

        let notEligible = PlusPaywallModel.plans([yearly, monthly],
                                                 eligibleForIntro: false, lang: .ru)
        XCTAssertNil(notEligible[0].caption, "вернувшемуся подписчику недели не обещаем")
        XCTAssertNil(notEligible[1].caption)
    }
}
