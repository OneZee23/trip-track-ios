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

    /// Клиренс обязан покрывать пилюлю с подъёмом при любом окне — иначе
    /// последняя строка экрана прячется под бар.
    func testClearanceCoversPillAndLift() {
        XCTAssertGreaterThanOrEqual(CustomTabBar.clearance, CustomTabBar.pillHeight + 14 + 8)
    }
}
