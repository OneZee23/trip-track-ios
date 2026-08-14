import XCTest
@testable import TripTrack

/// Coverage for `VehicleLevelSystem` after the ten-rung ladder with names was
/// replaced by an open-ended one where the step from level N to N+1 costs
/// N × 100 km. The numbers here come from the spec, not from the
/// implementation — if someone re-derives the formula, these are what must
/// still hold.
final class VehicleLevelSystemTests: XCTestCase {

    // MARK: - The spec's own examples

    /// «1→2: 100 км» — the first step is one hundred kilometres.
    func testFirstStepIsOneHundredKilometres() {
        XCTAssertEqual(VehicleLevelSystem.kmForLevel(1), 0)
        XCTAssertEqual(VehicleLevelSystem.kmForLevel(2), 100)
        XCTAssertEqual(VehicleLevelSystem.level(for: 99.9), 1)
        XCTAssertEqual(VehicleLevelSystem.level(for: 100), 2)
    }

    /// «10→11: 1000 км» — the tenth step is ten times the first.
    func testTenthStepIsOneThousandKilometres() {
        let step = VehicleLevelSystem.kmForLevel(11) - VehicleLevelSystem.kmForLevel(10)
        XCTAssertEqual(step, 1_000)
    }

    /// «38 420 км ⇒ LVL 28» — the worked example from the spec, and the value
    /// the Figma frame shows on the Honda.
    func testSpecWorkedExample() {
        XCTAssertEqual(VehicleLevelSystem.level(for: 38_420), 28)
    }

    /// The odometer in the user's own build: 295 km is still level 2, because
    /// level 3 costs 300. Fails if the curve is shifted by one step.
    func testShortOdometerStaysOnItsStep() {
        XCTAssertEqual(VehicleLevelSystem.level(for: 295), 2)
        XCTAssertEqual(VehicleLevelSystem.level(for: 300), 3)
    }

    // MARK: - No ceiling

    /// The old system stopped at 10 and a car that reached it could never earn
    /// anything again. Fails the moment a cap is reintroduced.
    func testThereIsNoMaximumLevel() {
        XCTAssertEqual(VehicleLevelSystem.level(for: 50 * 200 * 199), 200)
        XCTAssertGreaterThan(VehicleLevelSystem.kmToNextLevel(km: 50 * 200 * 199, level: 200), 0)
        XCTAssertLessThan(VehicleLevelSystem.progressToNext(km: 50 * 200 * 199, level: 200), 1)
    }

    // MARK: - Round trips

    /// Every level's own threshold must resolve back to that level, and one
    /// metre short of it to the level below. This is the property that a
    /// closed-form inverse can break in floating point.
    func testThresholdsRoundTripExactly() {
        for level in 1...120 {
            let km = VehicleLevelSystem.kmForLevel(level)
            XCTAssertEqual(VehicleLevelSystem.level(for: km), level,
                           "threshold of level \(level) (\(km) km) did not resolve to \(level)")
            if level > 1 {
                XCTAssertEqual(VehicleLevelSystem.level(for: km - 0.001), level - 1,
                               "just below level \(level) should still be \(level - 1)")
            }
        }
    }

    /// Progress is 0 at the start of a step and approaches 1 at its end.
    func testProgressSpansTheStep() {
        let start = VehicleLevelSystem.kmForLevel(5)
        let end = VehicleLevelSystem.kmForLevel(6)
        XCTAssertEqual(VehicleLevelSystem.progressToNext(km: start, level: 5), 0, accuracy: 0.0001)
        XCTAssertEqual(VehicleLevelSystem.progressToNext(km: (start + end) / 2, level: 5),
                       0.5, accuracy: 0.0001)
        XCTAssertEqual(VehicleLevelSystem.progressToNext(km: end, level: 5), 1, accuracy: 0.0001)
    }

    /// A brand-new vehicle: zero km, level 1, nothing negative anywhere.
    func testZeroOdometer() {
        XCTAssertEqual(VehicleLevelSystem.level(for: 0), 1)
        XCTAssertEqual(VehicleLevelSystem.progressToNext(km: 0, level: 1), 0)
        XCTAssertEqual(VehicleLevelSystem.kmToNextLevel(km: 0, level: 1), 100)
    }

    // MARK: - Decade colours

    /// The colour changes on the decade boundary and nowhere else, and holds
    /// from 100 up — the spec's «дальше не меняется».
    func testColourChangesOnlyEveryTenLevels() {
        for decade in 0..<10 {
            let first = max(1, decade * 10)
            let last = decade * 10 + 9
            XCTAssertEqual(VehicleLevelSystem.color(for: first),
                           VehicleLevelSystem.color(for: last),
                           "levels \(first) and \(last) share a decade and must share a colour")
        }
        XCTAssertNotEqual(VehicleLevelSystem.color(for: 9), VehicleLevelSystem.color(for: 10))
        XCTAssertNotEqual(VehicleLevelSystem.color(for: 19), VehicleLevelSystem.color(for: 20))
        XCTAssertEqual(VehicleLevelSystem.color(for: 100), VehicleLevelSystem.color(for: 4_000))
    }

    /// 20–29 is the brand orange — the one decade the spec names outright.
    func testMiddleDecadeIsBrandOrange() {
        XCTAssertEqual(VehicleLevelSystem.color(for: 28), AppTheme.accent)
    }
}
