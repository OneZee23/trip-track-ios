import XCTest
@testable import TripTrack

/// Когда уместно попросить сказать спасибо.
///
/// Проверяется таблицей, потому что открытым экраном это не задать вовсе: на
/// «не чаще раза в полгода» ушло бы полгода, а на «два отказа — навсегда» —
/// две поездки по сто километров с интервалом в год. При этом ошибка в любом
/// из правил выглядит одинаково: приложение, которое клянчит.
final class TipMomentTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Человек, у которого всё сошлось: месяц с приложением, двадцать поездок,
    /// только что закончил сотню километров, никогда не отказывал.
    private func ready(_ tweak: (inout TipMoment.Input) -> Void = { _ in }) -> TipMoment.Input {
        var input = TipMoment.Input(
            now: now,
            storefrontHidesPlus: false,
            tripDistanceMetres: 120_000,
            isDraft: false,
            tripCount: 40,
            firstLaunchAt: now.addingTimeInterval(-90 * 86_400),
            lastAskedAt: nil,
            declines: 0,
            tippedAt: nil,
            afterFailure: false
        )
        tweak(&input)
        return input
    }

    func testAsksWhenEverythingLinedUp() {
        XCTAssertTrue(TipMoment.shouldAsk(ready()))
    }

    // MARK: - То, при чём чаевых не существует вовсе

    /// Витрина не продаёт платного (РФ или выключенный флаг) — просить нечем и
    /// незачем: платёж там всё равно не пройдёт.
    func testSilentWhereTheStorefrontSellsNothing() {
        XCTAssertFalse(TipMoment.shouldAsk(ready { $0.storefrontHidesPlus = true }))
    }

    /// Черновик ещё не признан своей поездкой (правило 0.8.1). Просить спасибо
    /// за чужую дорогу — худшее, что можно сделать этой карточкой.
    func testSilentOnADraft() {
        XCTAssertFalse(TipMoment.shouldAsk(ready { $0.isDraft = true }))
    }

    /// После ошибки не просят — то же правило, что у предложения PRO.
    func testSilentRightAfterAFailure() {
        XCTAssertFalse(TipMoment.shouldAsk(ready { $0.afterFailure = true }))
    }

    // MARK: - Пороги «пожил с приложением»

    func testSilentBeforeEnoughTrips() {
        XCTAssertFalse(TipMoment.shouldAsk(ready { $0.tripCount = TipMoment.minTrips - 1 }))
        XCTAssertTrue(TipMoment.shouldAsk(ready { $0.tripCount = TipMoment.minTrips }))
    }

    func testSilentBeforeEnoughDays() {
        XCTAssertFalse(TipMoment.shouldAsk(ready {
            $0.firstLaunchAt = self.now.addingTimeInterval(-Double(TipMoment.minDays - 1) * 86_400)
        }))
    }

    /// Не знаем, когда человек поставил приложение, — «месяц» считать не от
    /// чего. Молчим, а не считаем от нуля.
    func testSilentWhenTheInstallDateIsUnknown() {
        XCTAssertFalse(TipMoment.shouldAsk(ready { $0.firstLaunchAt = nil }))
    }

    // MARK: - Заметная дорога

    /// Городская поездка момента не создаёт, и это не пробел: просить подарок
    /// за дорогу до магазина не за что.
    func testSilentOnAnOrdinaryDrive() {
        XCTAssertFalse(TipMoment.shouldAsk(ready { $0.tripDistanceMetres = 12_000 }))
        XCTAssertTrue(TipMoment.shouldAsk(ready {
            $0.tripDistanceMetres = TipMoment.notableMetres
        }))
    }

    // MARK: - Частота

    func testDoesNotAskTwiceWithinHalfAYear() {
        XCTAssertFalse(TipMoment.shouldAsk(ready {
            $0.lastAskedAt = self.now.addingTimeInterval(-Double(TipMoment.cooldownDays - 1) * 86_400)
        }))
        XCTAssertTrue(TipMoment.shouldAsk(ready {
            $0.lastAskedAt = self.now.addingTimeInterval(-Double(TipMoment.cooldownDays) * 86_400)
        }))
    }

    /// Один отказ растягивает паузу до года. Отказ — это ответ, и повторять
    /// вопрос через полгода после него было бы так же навязчиво, как не
    /// спрашивать вовсе — бессмысленно.
    func testOneDeclineStretchesThePauseToAYear() {
        let almostAYear = -Double(TipMoment.cooldownAfterDeclineDays - 1) * 86_400
        XCTAssertFalse(TipMoment.shouldAsk(ready {
            $0.declines = 1
            $0.lastAskedAt = self.now.addingTimeInterval(almostAYear)
        }))
        XCTAssertTrue(TipMoment.shouldAsk(ready {
            $0.declines = 1
            $0.lastAskedAt = self.now.addingTimeInterval(
                -Double(TipMoment.cooldownAfterDeclineDays) * 86_400)
        }))
    }

    /// Два отказа — вопрос закрыт НАВСЕГДА, сколько бы лет ни прошло. Строка в
    /// подвале «Я» при этом остаётся: передумавший найдёт её сам.
    func testTwoDeclinesCloseTheQuestionForever() {
        XCTAssertFalse(TipMoment.shouldAsk(ready {
            $0.declines = TipMoment.maxDeclines
            $0.lastAskedAt = self.now.addingTimeInterval(-10 * 365 * 86_400)
        }))
    }

    /// Поблагодарил — год тишины. Не «никогда»: тот, кто дал раз, чаще всего и
    /// есть тот, кто захочет ещё.
    func testQuietForAYearAfterATip() {
        XCTAssertFalse(TipMoment.shouldAsk(ready {
            $0.tippedAt = self.now.addingTimeInterval(
                -Double(TipMoment.quietAfterTipDays - 1) * 86_400)
        }))
        XCTAssertTrue(TipMoment.shouldAsk(ready {
            $0.tippedAt = self.now.addingTimeInterval(
                -Double(TipMoment.quietAfterTipDays) * 86_400)
        }))
    }

    /// Часы телефона уехали назад — отрицательная разница читается как «только
    /// что», а не как «давно». Иначе переведённое время открыло бы вопрос,
    /// который человек уже закрыл.
    func testClockGoingBackwardsDoesNotReopenTheQuestion() {
        XCTAssertFalse(TipMoment.shouldAsk(ready {
            $0.lastAskedAt = self.now.addingTimeInterval(+30 * 86_400)
        }))
    }

    // MARK: - Порядок правил

    /// Скрытая витрина перевешивает ВСЁ остальное, даже идеально подошедший
    /// момент: платного там нет ни в каком виде.
    func testHiddenStorefrontBeatsEveryOtherCondition() {
        XCTAssertFalse(TipMoment.shouldAsk(ready {
            $0.storefrontHidesPlus = true
            $0.tripDistanceMetres = 1_000_000
            $0.tripCount = 500
        }))
    }
}
