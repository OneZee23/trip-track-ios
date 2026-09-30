import XCTest
@testable import TripTrack

/// Витрина PRO по состояниям матрицы 0.8.4.
///
/// Проверяется НЕ картинка, а то, что в каждом состоянии на экране есть и чего
/// нет. Половину этих состояний открытым экраном не задать вовсе:
/// `SKTestSession` не умеет ни «Apple не ответила», ни «ждём одобрения
/// владельца семейной группы», — и ровно поэтому решение «что показывать»
/// вынесено из `body` в `ProPaywallPhase`.
final class ProPaywallStatesTests: XCTestCase {

    // MARK: - 1б: цены не загрузились

    /// Витрина без цен обязана остаться ВИТРИНОЙ: человек пришёл узнать, что
    /// такое PRO, и молчание в ответ хуже, чем отсутствие кнопки. А
    /// восстановление здесь и вовсе главное — его жмёт тот, кто уже платил.
    func testNoPricesKeepsTheSetAndRestoreButHidesBuying() {
        let phase = ProPaywallPhase.pricesFailed
        XCTAssertTrue(phase.showsFeatureSet, "набор из пяти виден всегда")
        XCTAssertTrue(phase.showsRestore, "восстановление работает без цен")
        XCTAssertFalse(phase.showsBuyButton, "покупать нечего")
        XCTAssertTrue(phase.showsRetry)
        XCTAssertTrue(phase.showsPricesFailedCard)
        XCTAssertFalse(phase.showsPlanRow)
    }

    // MARK: - 1а: цены едут

    func testLoadingShowsSkeletonNotEmptiness() {
        let phase = ProPaywallPhase.loading
        XCTAssertTrue(phase.showsFeatureSet)
        XCTAssertTrue(phase.showsTariffSkeleton)
        XCTAssertFalse(phase.showsRetry, "повторять ещё нечего — мы и не пробовали")
        XCTAssertFalse(phase.showsPlanRow)
        XCTAssertFalse(phase.allowsTariffChange, "выбирать не из чего")
    }

    // MARK: - 6: идёт покупка

    /// Пока идёт покупка, тарифы и крестик гаснут и не нажимаются: иначе
    /// человек закроет лист в середине системного диалога Apple и не узнает,
    /// чем всё кончилось.
    func testPurchasingLocksTariffsAndClose() {
        let phase = ProPaywallPhase.purchasing
        XCTAssertFalse(phase.allowsTariffChange)
        XCTAssertFalse(phase.allowsClose)
        XCTAssertTrue(phase.showsSpinnerInButton)
        XCTAssertTrue(phase.dimsChrome)
        XCTAssertTrue(phase.showsPlanRow, "тарифы на месте, просто не нажимаются")
    }

    /// Крестик гаснет РОВНО на время покупки и больше нигде: в остальных
    /// состояниях человек вправе уйти.
    func testCloseWorksEverywhereExceptDuringThePurchase() {
        for phase in Self.all where phase != .purchasing {
            XCTAssertTrue(phase.allowsClose, "\(phase) забрал выход")
        }
    }

    // MARK: - 7: ждём одобрения

    /// Ask To Buy: нажатие ничего не изменит, поэтому кнопки покупки нет, а
    /// вместо неё стоит «Понятно». Нажатие, которое ничего не делает, хуже
    /// отсутствующего.
    func testPendingReplacesBuyingWithAnAcknowledgement() {
        let phase = ProPaywallPhase.pending
        XCTAssertTrue(phase.showsPendingCard)
        XCTAssertFalse(phase.showsBuyButton)
        XCTAssertFalse(phase.showsPlanRow)
        XCTAssertFalse(phase.showsRetry)
        XCTAssertTrue(phase.allowsClose)
    }

    // MARK: - 9: куплено

    /// Витрины на этом экране больше нет вовсе — ни набора, ни восстановления.
    func testBoughtIsNotAStorefrontAnyMore() {
        let phase = ProPaywallPhase.bought
        XCTAssertFalse(phase.showsFeatureSet)
        XCTAssertFalse(phase.showsBuyButton)
        XCTAssertFalse(phase.showsRestore)
        XCTAssertFalse(phase.showsPlanRow)
    }

