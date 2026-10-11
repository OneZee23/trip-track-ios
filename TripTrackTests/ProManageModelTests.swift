import XCTest
@testable import TripTrack

/// «Ваш PRO» не обещает списания, которого не будет (0.8.9).
///
/// Экран встаёт между строкой PRO и системным листом Apple, и его строка о
/// подписке — единственное, что человек читает, решая, отменять ли. Поэтому
/// правило проверяется таблицей: отменившему продление — «работает до», без
/// цены; молчание Apple — дата без слова о продлении; цена — ДЕЙСТВУЮЩЕГО
/// тарифа, а не годового по умолчанию.
final class ProManageModelTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_822_000_000)

    func testTheLineNeverPromisesAChargeThatWillNotHappen() {
        let cases: [(ProStatus, PlusProductInfo.Period?, String?, Bool?, ProManageLine)] = [
            (.trial(until: date), .yearly, "24,99 €", true,
             .trialRenews(until: date, price: "24,99 €", period: .yearly)),
            (.active(until: date), .monthly, "5,99 €", true,
             .renews(on: date, price: "5,99 €", period: .monthly)),
            // Отменил продление в триале — ни слова о 24,99 €.
            (.trial(until: date), .yearly, "24,99 €", false, .endsOn(date)),
            (.active(until: date), .yearly, "24,99 €", false, .endsOn(date)),
            // Apple промолчала про продление — дата без обещаний.
            (.active(until: date), .yearly, "24,99 €", nil, .until(date)),
            // Продлится, но цены нет (продукты не приехали) — тоже без цены.
            (.trial(until: date), nil, nil, true, .until(date)),
            // Непродающая витрина: цену местной витрины не печатаем.
            (.proWithoutStore(until: date), .yearly, "24,99 €", true, .until(date)),
            (.proWithoutStore(until: date), .yearly, "24,99 €", false, .endsOn(date)),
            (.grace, .yearly, "24,99 €", true, .billingProblem),
            // Даты нет — строки нет, а не «до —».
            (.active(until: nil), .yearly, "24,99 €", true, .unknown),
        ]
        for (status, period, price, renews, expected) in cases {
            XCTAssertEqual(
                ProManageLine.resolve(status: status, period: period,
                                      productPrice: price, willAutoRenew: renews),
                expected, "\(status) renews=\(String(describing: renews))")
        }
    }

    /// Месячный тариф говорит «в месяц»: «потом 5,99 € в год» — это чужая
    /// цена за чужой срок.
    func testThePeriodWordFollowsThePlan() {
        let fmt: (Date) -> String = { _ in "12 окт." }
        let year = ProManageLine.renews(on: date, price: "X", period: .yearly).text(.ru, date: fmt)
        let month = ProManageLine.renews(on: date, price: "X", period: .monthly).text(.ru, date: fmt)
        XCTAssertEqual(year, "Продлится 12 окт. · X в год")
        XCTAssertEqual(month, "Продлится 12 окт. · X в месяц")
    }

    func testEveryLineIsFilledInEveryLanguage() {
        let lines: [ProManageLine] = [
            .trialRenews(until: date, price: "¤42", period: .yearly),
            .trialRenews(until: date, price: "¤42", period: .monthly),
            .renews(on: date, price: "¤42", period: .yearly),
            .renews(on: date, price: "¤42", period: .monthly),
            .endsOn(date), .until(date), .billingProblem,
        ]
        for lang in LanguageManager.Language.allCases {
            let texts = lines.compactMap { $0.text(lang, date: { _ in "D" }) }
            XCTAssertEqual(texts.count, lines.count, "\(lang)")
            XCTAssertEqual(Set(texts).count, texts.count, "\(lang): строки совпали — \(texts)")
            for t in texts {
                XCTAssertFalse(t.contains("{"), "\(lang): токен остался — «\(t)»")
            }
            // Строка о продлении несёт цену, строка об отмене — нет.
            XCTAssertTrue(texts[0].contains("¤42") && texts[2].contains("¤42"), "\(lang)")
            XCTAssertFalse(lines[4].text(lang, date: { _ in "D" })!.contains("¤42"), "\(lang)")
        }
        XCTAssertNil(ProManageLine.unknown.text(.ru, date: { _ in "D" }))
    }

    /// Ключ без строки в таблице откатывается на английский и молчит.
    func testEveryNewStringHasARowInEveryTable() {
        let strings: [(String, (LanguageManager.Language) -> String)] = [
            ("proManageTitle", AppStrings.proManageTitle),
            ("proManageIncluded", AppStrings.proManageIncluded),
            ("proManageManualOn", AppStrings.proManageManualOn),
            ("proManageAppStore", AppStrings.proManageAppStore),
            ("proManageAppStoreHint", AppStrings.proManageAppStoreHint),
            ("proManageVehicleCardWhere", AppStrings.proManageVehicleCardWhere),
            ("proManageEndsOn", { AppStrings.proManageEndsOn($0, date: "D") }),
            ("proManageUntil", { AppStrings.proManageUntil($0, date: "D") }),
            ("proManageRenewsYear", { AppStrings.proManageRenews($0, date: "D", price: "P", yearly: true) }),
            ("proManageRenewsMonth", { AppStrings.proManageRenews($0, date: "D", price: "P", yearly: false) }),
            ("proManageTrialRenewsYear", { AppStrings.proManageTrialRenews($0, date: "D", price: "P", yearly: true) }),
            ("proManageTrialRenewsMonth", { AppStrings.proManageTrialRenews($0, date: "D", price: "P", yearly: false) }),
        ]
        for (name, fn) in strings {
            let en = fn(.en)
            for lang in LanguageManager.Language.allCases where lang != .en {
                XCTAssertNotEqual(fn(lang), en, "\(name): у \(lang) строка осталась английской")
            }
        }
    }

    /// Несколько живых строк в группе: хоть одна продлевается — PRO не
    /// кончится; ни одной проверенной — не «отменил», а «не знаем».
    func testAutoRenewAcrossLiveRows() {
        XCTAssertEqual(PlusStore.autoRenews([false, true]), true)
        XCTAssertEqual(PlusStore.autoRenews([false]), false)
        XCTAssertNil(PlusStore.autoRenews([]))
    }

    /// Тариф берётся у строки, что кончается ПОЗЖЕ, — при равных датах первая
    /// найденная остаётся.
    func testPlanComesFromTheRowThatEndsLater() {
        let a = Date(timeIntervalSince1970: 100), b = Date(timeIntervalSince1970: 200)
        XCTAssertTrue(PlusStore.endsLater(b, than: a))
        XCTAssertFalse(PlusStore.endsLater(a, than: b))
        XCTAssertFalse(PlusStore.endsLater(a, than: a))
        XCTAssertTrue(PlusStore.endsLater(a, than: nil))
        XCTAssertFalse(PlusStore.endsLater(nil, than: a))
    }
}
