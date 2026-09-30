import XCTest
@testable import TripTrack

/// Восемь ответов на «что человек видит в строке PRO».
///
/// Два из них — про витрину, и порядок проверок тот же, что у `PlusGate`:
/// `isPlus` ПЕРВЫМ. Купленная на другой витрине подписка обязана честно
/// работать там, где местная витрина больше ничего не продаёт (состояние 17а),
/// а не исчезать вместе с разделом.
final class ProStatusTests: XCTestCase {

    private let until = Date(timeIntervalSince1970: 1_822_000_000)

    func testSubscriptionBeatsStorefront() {
        let s = ProStatus.resolve(state: .active, expires: until,
                                  isPending: false, storefrontHidesPlus: true)
        XCTAssertEqual(s, .proWithoutStore(until: until),
                       "PRO на непродающей витрине — это 17а, а не 17")
        XCTAssertEqual(s.destination, .manageSubscription,
                       "продлевать негде, но управление подпиской открыть можно")
    }

    func testHiddenOnlyWhenThereIsNoSubscription() {
        let s = ProStatus.resolve(state: .none, expires: nil,
                                  isPending: false, storefrontHidesPlus: true)
        XCTAssertEqual(s, .hiddenStorefront)
        XCTAssertEqual(s.destination, .none, "строки нет вовсе")
        XCTAssertFalse(s.showsRow)
    }

    /// Закончившаяся подписка на непродающей витрине — тоже 17: продлевать
    /// негде, и строка, ведущая в пустоту, хуже отсутствующей.
    func testExpiredOnAHiddenStorefrontIsAlsoHidden() {
        let s = ProStatus.resolve(state: .expired, expires: until,
                                  isPending: false, storefrontHidesPlus: true)
        XCTAssertEqual(s, .hiddenStorefront)
    }

    func testEveryStatusHasItsOwnDestination() {
        let cases: [(ProStatus, ProRowDestination)] = [
            (.none, .paywall),
            (.trial(until: until), .manageSubscription),
            (.active(until: until), .manageSubscription),
            (.expired(on: until), .paywall),
            (.grace, .manageSubscription),
            (.pending, .nothing),
        ]
        for (status, expected) in cases {
            XCTAssertEqual(status.destination, expected, "\(status)")
            XCTAssertTrue(status.showsRow, "\(status): строка обязана быть")
        }
    }

    /// «Ждём подтверждения» сильнее права: Ask To Buy одобрен — право приедет
    /// само, и строка сменится на 13. До этого она не должна предлагать купить
    /// второй раз.
    func testPendingWinsOverNoEntitlement() {
        XCTAssertEqual(ProStatus.resolve(state: .none, expires: nil,
                                         isPending: true, storefrontHidesPlus: false),
                       .pending)
    }

    /// Заголовок у всех один, кроме закончившейся: у той он свой и с датой.
    func testTitleIsTheProductNameExceptWhenItEnded() {
        for lang in LanguageManager.Language.allCases {
            let name = AppStrings.meProNone(lang)
            for s in [ProStatus.none, .trial(until: until), .active(until: until),
                      .grace, .pending] {
                XCTAssertEqual(s.rowTitle(lang: lang), name, "\(lang)/\(s)")
            }
            let ended = ProStatus.expired(on: until).rowTitle(lang: lang)
            XCTAssertNotEqual(ended, name, "\(lang): у закончившейся свой заголовок")
            XCTAssertFalse(ended.contains("{date}"), "\(lang): токен не подставлен")
        }
    }

    /// **Находка ревью задачи 2.** `expiresAt` приходит из
    /// `currentEntitlements`, а тот при `.expired` права УЖЕ НЕ ОТДАЁТ — то
    /// есть в момент, когда дату надо показать, живого значения нет.
    /// `PlusStore.lastKnownExpiry` запоминает её, пока подписка работала, но
    /// у человека, чья подписка кончилась до обновления, не запомнено ничего.
    /// Тогда остаётся заголовок без даты — и без висящего пробела.
    func testExpiredTitleHasNoDanglingSpaceWithoutADate() {
        for lang in LanguageManager.Language.allCases {
            let t = ProStatus.expired(on: nil).rowTitle(lang: lang)
            XCTAssertFalse(t.isEmpty, "\(lang): пустой заголовок")
            XCTAssertFalse(t.contains("{date}"), "\(lang): токен остался — «\(t)»")
            XCTAssertEqual(t, t.trimmingCharacters(in: .whitespaces),
                           "\(lang): висящий пробел — «\(t)»")
        }
    }

    /// Строки различимы на всех тринадцати языках: одинаковая подпись у двух
    /// статусов — это экран, по которому нельзя понять, что происходит.
    func testStatusSubtitlesDifferInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            let texts = [
                ProStatus.none.rowSubtitle(lang: lang),
                ProStatus.trial(until: until).rowSubtitle(lang: lang),
                ProStatus.active(until: until).rowSubtitle(lang: lang),
                ProStatus.expired(on: until).rowSubtitle(lang: lang),
                ProStatus.grace.rowSubtitle(lang: lang),
                ProStatus.pending.rowSubtitle(lang: lang),
            ]
            XCTAssertEqual(Set(texts).count, texts.count, "\(lang): подписи совпали — \(texts)")
            for t in texts {
                XCTAssertFalse(t.isEmpty, "\(lang): пустая подпись")
                XCTAssertFalse(t.contains("{date}"), "\(lang): токен остался — «\(t)»")
            }
        }
    }

    /// Дата печатается по локали языка, а не литералом «ru_RU».
    func testDateIsPrintedInTheLanguageOfTheApp() {
        let ru = ProStatus.active(until: until).rowSubtitle(lang: .ru)
        let en = ProStatus.active(until: until).rowSubtitle(lang: .en)
        XCTAssertNotEqual(ru, en, "русская и английская подписи обязаны отличаться")
    }

    /// Ключ без строки в таблице откатывается на АНГЛИЙСКИЙ — то есть выглядит
    /// рабочим и молчит. Ловится только сравнением.
    func testEveryNewStringHasARowInEveryTable() {
        let strings: [(String, (LanguageManager.Language) -> String)] = [
            ("meProSection", AppStrings.meProSection),
            ("meProNoneSub", AppStrings.meProNoneSub),
            ("meProExpiredSub", AppStrings.meProExpiredSub),
            ("meProGraceSub", AppStrings.meProGraceSub),
            ("meProPendingSub", AppStrings.meProPendingSub),
        ]
        for (name, fn) in strings {
            let en = fn(.en)
            for lang in [LanguageManager.Language.ru, .de, .es, .fr, .it,
                         .pl, .id, .tr, .fil, .uk, .kk, .pt] {
                XCTAssertNotEqual(fn(lang), en, "\(name): у \(lang) строка осталась английской")
            }
        }
    }
}