    // MARK: - Инвариант места под тарифами

    /// На месте тарифов стоит РОВНО ОДНА вещь: карточки, скелетон, ошибка цен
    /// или ожидание одобрения. Две сразу — это наложение, которого на экране
    /// не увидеть, пока не совпадут два условия; ни одной — пустая полоса в
    /// подвале.
    func testExactlyOneThingOccupiesTheTariffSlot() {
        for phase in Self.all where phase != .bought {
            let occupants = [phase.showsPlanRow,
                             phase.showsTariffSkeleton,
                             phase.showsPricesFailedCard,
                             phase.showsPendingCard].filter { $0 }.count
            XCTAssertEqual(occupants, 1, "\(phase): занято мест — \(occupants)")
        }
    }

    // MARK: - Сборка фазы из состояния стора

    /// Покупка сильнее всего: спиннер обязан появиться, даже если цены ещё не
    /// доехали (человек нажал ровно в этот момент).
    func testPurchaseBeatsEverythingElse() {
        XCTAssertEqual(
            ProPaywallView.phase(justBought: false, productsLoaded: false, hasPlans: false,
                                 isBusy: true, notice: .none),
            .purchasing)
    }

    /// «Ещё не спрашивали» и «спросили, не дали» — РАЗНЫЕ состояния (1а и 1б),
    /// хотя `PlusStore.products` в обоих пуст.
    func testEmptyProductsMeanDifferentThingsBeforeAndAfterTheAttempt() {
        XCTAssertEqual(
            ProPaywallView.phase(justBought: false, productsLoaded: false, hasPlans: false,
                                 isBusy: false, notice: .none),
            .loading)
        XCTAssertEqual(
            ProPaywallView.phase(justBought: false, productsLoaded: true, hasPlans: false,
                                 isBusy: false, notice: .none),
            .pricesFailed)
    }

    /// Ожидание одобрения переживает загрузку цен: карточка «Ждём
    /// подтверждения» не имеет права смениться тарифами, пока человек её не
    /// закрыл.
    func testPendingSurvivesThePriceState() {
        XCTAssertEqual(
            ProPaywallView.phase(justBought: false, productsLoaded: true, hasPlans: true,
                                 isBusy: false, notice: .pending),
            .pending)
    }

    /// Неудача — ТОСТ, а не состояние экрана: тарифы и кнопка остаются, чтобы
    /// попробовать снова можно было тем же нажатием.
    func testAFailureLeavesTheStorefrontAlone() {
        XCTAssertEqual(
            ProPaywallView.phase(justBought: false, productsLoaded: true, hasPlans: true,
                                 isBusy: false, notice: .failed),
            .priced)
    }

    /// «Куплено» показывается тому, кто НАЖАЛ кнопку, а не тому, у кого есть
    /// подписка: витрину открывает и действующий подписчик (из строки «Я» —
    /// «управлять»), и поздравлять его с покупкой, которой не было, нельзя.
    /// Поэтому признак — нажатие, и оно сильнее всех остальных.
    func testJustBoughtBeatsEverythingIncludingAPurchaseInFlight() {
        XCTAssertEqual(
            ProPaywallView.phase(justBought: true, productsLoaded: false,
                                 hasPlans: false, isBusy: true, notice: .pending),
            .bought)
        XCTAssertNotEqual(
            ProPaywallView.phase(justBought: false, productsLoaded: true,
                                 hasPlans: true, isBusy: false, notice: .none),
            .bought,
            "без нажатия «куплено» не показывается")
    }

    /// Отмену человеком тостом не сопровождаем — он сам закрыл системный лист.
    ///
    /// `message(for:)` отдаёт `PlusStore.PurchaseMessage`, а не опциональную
    /// строку: текст ошибки StoreKit на экран не попадает ни на одном языке,
    /// он английский и системный.
    func testCancelledSaysNothing() {
        XCTAssertEqual(PlusStore.message(for: .cancelled), .none)
        XCTAssertEqual(PlusStore.message(for: .success), .none)
        XCTAssertEqual(PlusStore.message(for: .pending), .pending)
    }

    private static let all: [ProPaywallPhase] = [
        .loading, .priced, .pricesFailed, .purchasing, .pending, .bought
    ]
}
