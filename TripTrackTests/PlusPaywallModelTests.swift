import XCTest
import StoreKit
@testable import TripTrack

/// Строки пейвола собираются из ответа Apple, а не пишутся руками.
///
/// Проверять это можно только здесь: `Product` не собирается в тесте вовсе —
/// у него нет инициализатора, — поэтому между StoreKit и экраном стоит
/// `PlusProductInfo`, и таблица тарифов считается чистой функцией.
final class PlusPaywallModelTests: XCTestCase {

    /// Форматтер без локали нарочно: `.formatted()` взял бы разделитель
    /// симулятора и сделал тест шатким.
    private static func euro(_ v: Decimal) -> String {
        String(format: "%.2f €", NSDecimalNumber(decimal: v).doubleValue)
    }

    private let yearly = PlusProductInfo(
        id: PlusStore.yearlyID, displayPrice: "19,99 €", period: .yearly,
        trialDays: 7, price: 19.99, format: PlusPaywallModelTests.euro)
    private let monthly = PlusProductInfo(
        id: PlusStore.monthlyID, displayPrice: "2,99 €", period: .monthly,
        trialDays: nil, price: 2.99, format: PlusPaywallModelTests.euro)

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
        XCTAssertEqual(plans[0].title, "Год · 19,99 €")
        XCTAssertEqual(plans[1].title, "Месяц · 2,99 €")
        XCTAssertEqual(plans[0].displayPrice, "19,99 €")
        XCTAssertEqual(plans[1].displayPrice, "2,99 €")
    }

    /// Ни в одной из тринадцати строка тарифа не несёт своей валюты — только
    /// подставленную. Знак «€» в переводе значил бы, что человек в Грузии
    /// читает цену, которой не увидит на списании.
    func testNoLanguageWritesACurrencyOfItsOwn() {
        for lang in LanguageManager.Language.allCases {
            let plans = PlusPaywallModel.plans([yearly, monthly],
                                               eligibleForIntro: false, lang: lang)
            for plan in plans {
                let printed = plan.title + " " + (plan.caption ?? "")
                let stripped = printed
                    .replacingOccurrences(of: "19,99 €", with: "")
                    .replacingOccurrences(of: "2,99 €", with: "")
                    // «в месяц» приходит из `ProPriceMath`, напечатанное нашим
                    // тестовым форматтером: его евро тоже подставленное.
                    .replacingOccurrences(of: "1.67 €", with: "")
                for sign in ["€", "$", "£", "₽", "₾"] {
                    XCTAssertFalse(stripped.contains(sign),
                                   "\(lang.rawValue): в строке тарифа своя валюта — \(printed)")
                }
            }
        }
    }

    // MARK: - Подписи тарифов

    /// Годовому — обещание недели акцентом, месячному — честное «недели нет».
    func testCaptionsSayWhatEachTariffGives() {
        let plans = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: .ru)
        XCTAssertEqual(plans[0].caption, "Неделя бесплатно")
        XCTAssertTrue(plans[0].captionIsAccent, "обещание — акцентом")
        XCTAssertTrue(plans[0].hasFreeWeek)
        XCTAssertEqual(plans[1].caption, "Без пробной недели")
        XCTAssertFalse(plans[1].captionIsAccent)
        XCTAssertFalse(plans[1].hasFreeWeek, "у месячного недели нет НИКОГДА")
    }

    /// Недели не положено (состояние 4) — на её месте «в месяц», и это уже не
    /// обещание, а справка: серым.
    func testWithoutTheWeekTheYearlyShowsItsMonthlyPrice() {
        let plans = PlusPaywallModel.plans([yearly, monthly],
                                           eligibleForIntro: false, lang: .ru)
        XCTAssertEqual(plans[0].caption, "1.67 € в месяц")
        XCTAssertFalse(plans[0].captionIsAccent)
        XCTAssertFalse(plans[0].hasFreeWeek)
    }

    /// Цен числом не привезли — подписи «в месяц» нет вовсе, а не «0 € в
    /// месяц». Считать не из чего (правило `ProPriceMath`).
    func testNoNumericPriceMeansNoMonthlyCaption() {
        let bare = PlusProductInfo(id: PlusStore.yearlyID, displayPrice: "19,99 €",
                                   period: .yearly, trialDays: nil)
        let plans = PlusPaywallModel.plans([bare], eligibleForIntro: false, lang: .ru)
        XCTAssertNil(plans[0].caption)
        XCTAssertEqual(plans[0].title, "Год · 19,99 €", "цена строкой всё равно на месте")
    }

    func testCaptionsAreTranslatedEverywhere() {
        for lang in LanguageManager.Language.allCases {
            let plans = PlusPaywallModel.plans([yearly, monthly],
                                               eligibleForIntro: true, lang: lang)
            for plan in plans {
                let caption = plan.caption ?? ""
                XCTAssertFalse(caption.isEmpty, lang.rawValue)
                XCTAssertFalse(caption.contains("{"),
                               "\(lang.rawValue): токен не подставлен — \(caption)")
                XCTAssertFalse(plan.title.contains("{"),
                               "\(lang.rawValue): токен не подставлен — \(plan.title)")
            }
        }
    }

    // MARK: - Выгода

    /// «−44 %» на годовом и НИЧЕГО на месячном: выгода это свойство пары, а
    /// показывается она у того тарифа, который её даёт.
    func testSavingSitsOnTheYearlyOnly() {
        let plans = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: .ru)
        XCTAssertEqual(plans[0].savingPercent, 44)
        XCTAssertNil(plans[1].savingPercent)
    }

    /// Месячного не привезли — сравнивать не с чем, и чипа нет. Не ноль.
    func testNoSavingWithoutTheMonthlyToCompareTo() {
        let plans = PlusPaywallModel.plans([yearly], eligibleForIntro: true, lang: .ru)
        XCTAssertNil(plans[0].savingPercent)
    }

    // MARK: - Триал

    /// Длина предложения считается из периода Apple, а не угадывается. Неделя —
    /// семь дней, и именно так заведён `Config/TripTrack.storekit`.
    func testOfferLengthInDays() {
        XCTAssertEqual(PlusPaywallModel.days(unit: .week, value: 1), 7)
        XCTAssertEqual(PlusPaywallModel.days(unit: .day, value: 3), 3)
        XCTAssertEqual(PlusPaywallModel.days(unit: .month, value: 1), 30)
        XCTAssertEqual(PlusPaywallModel.days(unit: .year, value: 1), 365)
    }

    /// **Находка аудита M1.** `introductoryOffer` у продукта есть ВСЕГДА, а
    /// право на него — нет. Вернувшемуся подписчику (отменил → передумал)
    /// пейвол обещал «7 дней бесплатно, потом 29,99 €», а списывалось
    /// 29,99 € сразу: это App Store Review 3.1.2 и потребительское право, а
    /// не косметика.
    func testTrialIsSilentWhenAppleWillNotGiveIt() {
        let promised = PlusPaywallModel.plans([yearly], eligibleForIntro: true, lang: .ru)
        XCTAssertTrue(promised[0].hasFreeWeek, "тому, кто триал получит, — обещаем")
        XCTAssertEqual(promised[0].caption, "Неделя бесплатно")

        let silent = PlusPaywallModel.plans([yearly], eligibleForIntro: false, lang: .ru)
        XCTAssertFalse(silent[0].hasFreeWeek, "тому, кто его уже съел, — ни слова")
        XCTAssertNotEqual(silent[0].caption, "Неделя бесплатно")
        XCTAssertEqual(silent[0].title, promised[0].title, "цена та же самая")
    }

    /// **Копия обещает НЕДЕЛЮ, а Apple присылает ЧИСЛО дней.** Разойдись эти
    /// два — приложение обещало бы неделю там, где витрина даёт три дня, и это
    /// Review 3.1.2. Поэтому вся подача триала включается только при РОВНО
    /// семи днях; при любом другом числе пейвол ведёт себя как состояние 4 и
    /// не обещает ничего. Недообещать безопасно, переобещать — нет.
    func testAnOfferOfAnyOtherLengthIsNotPresentedAsAWeek() {
        for days in [1, 3, 14, 30] {
            let odd = PlusProductInfo(
                id: PlusStore.yearlyID, displayPrice: "19,99 €", period: .yearly,
                trialDays: days, price: 19.99, format: Self.euro)
            let plans = PlusPaywallModel.plans([odd], eligibleForIntro: true, lang: .ru)
            XCTAssertFalse(plans[0].hasFreeWeek, "\(days) дней обещаны как неделя")
            XCTAssertNotEqual(plans[0].caption, "Неделя бесплатно")
        }
    }

    // MARK: - Заголовки

    func testTitlesAreTheLanguagesOwnWords() {
        let de = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: .de)
        XCTAssertEqual(de.map(\.title), ["Jahr · 19,99 €", "Monat · 2,99 €"])
        let ru = PlusPaywallModel.plans([yearly, monthly], eligibleForIntro: true, lang: .ru)
        XCTAssertEqual(ru.map(\.title), ["Год · 19,99 €", "Месяц · 2,99 €"])
    }

    // Четыре теста подписи строки «Плюс» жили здесь до 0.8.4 и заменены
    // `ProStatusTests`: статусов стало восемь, два из них про витрину, и
    // отвечает на них `ProStatus`, а не `PlusRow`.
    //
    // Один из них описывал то, чего больше нет: строка зазывала триалом
    // («7 дней бесплатно») у того, кто ещё не покупал. Дизайн 0.8.4 убрал
    // приманку из строки — подпись там теперь про набор («Фоны, рамки, цвет
    // линии, ручная поездка»), а обещание недели живёт на пейволе, где рядом
    // стоит цена и условия автопродления. Так этого и требует Review 3.1.2.
}
