import XCTest
@testable import TripTrack

/// Геометрия платной части — числами по пяти телефонам.
///
/// Источник чисел — `design/pro/tokens.json → devices`, и ТОЛЬКО он: в §2 и §9
/// документа хендоффа и в матрице подвал записан как 184, хотя его собственные
/// части дают 192 (+ низ). Разница в восемь точек делает запас 13 mini не «8»,
/// а нулевым, и заметить это можно только арифметикой.
final class ProLayoutTests: XCTestCase {

    private let se    = ProLayout(height: 667, safeTop: 20, safeBottom: 0)
    private let mini  = ProLayout(height: 812, safeTop: 50, safeBottom: 34)
    private let base  = ProLayout(height: 844, safeTop: 47, safeBottom: 34)
    private let i15   = ProLayout(height: 852, safeTop: 59, safeBottom: 34)
    private let max15 = ProLayout(height: 932, safeTop: 59, safeBottom: 34)

    /// Подвал = 192 частей плюс низ: индикатор 34, а без него поле 4.
    func testFooterIsPartsPlusBottom() {
        XCTAssertEqual(se.footer, 196, "SE: 192 + поле 4")
        for (name, l) in [("mini", mini), ("13/14", base), ("15/16", i15), ("Max", max15)] {
            XCTAssertEqual(l.footer, 226, "\(name): 192 + индикатор 34")
        }
    }

    func testRoomMatchesTokensOnEveryPhone() {
        XCTAssertEqual(se.roomAboveFooter, 451)
        XCTAssertEqual(mini.roomAboveFooter, 536)
        XCTAssertEqual(base.roomAboveFooter, 571)
        XCTAssertEqual(i15.roomAboveFooter, 567)
        XCTAssertEqual(max15.roomAboveFooter, 647)
    }

    /// Гибрид: прокрутка только там, где не влезает. На 13 mini запас РОВНО
    /// ноль — в матрице написано «8», и это та самая ошибка на восемь точек.
    func testOnlySEScrollsAndMiniFitsExactly() {
        XCTAssertTrue(se.paywallScrolls)
        XCTAssertEqual(se.hiddenBelowFold, 85)

        XCTAssertFalse(mini.paywallScrolls)
        XCTAssertEqual(mini.roomAboveFooter - ProLayout.contentAboveFooter, 0,
                       "у 13 mini запаса нет вовсе")

        for l in [base, i15, max15] { XCTAssertFalse(l.paywallScrolls) }
        XCTAssertEqual(base.roomAboveFooter - ProLayout.contentAboveFooter, 35)
        XCTAssertEqual(i15.roomAboveFooter - ProLayout.contentAboveFooter, 31)
        XCTAssertEqual(max15.roomAboveFooter - ProLayout.contentAboveFooter, 111)
    }

    func testContextSheetLineSheetMapAndDialog() {
        XCTAssertEqual(se.contextSheet(titleLines: 1), 383)
        XCTAssertEqual(base.contextSheet(titleLines: 1), 401)
        XCTAssertEqual(base.contextSheet(titleLines: 2), 427)

        XCTAssertEqual(se.lineSheet, 537)
        XCTAssertEqual(base.lineSheet, 555)

        XCTAssertEqual(se.manualMap, 267)
        XCTAssertEqual(mini.manualMap, 325)
        XCTAssertEqual(base.manualMap, 338)
        XCTAssertEqual(i15.manualMap, 341)
        XCTAssertEqual(max15.manualMap, 373)

        XCTAssertEqual(se.dialogTop, 214)
        XCTAssertEqual(base.dialogTop, 302)
        XCTAssertEqual(max15.dialogTop, 346)
    }

    // MARK: - Число строк заголовка контекстного листа

    /// Считается по ДЛИНЕ СТРОКИ, а не по номеру момента: «PRO закончился» —
    /// одна строка на любом языке, а «Уже десять поездок. Профиль можно
    /// оформить» — две, и по-немецки длиннее русского.
    func testTitleLinesFollowTheStringNotTheMoment() {
        XCTAssertEqual(ProLayout.titleLines(for: "PRO закончился"), 1)
        XCTAssertEqual(
            ProLayout.titleLines(for: "Уже десять поездок. Профиль можно оформить"), 2)
        XCTAssertEqual(ProLayout.titleLines(for: ""), 1)
    }

    /// Порог ошибается в сторону ДВУХ строк: лист на 26 pt выше нужного
    /// показывает пустое место внизу, а на 26 pt ниже — обрезает кнопку.
    func testTheThresholdErrsTowardsTheTallerSheet() {
        let short = String(repeating: "a", count: ProLayout.titleCharactersPerLine)
        let long = short + "a"
        XCTAssertEqual(ProLayout.titleLines(for: short), 1)
        XCTAssertEqual(ProLayout.titleLines(for: long), 2)

        let phone = ProLayout(height: 844, safeTop: 47, safeBottom: 34)
        XCTAssertGreaterThan(phone.contextSheet(titleLines: 2),
                             phone.contextSheet(titleLines: 1),
                             "две строки обязаны давать лист выше")
        XCTAssertEqual(phone.contextSheet(titleLines: 2)
                       - phone.contextSheet(titleLines: 1), 26,
                       "вторая строка заголовка стоит ровно 26 pt")
    }

    /// Ни один заголовок момента ни на одном из тринадцати языков не уходит в
    /// ТРИ строки: третьей высоты у листа нет вовсе, и она обрезала бы кнопку.
    func testNoMomentTitleOverflowsTwoLinesInAnyLanguage() {
        let budget = ProLayout.titleCharactersPerLine * 2
        for lang in LanguageManager.Language.allCases {
            for moment in ProOfferMoment.allCases {
                let title = ProContextSheet.title(moment, lang)
                XCTAssertLessThanOrEqual(
                    title.count, budget,
                    "\(lang.rawValue) \(moment): «\(title)» не влезает в две строки")
            }
        }
    }
}
