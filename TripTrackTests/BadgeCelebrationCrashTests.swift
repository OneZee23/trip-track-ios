import XCTest
@testable import TripTrack

/// APPLE-IOS-3 (Sentry): 8 падений EXC_BREAKPOINT в 0.6.7–0.8.1, все в
/// `BadgeCelebrationView.body`, строка `badges[currentIndex]`. Родитель
/// очищает `pendingBadges` до конца закрывающей анимации, и тело
/// перерисовывается с пустым массивом.
final class BadgeCelebrationCrashTests: XCTestCase {
    private let a = (badge: Badge.all[0], count: 1)
    private let b = (badge: Badge.all[1], count: 2)

    func testEmptyLiveListDuringDismissKeepsTheShownBadge() {
        let item = BadgeCelebrationView.item(at: 0, shown: [a], live: [])
        XCTAssertEqual(item?.badge.id, a.badge.id)
    }

    func testNothingToShowDoesNotCrash() {
        XCTAssertNil(BadgeCelebrationView.item(at: 0, shown: [], live: []))
    }

    func testIndexPastTheEndIsClamped() {
        XCTAssertEqual(BadgeCelebrationView.item(at: 5, shown: [a, b], live: [])?.badge.id, b.badge.id)
        XCTAssertEqual(BadgeCelebrationView.item(at: -1, shown: [], live: [a, b])?.badge.id, a.badge.id)
    }

    func testBeforeAppearTheLiveListIsUsed() {
        XCTAssertEqual(BadgeCelebrationView.item(at: 1, shown: [], live: [a, b])?.badge.id, b.badge.id)
    }
}
