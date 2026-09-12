import XCTest
@testable import TripTrack

/// Подъём пилюли таб-бара над индикатором «домой» (0.6.8): зазор до
/// индикатора равен боковому полю; на телефонах с кнопкой — канонные 14 pt.
final class CustomTabBarLiftTests: XCTestCase {

    func testHomeIndicatorPhoneGetsSideMarginGap() {
        let lift = CustomTabBar.bottomLift(bottomInset: 34)
        XCTAssertEqual(lift, 24)
        XCTAssertEqual(lift - CustomTabBar.homeIndicatorTop, CustomTabBar.sideMargin)
    }

    func testHomeButtonPhoneKeepsCanon() {
        XCTAssertEqual(CustomTabBar.bottomLift(bottomInset: 0), 14)
    }

    /// Клиренс считается от ФАКТИЧЕСКОГО инсета, а не от пола: с индикатором
    /// 74 + 24 + 8, без него 74 + 14 + 8.
    func testClearanceFollowsInset() {
        XCTAssertEqual(CustomTabBar.clearance(bottomInset: 34), 106)
        XCTAssertEqual(CustomTabBar.clearance(bottomInset: 0), 96)
    }
}
