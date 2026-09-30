import XCTest
@testable import TripTrack

/// Правило частоты контекстного предложения — состояние 11 матрицы 0.8.4.
///
/// Проверять это можно только здесь. «Не чаще одного листа в 30 дней», «два
/// отказа подряд дают паузу 90 дней», «три отказа выключают навсегда» —
/// правила, на проверку которых открытым экраном ушли бы месяцы, а ошибка в
/// любом из них выглядит как приложение, которое просит денег у человека,
/// трижды сказавшего «нет».
final class ProContextOfferTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ago(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// Человек, которому предложить МОЖНО: полгода с приложением, сорок
    /// поездок, ни одного отказа, стоит на «Ленте».
    private func eligible() -> ProContextOffer.Input {
        ProContextOffer.Input(
            now: now,
            isPlus: false,
            storefrontHidesPlus: false,
            tripCount: 40,
            firstLaunchAt: ago(180),
            proExpiredAt: nil,
            lastOfferAt: nil,
            consecutiveDeclines: 0,
            totalDeclines: 0,
            shownMoments: [],
            isFirstSession: false,
            recordedTripThisSession: false,
            hasNetwork: true,
            onEligibleScreen: true,
            alreadyShownThisSession: false,
            entitlementsKnown: true,
            afterFailure: false,
            fromPush: false)
    }

    // MARK: - База

    func testTheEligiblePersonGetsAnOffer() {
        XCTAssertNotNil(ProContextOffer.moment(eligible()))
    }

    // MARK: - Запреты, которые не обсуждаются

    /// Каждый из семи запретов ОДИН закрывает лист. Проверяется по одному, а
    /// не всеми сразу: иначе сломанный запрет прятался бы за исправным
    /// соседом.
    func testEachHardBlockAloneIsEnough() {
        let blocks: [(String, (inout ProContextOffer.Input) -> Void)] = [
            ("подписка активна", { $0.isPlus = true }),
            ("права ещё не приехали", { $0.entitlementsKnown = false }),
            ("нет сети", { $0.hasNetwork = false }),
            ("первая сессия", { $0.isFirstSession = true }),
            ("только что записал поездку", { $0.recordedTripThisSession = true }),
            ("после ошибок", { $0.afterFailure = true }),
            ("из пуша", { $0.fromPush = true }),
            ("не тот экран", { $0.onEligibleScreen = false }),
            ("в этой сессии уже показывали", { $0.alreadyShownThisSession = true })
        ]
        for (why, apply) in blocks {
            var input = eligible()
            apply(&input)
            XCTAssertNil(ProContextOffer.moment(input), "не закрыл лист: \(why)")
            XCTAssertTrue(ProContextOffer.isUnconditionallyBlocked(input), why)
        }
    }

    /// Безусловные запреты сильнее ВСЕГО, включая статус M4: он единственный,
    /// кто свободен от порогов, но не от них.
    func testTheUnconditionalBlocksStopEvenTheNotice() {
        let blocks: [(String, (inout ProContextOffer.Input) -> Void)] = [
            ("права ещё не приехали", { $0.entitlementsKnown = false }),
            ("нет сети", { $0.hasNetwork = false }),
            ("первая сессия", { $0.isFirstSession = true }),
            ("только что записал поездку", { $0.recordedTripThisSession = true }),
            ("после ошибок", { $0.afterFailure = true }),
            ("из пуша", { $0.fromPush = true }),
            ("не тот экран", { $0.onEligibleScreen = false }),
            ("в этой сессии уже показывали", { $0.alreadyShownThisSession = true })
        ]
        for (why, apply) in blocks {
            var input = eligible()
            input.proExpiredAt = ago(3)
            apply(&input)
            XCTAssertNil(ProContextOffer.moment(input), "M4 прошёл мимо запрета: \(why)")
        }
    }

    /// **M4 — СТАТУС, а не продажа: без порогов и без счётчика.**
    ///
    /// Спека говорит это дважды — §11 («статус, без порогов и счётчика») и
    /// чек-лист приёмки, пункт 9 («M4 без порогов и без счётчика»). Первая
    /// редакция подчиняла его всем гейтам подряд, и цена была конкретной:
    /// человек трижды отказался от M1/M3 (обычное дело — правило трёх отказов
    /// ровно для таких), потом оформил PRO сам из строки «Я», попользовался,
    /// подписка истекла — и он НИКОГДА не узнал бы, что оформление сохранено
    /// и вернётся с подпиской, а вписанные поездки на месте. Это единственное,
    /// зачем M4 существует.
    func testExpiryIgnoresEveryThresholdAndEveryRefusal() {
        var input = eligible()
        input.proExpiredAt = ago(2)
        // Нарушено ВСЁ сразу: одна поездка, один день с приложением, лист
        // показывали вчера, девять отказов, девять подряд.
        input.tripCount = 1
        input.firstLaunchAt = ago(1)
        input.lastOfferAt = ago(1)
        input.totalDeclines = 9
        input.consecutiveDeclines = 9
        XCTAssertEqual(ProContextOffer.moment(input), .expired,
                       "M4 — статус, а не продажа")
    }

    /// И обратное: те же нарушения закрывают М1 и М3 наглухо. Иначе
    /// освобождение M4 было бы освобождением всех.
    func testTheSameViolationsStillCloseTheOffers() {
        var input = eligible()
        input.tripCount = 1
        input.firstLaunchAt = ago(1)
        input.lastOfferAt = ago(1)
        input.totalDeclines = 9
        input.consecutiveDeclines = 9
        XCTAssertNil(ProContextOffer.moment(input))
        XCTAssertTrue(ProContextOffer.isBlocked(input, for: .tenTrips))
        XCTAssertTrue(ProContextOffer.isBlocked(input, for: .oneMonth))
        XCTAssertFalse(ProContextOffer.isBlocked(input, for: .expired))
    }

    /// Скрытая витрина закрывает ПРЕДЛОЖЕНИЕ, но не ИЗВЕЩЕНИЕ.
    ///
    /// §11 спеки запрещает лист при скрытой витрине, а матрица требует
    /// обратного для 17а («M4 с одной кнопкой „Понятно"»). Разрешено по
    /// смыслу: M1 и M3 продают, M4 сообщает, что оформление откатилось. Не
    /// сказать об этом значило бы молча сменить человеку профиль.
    func testAHiddenStorefrontSilencesTheOffersButNotTheNotice() {
        var offer = eligible()
        offer.storefrontHidesPlus = true
        offer.tripCount = 10
        XCTAssertNil(ProContextOffer.moment(offer), "M1 продаёт — молчит")

        var month = eligible()
        month.storefrontHidesPlus = true
        month.shownMoments = [.tenTrips]
        month.firstLaunchAt = ago(40)
        XCTAssertNil(ProContextOffer.moment(month), "M3 продаёт — молчит")

        var notice = eligible()
        notice.storefrontHidesPlus = true
        notice.proExpiredAt = ago(3)
        XCTAssertEqual(ProContextOffer.moment(notice), .expired,
                       "извещение обязано доехать и на скрытой витрине")
        XCTAssertFalse(ProContextOffer.sells(.expired, storefrontHidesPlus: true),
                       "вести некуда — кнопка одна")
        XCTAssertTrue(ProContextOffer.sells(.expired, storefrontHidesPlus: false))
    }

    /// Подписка сильнее ВСЕГО, включая момент «PRO закончился»: у активной
    /// подписки нет состояния «закончилась».
    func testAnActivePlusBeatsEvenTheExpiredMoment() {
        var input = eligible()
        input.isPlus = true
        input.proExpiredAt = ago(3)
        XCTAssertNil(ProContextOffer.moment(input))
    }

    // MARK: - Порог входа

    func testNothingBeforeTheFifthTripAndTheSeventhDay() {
        var young = eligible()
        young.tripCount = 4
        XCTAssertNil(ProContextOffer.moment(young), "четыре поездки — рано")

        var fresh = eligible()
        fresh.firstLaunchAt = ago(6)
        XCTAssertNil(ProContextOffer.moment(fresh), "шесть дней — рано")

        var exactly = eligible()
        exactly.tripCount = ProContextOffer.minTrips
        exactly.firstLaunchAt = ago(ProContextOffer.minDays)
        exactly.shownMoments = [.tenTrips, .oneMonth]
        XCTAssertFalse(ProContextOffer.isBlocked(exactly, for: .tenTrips),
                       "ровно на пороге запрета уже нет")
    }

    /// Дня первого запуска не знаем — «семь дней» считать не от чего, и
    /// молчим. Не «показываем, раз не знаем».
    func testAnUnknownFirstLaunchMeansSilence() {
        var input = eligible()
        input.firstLaunchAt = nil
        XCTAssertNil(ProContextOffer.moment(input))
    }

    // MARK: - Окно 30 дней

    func testNoMoreThanOneSheetInThirtyDays() {
        var recent = eligible()
        recent.lastOfferAt = ago(29)
        XCTAssertNil(ProContextOffer.moment(recent))

        var due = eligible()
        due.lastOfferAt = ago(30)
        XCTAssertNotNil(ProContextOffer.moment(due), "тридцать дней прошло")
    }

    // MARK: - Отказы

    /// Два «Не сейчас» подряд — пауза 90 дней, а не 30. Окно проверяется от
    /// ТОГО ЖЕ последнего показа: другой точки отсчёта у паузы нет.
    func testTwoDeclinesInARowBuyNinetyDaysOfSilence() {
        var paused = eligible()
        paused.consecutiveDeclines = 2
        paused.totalDeclines = 2
        paused.lastOfferAt = ago(60)
        XCTAssertNil(ProContextOffer.moment(paused), "шестьдесят дней внутри паузы")

        var over = paused
        over.lastOfferAt = ago(90)
        XCTAssertNotNil(ProContextOffer.moment(over), "пауза кончилась")
    }

    /// Один отказ паузы НЕ даёт: человек мог просто закрыть лист.
    func testASingleDeclineDoesNotBuyThePause() {
        var input = eligible()
        input.consecutiveDeclines = 1
        input.totalDeclines = 1
        input.lastOfferAt = ago(31)
        XCTAssertNotNil(ProContextOffer.moment(input))
    }

    /// Три отказа — это ОТВЕТ, а не пауза. Сколько бы ни прошло времени.
    func testThreeDeclinesTurnItOffForever() {
        var input = eligible()
        input.totalDeclines = 3
        input.consecutiveDeclines = 0
        input.lastOfferAt = ago(3650)
        XCTAssertNil(ProContextOffer.moment(input), "десять лет спустя — всё равно нет")
    }

    // MARK: - Какой момент

    /// «PRO закончился» первым: человек, у которого PRO было, отвечает на
    /// другой вопрос — не «зачем это», а «вернуть ли».
    func testTheExpiredMomentWinsOverTheThresholds() {
        var input = eligible()
        input.proExpiredAt = ago(5)
        XCTAssertEqual(ProContextOffer.moment(input), .expired)
    }

    func testTenTripsComesBeforeTheMonth() {
        var input = eligible()
        input.tripCount = 10
        input.firstLaunchAt = ago(40)
        XCTAssertEqual(ProContextOffer.moment(input), .tenTrips)
    }

    /// Порог «десять поездок» уже сработал — дальше отвечает месяц.
    func testTheMonthComesAfterTenTripsWasAlreadyShown() {
        var input = eligible()
        input.shownMoments = [.tenTrips]
        input.firstLaunchAt = ago(40)
        XCTAssertEqual(ProContextOffer.moment(input), .oneMonth)
    }

    /// Одноразовые моменты ПОВТОРНО не показываются: «уже десять поездок»,
    /// сказанное дважды, — это абсурд, а не напоминание.
    func testOneOffMomentsNeverRepeat() {
        var input = eligible()
        input.shownMoments = [.tenTrips, .oneMonth]
        XCTAssertNil(ProContextOffer.moment(input))
    }

    /// А вот «PRO закончился» повторяем: это СТАТУС, у него нет порога,
    /// который переходят один раз (спека §11). Ограничивают его общее окно
    /// 30 дней и три отказа, а не список показанного.
    func testTheExpiredMomentIsAStatusAndMayRepeat() {
        var input = eligible()
        input.shownMoments = [.tenTrips, .oneMonth, .expired]
        input.proExpiredAt = ago(120)
        input.lastOfferAt = ago(31)
        XCTAssertEqual(ProContextOffer.moment(input), .expired)
    }

    /// Поездок ещё девять, месяца ещё нет — предложить нечего, хотя запретов
    /// тоже нет. `nil` здесь значит «повода нет», и это не то же самое, что
    /// «нельзя».
    func testNoThresholdReachedMeansNoOffer() {
        var input = eligible()
        input.tripCount = 9
        input.firstLaunchAt = ago(20)
        XCTAssertFalse(ProContextOffer.isBlocked(input, for: .tenTrips),
                       "запретов нет")
        XCTAssertNil(ProContextOffer.moment(input), "но и повода нет")
    }

    // MARK: - Куда ведёт

    /// Момент обещает конкретную вещь и вести обязан на её страницу, а не в
    /// общий список: «профиль можно оформить» → фон профиля, «маршрут любого
    /// цвета» → цвет линии.
    func testEachMomentLeadsToWhatItPromised() {
        XCTAssertEqual(ProContextOffer.feature(for: .tenTrips), .profileBackgrounds)
        XCTAssertEqual(ProContextOffer.feature(for: .oneMonth), .routeLineStyle)
        // Точным значением, а не «одна из пяти»: подмена фичи у извещения
        // проходила мимо всех проверок (находка ревью), и человек увидел бы
        // превью не того, о чём ему сообщают.
        XCTAssertEqual(ProContextOffer.feature(for: .expired), .profileBackgrounds)
        for moment in ProOfferMoment.allCases {
            XCTAssertTrue(PlusFeature.allCases.contains(
                ProContextOffer.feature(for: moment)), "\(moment)")
        }
    }

    // MARK: - Сутки

    /// Сутки считаются секундами, а не календарём: часовой пояс, сменившийся
    /// в поездке, не имеет права подарить человеку лишний лист.
    func testDaysAreWholeElapsedDaysNotCalendarDays() {
        XCTAssertEqual(ProContextOffer.days(from: ago(30), to: now), 30)
        XCTAssertEqual(ProContextOffer.days(from: now.addingTimeInterval(-86_399), to: now), 0,
                       "почти сутки — это ещё ноль суток")
        XCTAssertEqual(ProContextOffer.days(from: now, to: now), 0)
    }
}
