import XCTest
@testable import TripTrack

/// Память контекстного предложения.
///
/// Своё хранилище на каждый тест: правило, купленное `PrivacyZoneDisciplineTests`
/// — оставшееся от соседнего прогона значение в контейнере симулятора красит
/// чужой тест в другом конце набора.
final class ProOfferLedgerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var ledger: ProOfferLedger!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "pro.offer.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        ledger = ProOfferLedger(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        ledger = nil
        suite = nil
        super.tearDown()
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Пустая память

    func testAFreshLedgerKnowsNothing() {
        XCTAssertNil(ledger.lastOfferAt)
        XCTAssertNil(ledger.firstLaunchAt)
        XCTAssertNil(ledger.proExpiredAt)
        XCTAssertEqual(ledger.consecutiveDeclines, 0)
        XCTAssertEqual(ledger.totalDeclines, 0)
        XCTAssertTrue(ledger.shownMoments.isEmpty)
    }

    // MARK: - Первый запуск

    /// Пишется ОДИН раз. Перезапись сдвигала бы «семь дней» на каждом запуске,
    /// и порог входа не наступил бы никогда.
    func testFirstLaunchIsWrittenOnceAndNeverMoves() {
        ledger.rememberFirstLaunchIfNeeded(now)
        XCTAssertEqual(ledger.firstLaunchAt?.timeIntervalSince1970,
                       now.timeIntervalSince1970)

        ledger.rememberFirstLaunchIfNeeded(now.addingTimeInterval(86_400 * 40))
        XCTAssertEqual(ledger.firstLaunchAt?.timeIntervalSince1970,
                       now.timeIntervalSince1970, "дата первого запуска сдвинулась")
    }

    // MARK: - Показы

    func testShowingRecordsBothTheMomentAndTheTime() {
        ledger.recordShown(.tenTrips, at: now)
        XCTAssertEqual(ledger.shownMoments, [.tenTrips])
        XCTAssertEqual(ledger.lastOfferAt?.timeIntervalSince1970,
                       now.timeIntervalSince1970)

        ledger.recordShown(.oneMonth, at: now.addingTimeInterval(86_400 * 31))
        XCTAssertEqual(ledger.shownMoments, [.tenTrips, .oneMonth])
    }

    /// Один и тот же момент дважды не раздувает список.
    func testTheSameMomentIsNotStoredTwice() {
        ledger.recordShown(.expired, at: now)
        ledger.recordShown(.expired, at: now.addingTimeInterval(86_400 * 31))
        XCTAssertEqual(ledger.shownMoments, [.expired])
    }

    /// Незнакомое имя момента (откатились с будущей версии) молча
    /// отбрасывается: список показанного — не контракт, и ронять из-за него
    /// предложение нельзя.
    func testAnUnknownStoredMomentIsIgnoredNotFatal() {
        defaults.set(["tenTrips", "somethingFromTheFuture"],
                     forKey: "pro.offer.shown.v1")
        XCTAssertEqual(ledger.shownMoments, [.tenTrips])
    }

    // MARK: - Отказы

    func testDeclinesCountBothInARowAndInTotal() {
        ledger.recordDecline()
        ledger.recordDecline()
        XCTAssertEqual(ledger.consecutiveDeclines, 2)
        XCTAssertEqual(ledger.totalDeclines, 2)
    }

    /// Интерес отменяет ПАУЗУ, но не стирает историю отказов. Иначе «нет, нет,
    /// посмотрел, нет, нет, посмотрел» обходило бы правило трёх отказов вечно.
    func testInterestClearsThePauseButNotTheHistory() {
        ledger.recordDecline()
        ledger.recordDecline()
        ledger.recordInterest()
        XCTAssertEqual(ledger.consecutiveDeclines, 0)
        XCTAssertEqual(ledger.totalDeclines, 2, "история отказов стёрлась")

        ledger.recordDecline()
        XCTAssertEqual(ledger.totalDeclines, 3, "третий отказ обязан быть третьим")
    }

    // MARK: - Окончание подписки

    func testExpiryIsRememberedAndClearedOnRenewal() {
        ledger.recordProExpired(at: now)
        XCTAssertEqual(ledger.proExpiredAt?.timeIntervalSince1970,
                       now.timeIntervalSince1970)
        ledger.recordProExpired(at: nil)
        XCTAssertNil(ledger.proExpiredAt, "продление не сняло отметку")
    }

    // MARK: - Связка с политикой

    /// Память и политика обязаны сходиться: три отказа, записанные ledger'ом,
    /// закрывают предложение в `ProContextOffer`.
    func testThreeRecordedDeclinesActuallyCloseTheOffer() {
        ledger.rememberFirstLaunchIfNeeded(now.addingTimeInterval(-86_400 * 180))
        ledger.recordDecline()
        ledger.recordDecline()
        ledger.recordDecline()

        let input = ProContextOffer.Input(
            now: now,
            isPlus: false,
            storefrontHidesPlus: false,
            tripCount: 40,
            firstLaunchAt: ledger.firstLaunchAt,
            proExpiredAt: ledger.proExpiredAt,
            lastOfferAt: ledger.lastOfferAt,
            consecutiveDeclines: ledger.consecutiveDeclines,
            totalDeclines: ledger.totalDeclines,
            shownMoments: ledger.shownMoments,
            isFirstSession: false,
            recordedTripThisSession: false,
            hasNetwork: true,
            onEligibleScreen: true,
            alreadyShownThisSession: false)
        XCTAssertNil(ProContextOffer.moment(input))
    }
}
