import XCTest
@testable import TripTrack

@MainActor
final class StoreHealthTests: XCTestCase {
    /// The destructive affordance must not be the first thing offered. A store
    /// that is merely not yet readable — the device has not been unlocked since
    /// boot — looks identical to a corrupt one, and the old code treated both
    /// as "throw it away".
    func testStartFreshIsOfferedOnlyAfterThreeFailures() {
        XCTAssertFalse(StoreHealth.offersStartFresh(failedAttempts: 0))
        XCTAssertFalse(StoreHealth.offersStartFresh(failedAttempts: 1))
        XCTAssertFalse(StoreHealth.offersStartFresh(failedAttempts: 2))
        XCTAssertTrue(StoreHealth.offersStartFresh(failedAttempts: 3))
        XCTAssertTrue(StoreHealth.offersStartFresh(failedAttempts: 9))
    }

    /// The recovery screen can succeed on the second or third attempt, so the
    /// bootstrap is reachable more than once. Starting SyncCoordinator twice
    /// duplicates its Combine subscriptions — no crash, just every sync trigger
    /// firing twice, which nobody notices until the log doubles.
    func testServicesStartExactlyOnce() {
        AppBootstrap.resetForTesting()
        var count = 0
        AppBootstrap.startServicesOnce { count += 1 }
        AppBootstrap.startServicesOnce { count += 1 }
        AppBootstrap.startServicesOnce { count += 1 }
        XCTAssertEqual(count, 1)
    }

    func testBootstrapCanBeResetBetweenTests() {
        AppBootstrap.resetForTesting()
        var first = 0
        AppBootstrap.startServicesOnce { first += 1 }
        XCTAssertEqual(first, 1)

        AppBootstrap.resetForTesting()
        var second = 0
        AppBootstrap.startServicesOnce { second += 1 }
        XCTAssertEqual(second, 1)
    }
}
