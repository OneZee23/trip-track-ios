import XCTest
@testable import TripTrack

/// `looksLikeDefaultCheckpointName` used to be a broken inline regex in
/// `TripManager.applyPlaceName`: `"^\\(word) \\d+$"` is TWO backslashes,
/// i.e. the literal text `\(word)` inside the pattern, not Swift string
/// interpolation (which needs one). The regex looked for the literal
/// substring "(word) 7" and essentially never matched a real default
/// checkpoint name, so the geocoder lost its right to rename one.
final class CheckpointDefaultNameTests: XCTestCase {
    func testRussianDefaultNameMatches() {
        XCTAssertTrue(CheckpointDefaultName.looksLikeDefaultCheckpointName("Отметка 7"))
    }

    func testEnglishDefaultNameMatches() {
        XCTAssertTrue(CheckpointDefaultName.looksLikeDefaultCheckpointName("Checkpoint 12"))
    }

    func testAHumanGivenNameDoesNotMatch() {
        XCTAssertFalse(CheckpointDefaultName.looksLikeDefaultCheckpointName("Отметка у моря"))
    }

    func testEmptyNameCountsAsDefault() {
        XCTAssertTrue(CheckpointDefaultName.looksLikeDefaultCheckpointName(""))
    }

    func testBareNumberDoesNotMatch() {
        XCTAssertFalse(CheckpointDefaultName.looksLikeDefaultCheckpointName("7"))
    }

    /// Trailing punctuation after the number must not still count as
    /// default — and it exercises the same escaped-word call path the
    /// metacharacter concern is about.
    func testTrailingPunctuationDoesNotMatch() {
        XCTAssertFalse(CheckpointDefaultName.looksLikeDefaultCheckpointName("Отметка 7."))
    }
}
