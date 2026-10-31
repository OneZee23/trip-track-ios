import Combine
import UIKit
import XCTest
@testable import TripTrack

/// Сессия контекстного предложения — заход в приложение, а не жизнь процесса.
///
/// Разбор покупок 29 окт 2026: флаг «в эту сессию записана поездка» держался
/// до смерти процесса, а процесс TripTrack живёт в фоне сутками. У того, кто
/// ездит каждый день, предложение PRO не появлялось вовсе.
@MainActor
final class ProOfferCoordinatorTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var states: PassthroughSubject<PlusStore.State, Never>!
    private var savedIsPlus = false
    private var savedHidesPlus = false

    override func setUp() {
        super.setUp()
        suite = "ProOfferCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        center = NotificationCenter()
        states = PassthroughSubject()
        // Правило читает живые права и витрину; тест не должен зависеть от
        // того, что оставил соседний класс.
        savedIsPlus = PlusAccess.shared.isPlus
        savedHidesPlus = PlusAccess.shared.storefrontHidesPlus
        PlusAccess.shared.isPlus = false
        PlusAccess.shared.storefrontHidesPlus = false
    }

    override func tearDown() {
        PlusAccess.shared.isPlus = savedIsPlus
        PlusAccess.shared.storefrontHidesPlus = savedHidesPlus
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        center = nil
        states = nil
        suite = nil
        super.tearDown()
    }

    /// Месяц с приложением, права уже ответили: дальше всё решает сессия.
    private func makeCoordinator(firstLaunchDaysAgo: Double? = 40) -> ProOfferCoordinator {
        let ledger = ProOfferLedger(defaults: defaults)
        if let days = firstLaunchDaysAgo {
            ledger.rememberFirstLaunchIfNeeded(Date().addingTimeInterval(-days * 86_400))
        }
        let coordinator = ProOfferCoordinator(
            ledger: ledger, plusStates: states.eraseToAnyPublisher(), center: center)
        states.send(PlusStore.State.none)
        return coordinator
    }

    func testATripRecordedInThisSessionBlocksOnlyThisSession() {
        let coordinator = makeCoordinator()
        center.post(name: .tripRecordingEnded, object: nil)
        coordinator.screenAppeared(hasNetwork: true, tripCount: 12)
        XCTAssertNil(coordinator.pending, "в заход, где записалась поездка, не предлагаем")

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        coordinator.screenAppeared(hasNetwork: true, tripCount: 12)
        XCTAssertEqual(coordinator.pending, .tenTrips,
                       "процесс тот же, но заход новый: поездка его больше не держит")
    }

    /// Процесс первого запуска, проживший в фоне больше недели: раньше он так
    /// и оставался «первой сессией».
    func testTheFirstSessionEndsWhenTheAppLeavesTheScreen() {
        let coordinator = makeCoordinator(firstLaunchDaysAgo: nil)
        defaults.set(Date().addingTimeInterval(-40 * 86_400).timeIntervalSince1970,
                     forKey: "pro.offer.firstLaunchAt.v1")
        coordinator.screenAppeared(hasNetwork: true, tripCount: 12)
        XCTAssertNil(coordinator.pending, "первый заход в приложение")

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        coordinator.screenAppeared(hasNetwork: true, tripCount: 12)
        XCTAssertEqual(coordinator.pending, .tenTrips)
    }

    func testWithoutATripTheOfferStillWaitsForItsThresholds() {
        let coordinator = makeCoordinator()
        coordinator.screenAppeared(hasNetwork: true, tripCount: 4)
        XCTAssertNil(coordinator.pending, "меньше пяти поездок")
        coordinator.screenAppeared(hasNetwork: true, tripCount: 12)
        XCTAssertEqual(coordinator.pending, .tenTrips)
    }
}
