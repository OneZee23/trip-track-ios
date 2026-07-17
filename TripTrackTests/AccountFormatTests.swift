import XCTest
@testable import TripTrack

/// `AccountFormat.maskedEmail` — the F11 «a•••@icloud.com» masking helper on
/// the account card. Pure function; degenerate inputs must return safely and
/// must never echo the full local part back.
final class AccountFormatTests: XCTestCase {

    func testNormalEmail() {
        XCTAssertEqual(AccountFormat.maskedEmail("alex@icloud.com"), "a•••@icloud.com")
    }

    func testSingleCharLocalPart() {
        XCTAssertEqual(AccountFormat.maskedEmail("a@icloud.com"), "a•••@icloud.com")
    }

    func testUnicodeLocalPart() {
        XCTAssertEqual(AccountFormat.maskedEmail("юзер@почта.рф"), "ю•••@почта.рф")
    }

    func testNoAtSignInput() {
        // Not an email shape — masked anyway, never echoed back raw.
        XCTAssertEqual(AccountFormat.maskedEmail("not-an-email"), "n•••")
    }

    func testEmptyInput() {
        XCTAssertEqual(AccountFormat.maskedEmail(""), "")
    }

    func testWhitespaceOnlyInput() {
        XCTAssertEqual(AccountFormat.maskedEmail("   "), "")
    }

    func testAtFirstCharacter() {
        // "@domain" — no local part to take a first character from.
        XCTAssertEqual(AccountFormat.maskedEmail("@icloud.com"), "•••@icloud.com")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(AccountFormat.maskedEmail("  alex@icloud.com  "), "a•••@icloud.com")
    }

    func testLongLocalPartKeepsOnlyFirstCharacter() {
        let masked = AccountFormat.maskedEmail("very.long.local.part@example.org")
        XCTAssertEqual(masked, "v•••@example.org")
        XCTAssertFalse(masked.contains("long"))
    }
}
