import XCTest
@testable import TripTrack

/// Coverage for `ConsumptionUnit`, the litres-per-100 ↔ mpg switch.
///
/// These tests exist because this screen already shipped the bug once: an
/// earlier pass labelled the stored per-100 numbers "mpg" without converting
/// them, which inverts the meaning — the scale runs the other way. Anything
/// that reintroduces a relabel-instead-of-convert should fail here.
final class ConsumptionUnitTests: XCTestCase {

    // MARK: - The two directions

    /// The reference figure: 9.4 L/100 km ≈ 25 mpg (US).
    func testConvertsToMpg() {
        XCTAssertEqual(ConsumptionUnit.mpg.display(fromPer100: 9.4), 25.02, accuracy: 0.05)
        XCTAssertEqual(ConsumptionUnit.mpg.display(fromPer100: 5.6), 42.0, accuracy: 0.05)
    }

    func testConvertsBackFromMpg() {
        XCTAssertEqual(ConsumptionUnit.mpg.toPer100(25), 9.41, accuracy: 0.01)
        XCTAssertEqual(ConsumptionUnit.mpg.toPer100(42), 5.6, accuracy: 0.01)
    }

    /// Per-100 is the storage unit, so it passes straight through in both
    /// directions. Fails if someone ever "helpfully" converts it too.
    func testPer100IsIdentity() {
        XCTAssertEqual(ConsumptionUnit.per100.display(fromPer100: 9.1), 9.1)
        XCTAssertEqual(ConsumptionUnit.per100.toPer100(9.1), 9.1)
    }

    /// Typing a figure, switching units and switching back must return the
    /// same car — this is exactly what the segment does on every tap.
    func testRoundTripSurvivesTheSwitch() {
        for stored in [4.2, 6.0, 7.8, 9.1, 14.5, 22.0] {
            let shown = ConsumptionUnit.mpg.display(fromPer100: stored)
            let back = ConsumptionUnit.mpg.toPer100(shown)
            XCTAssertEqual(back, stored, accuracy: 0.0001,
                           "\(stored) L/100km did not survive a round trip through mpg")
        }
    }

    // MARK: - The inversion itself

    /// The whole reason this type exists: more litres is worse, more miles per
    /// gallon is better. A relabel would preserve the order and lie.
    func testTheScaleIsInverted() {
        let thirsty = ConsumptionUnit.mpg.display(fromPer100: 15)
        let frugal = ConsumptionUnit.mpg.display(fromPer100: 5)
        XCTAssertLessThan(thirsty, frugal, "the thirstier car must show FEWER mpg")
    }

    // MARK: - Degenerate input

    /// A vehicle with no consumption set yet. Dividing by it would give
    /// infinity, which formats as "inf" in a text field.
    func testZeroStaysZero() {
        XCTAssertEqual(ConsumptionUnit.mpg.display(fromPer100: 0), 0)
        XCTAssertEqual(ConsumptionUnit.mpg.toPer100(0), 0)
        XCTAssertFalse(ConsumptionUnit.mpg.display(fromPer100: 0).isInfinite)
    }

    // MARK: - Labels

    func testSegmentLabels() {
        XCTAssertEqual(ConsumptionUnit.mpg.segmentLabel(.ru), "mpg")
        XCTAssertEqual(ConsumptionUnit.mpg.segmentLabel(.en), "mpg")
        XCTAssertEqual(ConsumptionUnit.per100.segmentLabel(.ru), "л/100")
    }

    /// The per-100 label still defers to the volume/distance settings; only
    /// mpg is a fixed word.
    func testValueUnitFollowsTheOtherSettings() {
        XCTAssertEqual(
            ConsumptionUnit.per100.valueUnit(volumeRaw: "liters", distanceRaw: "km", isRu: true),
            "л/100км")
        XCTAssertEqual(
            ConsumptionUnit.mpg.valueUnit(volumeRaw: "liters", distanceRaw: "km", isRu: true),
            "mpg")
    }

    // MARK: - Fuel price

    /// Picking mpg picks gallons. Miles per gallon alongside roubles per litre
    /// is not a set of units anyone uses.
    func testMpgImpliesGallons() {
        XCTAssertEqual(ConsumptionUnit.mpg.volumeUnit, .gallons)
        XCTAssertEqual(ConsumptionUnit.per100.volumeUnit, .liters)
    }

    /// The price is STORED per litre — that is what trip cost multiplies
    /// litres by. Switching to gallons used to only change the label, so
    /// «65 ₽/л» became «65 ₽/gal» while every trip stayed litre-priced.
    func testPriceConvertsToGallons() {
        XCTAssertEqual(ConsumptionUnit.mpg.displayPrice(fromPerLitre: 65), 246.05, accuracy: 0.01)
        XCTAssertEqual(ConsumptionUnit.per100.displayPrice(fromPerLitre: 65), 65)
    }

    func testPriceRoundTrips() {
        for perLitre in [42.0, 56.0, 65.0, 98.5] {
            let shown = ConsumptionUnit.mpg.displayPrice(fromPerLitre: perLitre)
            XCTAssertEqual(ConsumptionUnit.mpg.priceToPerLitre(shown), perLitre, accuracy: 0.0001)
        }
    }

    /// Price and consumption move in OPPOSITE directions across the same
    /// switch: a gallon costs more than a litre, and a car goes further on a
    /// gallon than 100 km costs it in litres. Fails if someone reuses one
    /// conversion for both.
    func testPriceAndConsumptionAreNotTheSameConversion() {
        XCTAssertGreaterThan(ConsumptionUnit.mpg.displayPrice(fromPerLitre: 65), 65)
        XCTAssertGreaterThan(ConsumptionUnit.mpg.display(fromPer100: 9.4), 9.4)
        // …but not by the same factor, and not by each other's factor.
        XCTAssertNotEqual(
            ConsumptionUnit.mpg.displayPrice(fromPerLitre: 9.4),
            ConsumptionUnit.mpg.display(fromPer100: 9.4),
            accuracy: 0.001)
    }

    func testUnknownStoredValueFallsBackToPer100() {
        UserDefaults.standard.set("furlongs", forKey: ConsumptionUnit.storageKey)
        XCTAssertEqual(ConsumptionUnit.current, .per100)
        UserDefaults.standard.removeObject(forKey: ConsumptionUnit.storageKey)
        XCTAssertEqual(ConsumptionUnit.current, .per100)
    }
}
