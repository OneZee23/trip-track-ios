import XCTest
@testable import TripTrack

/// Display-name validator and sanitizer. Covers homoglyph attacks, repeat
/// runs, punctuation floods, profanity, and invisible Unicode stripping.
final class ContentFilterTests: XCTestCase {

    // MARK: - sanitize

    func testSanitizeStripsZeroWidthSpace() {
        // U+200B between letters — visually invisible, lets two users mint
        // identical-looking display names.
        let input = "Иван\u{200B}\u{200B}"
        XCTAssertEqual(ContentFilter.sanitize(input), "Иван")
    }

    func testSanitizeStripsBidiOverride() {
        let input = "Анна\u{202E}хак"
        XCTAssertEqual(ContentFilter.sanitize(input), "Аннахак")
    }

    func testSanitizeStripsBOM() {
        XCTAssertEqual(ContentFilter.sanitize("\u{FEFF}Anya"), "Anya")
    }

    func testSanitizeCollapsesNBSPAndTrims() {
        // U+00A0 NBSP between words + trailing regular spaces.
        let input = "  Anya\u{00A0}\u{00A0}Smith   "
        XCTAssertEqual(ContentFilter.sanitize(input), "Anya Smith")
    }

    func testSanitizeCollapsesInternalWhitespace() {
        XCTAssertEqual(ContentFilter.sanitize("Anya    Smith"), "Anya Smith")
    }

    func testSanitizeKeepsEmoji() {
        // Emoji aren't in the strip set — they're visible glyphs the user
        // typed on purpose. (Server may still reject, but sanitize() leaves them.)
        let result = ContentFilter.sanitize("Иван 🚗")
        XCTAssertEqual(result, "Иван 🚗")
    }

    // MARK: - validate(.displayName) — passing cases

    func testValidatePassesCyrillicName() {
        XCTAssertNil(ContentFilter.validate("Иван", field: .displayName, language: .ru))
    }

    func testValidatePassesLatinFullName() {
        XCTAssertNil(ContentFilter.validate("Anya Smith", field: .displayName, language: .en))
    }

    func testValidatePassesHyphenSeparatedMixedScript() {
        // Latin + Cyrillic in SEPARATE tokens (split by hyphen) is OK —
        // only same-token mixing is the impersonation vector.
        XCTAssertNil(ContentFilter.validate("Иван-Smith", field: .displayName, language: .en))
    }

    func testValidatePassesEmpty() {
        // Empty input is valid (means user cleared the field).
        XCTAssertNil(ContentFilter.validate("", field: .displayName, language: .en))
    }

    // MARK: - validate(.displayName) — failing cases

    func testValidateRejectsHomoglyphMixedScriptInSameToken() {
        // Cyrillic 'Т' (U+0422) + Latin 'witter' — classic Twitter impersonation.
        let err = ContentFilter.validate("Тwitter", field: .displayName, language: .en)
        XCTAssertNotNil(err, "Expected mixed-script error for Тwitter")
    }

    func testValidateRejectsRepeatedRun() {
        // 5 identical chars in a row (`aaaaa`) should trip the spam guard.
        let err = ContentFilter.validate("aaaaa", field: .displayName, language: .en)
        XCTAssertNotNil(err)
    }

    func testValidateRejectsPunctuationFlood() {
        // `....!` is 5 non-letter chars; threshold is 4. Letter prefix avoids
        // the no-letter rejection so we test punctuation rule in isolation.
        let err = ContentFilter.validate("a....!", field: .displayName, language: .en)
        XCTAssertNotNil(err)
    }

    func testValidateRejectsDigitsOnly() {
        let err = ContentFilter.validate("123", field: .displayName, language: .en)
        XCTAssertNotNil(err)
    }

    func testValidateRejectsTooLong() {
        // displayName max is 30. 31 'a's would also trip the repeat-run guard,
        // so use a varied 31-char string.
        let long = String(repeating: "ab", count: 16) // 32 chars
        let err = ContentFilter.validate(long, field: .displayName, language: .en)
        XCTAssertNotNil(err)
    }

    // MARK: - profanity

    func testValidateRejectsEnglishSlur() {
        let err = ContentFilter.validate("retard", field: .displayName, language: .en)
        XCTAssertNotNil(err)
    }

    func testValidateRejectsRussianSlur() {
        let err = ContentFilter.validate("педик", field: .displayName, language: .ru)
        XCTAssertNotNil(err)
    }

    func testContainsObjectionableCaseInsensitive() {
        XCTAssertTrue(ContentFilter.containsObjectionable("RETARD"))
        XCTAssertTrue(ContentFilter.containsObjectionable("Педик"))
    }

    func testContainsObjectionableNoFalsePositiveOnInnocentText() {
        XCTAssertFalse(ContentFilter.containsObjectionable("Hello world"))
        XCTAssertFalse(ContentFilter.containsObjectionable("Поездка на дачу"))
    }
}
