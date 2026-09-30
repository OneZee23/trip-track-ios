import XCTest
import StoreKit
@testable import TripTrack

/// Строки пейвола собираются из ответа Apple, а не пишутся руками.
///
/// Проверять это можно только здесь: `Product` не собирается в тесте вовсе —
/// у него нет инициализатора, — поэтому между StoreKit и экраном стоит
/// `PlusProductInfo`, и таблица тарифов считается чистой функцией.
final class PlusPaywallModelTests: XCTestCase {

    private let yearly = PlusProductInfo(
        id: PlusStore.yearlyID, displayPrice: "29,99 €", period: .yearly, trialDays: 7)
    private let monthly = PlusProductInfo(
        id: PlusStore.monthlyID, displayPrice: "6,99 €", period: .monthly, trialDays: nil)

    // MARK: - Порядок и умолчание

    /// Годовой первым и выбранным — даже если Apple вернула продукты в другом
    /// порядке. Порядок ответа StoreKit нигде не обещан.
    func testYearlyLeadsAndIsTheDefault() {
        let plans = PlusPaywallModel.plans([monthly, yearly], eligibleForIntro: true, lang: .ru)
        XCTAssertEqual(plans.map(\.id), [PlusStore.yearlyID, PlusStore.monthlyID])
        XCTAssertTrue(plans[0].isDefault)
        XCTAssertFalse(plans[1].isDefault)
        XCTAssertEqual(PlusPaywallModel.defaultSelection(plans), PlusStore.yearlyID)
    }

    /// Годового не привезли — выбран первый из привезённых, а не «ничего»:
    /// пейвол с невыбранным тарифом это кнопка, которая не нажимается.
    func testWithoutTheYearlyTheFirstPlanIsSelected() {
        let plans = PlusPaywallModel.plans([monthly], eligibleForIntro: true, lang: .en)
        XCTAssertEqual(PlusPaywallModel.defaultSelection(plans), PlusStore.monthlyID)
    }

    func testNoProductsMeansNoSelection() {
        XCTAssertNil(PlusPaywallModel.defaultSelection(
            PlusPaywallModel.plans([], eligibleForIntro: true, lang: .de)))
    }

    // MARK: - Цена

    /// Цена попадает на экран ровно такой, какой её напечатала витрина: своего
    /// форматтера у пейвола нет и быть не должно.
    func testPriceComesStraightFromDisplayPrice() {
        let plans = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: .ru)
        XCTAssertTrue(plans[0].price.contains("29,99 €"), plans[0].price)
        XCTAssertTrue(plans[1].price.contains("6,99 €"), plans[1].price)
    }

    /// Ни в одной из тринадцати строка тарифа не несёт своей валюты — только
    /// подставленную. Знак «€» в переводе значил бы, что человек в Грузии
    /// читает цену, которой не увидит на списании.
    func testNoLanguageWritesACurrencyOfItsOwn() {
        for lang in LanguageManager.Language.allCases {
            let plans = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: lang)
            for plan in plans {
                let stripped = plan.price.replacingOccurrences(of: "29,99 €", with: "")
                    .replacingOccurrences(of: "6,99 €", with: "")
                for sign in ["€", "$", "£", "₽", "₾"] {
                    XCTAssertFalse(stripped.contains(sign),
                                   "\(lang.rawValue): в строке тарифа своя валюта — \(plan.price)")
                }
            }
        }
    }

    // MARK: - Триал

    /// «7 дней бесплатно, потом 29,99 € в год» — и длина, и цена приходят из
    /// предложения, а не из литерала.
    func testTrialCaptionCarriesBothTheLengthAndThePrice() {
        let plans = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: .ru)
        XCTAssertEqual(plans[0].caption, "7 дней бесплатно, потом 29,99 € в год")
        XCTAssertNil(plans[1].caption, "у месячного триала нет — подписи тоже")
    }

    func testTrialCaptionIsTranslatedEverywhere() {
        for lang in LanguageManager.Language.allCases {
            let plans = PlusPaywallModel.plans([yearly], eligibleForIntro: true, lang: lang)
            let caption = plans[0].caption ?? ""
            XCTAssertFalse(caption.isEmpty, lang.rawValue)
            XCTAssertFalse(caption.contains("{"), "\(lang.rawValue): токен не подставлен — \(caption)")
            XCTAssertTrue(caption.contains("7"), "\(lang.rawValue): длина триала потерялась — \(caption)")
            XCTAssertTrue(caption.contains("29,99 €"), "\(lang.rawValue): цена потерялась — \(caption)")
        }
    }

    /// Длина предложения считается из периода Apple, а не угадывается. Неделя —
    /// семь дней, и именно так заведён `Config/TripTrack.storekit`.
    func testOfferLengthInDays() {
        XCTAssertEqual(PlusPaywallModel.days(unit: .week, value: 1), 7)
        XCTAssertEqual(PlusPaywallModel.days(unit: .day, value: 3), 3)
        XCTAssertEqual(PlusPaywallModel.days(unit: .month, value: 1), 30)
        XCTAssertEqual(PlusPaywallModel.days(unit: .year, value: 1), 365)
    }

    // MARK: - Заголовки

    func testTitlesAreTheLanguagesOwnWords() {
        let ru = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: .ru)
        XCTAssertEqual(ru.map(\.title), ["Год", "Месяц"])
        let de = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: .de)
        XCTAssertEqual(de.map(\.title), ["Jahr", "Monat"])
    }

    // MARK: - Подпись строки «Плюс» в профиле

    private static let october: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 12; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    // Четыре теста подписи строки «Плюс» жили здесь до 0.8.4 и заменены
    // `ProStatusTests`: статусов стало восемь, два из них про витрину, и
    // отвечает на них `ProStatus`, а не `PlusRow`.
    //
    // Один из них описывал то, чего больше нет: строка зазывала триалом
    // («7 дней бесплатно») у того, кто ещё не покупал. Дизайн 0.8.4 убрал
    // приманку из строки — подпись там теперь про набор («Фоны, рамки, цвет
    // линии, ручная поездка»), а обещание недели живёт на пейволе, где рядом
    // стоит цена и условия автопродления. Так этого и требует Review 3.1.2.

    /// **Находка аудита M1.** `introductoryOffer` у продукта есть ВСЕГДА, а
    /// право на него — нет. Вернувшемуся подписчику (отменил → передумал)
    /// пейвол обещал «7 дней бесплатно, потом 29,99 €», а списывалось
    /// 29,99 € сразу: это App Store Review 3.1.2 и потребительское право, а
    /// не косметика.
    func testTrialCaptionIsSilentWhenAppleWillNotGiveTheTrial() {
        let yearly = PlusProductInfo(
            id: PlusStore.yearlyID, displayPrice: "29,99 €", period: .yearly, trialDays: 7)

        let promised = PlusPaywallModel.plans([yearly], eligibleForIntro: true, lang: .ru)
        XCTAssertNotNil(promised.first?.caption, "тому, кто триал получит, — обещаем")

        let silent = PlusPaywallModel.plans([yearly], eligibleForIntro: false, lang: .ru)
        XCTAssertNil(silent.first?.caption, "тому, кто его уже съел, — ни слова")
        XCTAssertEqual(silent.first?.price, promised.first?.price, "цена та же самая")
    }
}
