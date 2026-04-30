import XCTest
@testable import TripTrack

/// `RandomDisplayName.isPlaceholder` is the gate the UI uses to decide
/// whether to nudge the user with "tap to change" — false negatives
/// stick a user with a generated name forever, false positives nag
/// users who actually want their handle.
final class RandomDisplayNameTests: XCTestCase {

    // MARK: - isPlaceholder positive cases

    func testRecognizesGeneratedRussianName() {
        XCTAssertTrue(RandomDisplayName.isPlaceholder("Дерзкий Гонщик 472"))
    }

    func testRecognizesGeneratedEnglishName() {
        XCTAssertTrue(RandomDisplayName.isPlaceholder("Swift Driver 42"))
    }

    func testRecognizesAllGeneratedShape() {
        // Every name produced by generate() must round-trip through isPlaceholder.
        // Sample 20 generated names per locale to exercise the random pool.
        for _ in 0..<20 {
            let ru = RandomDisplayName.generate(language: .ru)
            XCTAssertTrue(RandomDisplayName.isPlaceholder(ru), "Failed to recognize generated name: \(ru)")
            let en = RandomDisplayName.generate(language: .en)
            XCTAssertTrue(RandomDisplayName.isPlaceholder(en), "Failed to recognize generated name: \(en)")
        }
    }

    // MARK: - isPlaceholder negative cases

    func testRealNameIsNotPlaceholder() {
        XCTAssertFalse(RandomDisplayName.isPlaceholder("Иван Петров"))
    }

    func testNilIsNotPlaceholder() {
        XCTAssertFalse(RandomDisplayName.isPlaceholder(nil))
    }

    func testEmptyStringIsNotPlaceholder() {
        XCTAssertFalse(RandomDisplayName.isPlaceholder(""))
    }

    func testNonNumericThirdTokenIsNotPlaceholder() {
        // Third token isn't an integer — fail fast.
        XCTAssertFalse(RandomDisplayName.isPlaceholder("Дерзкий Гонщик abc"))
    }

    func testTwoTokenNameIsNotPlaceholder() {
        XCTAssertFalse(RandomDisplayName.isPlaceholder("Дерзкий Гонщик"))
    }

    func testFourTokenNameIsNotPlaceholder() {
        XCTAssertFalse(RandomDisplayName.isPlaceholder("Дерзкий Гонщик 472 extra"))
    }

    func testUnknownAdjectiveIsNotPlaceholder() {
        // Three tokens, ends with a number, but adjective isn't in our pool.
        XCTAssertFalse(RandomDisplayName.isPlaceholder("Случайный Гонщик 472"))
    }
}
