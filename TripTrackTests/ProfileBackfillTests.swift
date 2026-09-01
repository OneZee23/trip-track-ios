import XCTest
@testable import TripTrack

/// Two things the August «Пользователь» incident taught us about the profile
/// push, both of which the first fix got wrong.
///
/// 1. The launch backfill must send the NAME and nothing else. The rest of
///    `syncProfileToServer`'s payload is a mirror of THIS device, and nothing
///    re-reads it from the server after login — so a second phone on the same
///    Apple ID, opened for the first time after an update, would push its
///    stale mirror over whatever the primary phone had set.
/// 2. A name that the server cannot accept must never reach it. The server
///    caps `displayName` at 30 characters and Apple hands us `fullName`
///    unfiltered; with a launch retry in place, an over-long name turns into a
///    request that is refused on every single cold start, forever.
final class ProfileBackfillTests: XCTestCase {

    // MARK: - The backfill payload carries the name alone

    private func encodedKeys(_ req: ProfileUpdateRequest) throws -> Set<String> {
        let data = try JSONEncoder().encode(req)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    func testNameOnlyPayloadCarriesNothingButTheName() throws {
        let req = ProfileUpdateRequest.nameOnly("Клаус")

        XCTAssertEqual(try encodedKeys(req), ["displayName"],
                       "every other field is a mirror of this device and would clobber the server")
    }

    func testNameOnlyPayloadKeepsTheNameItWasGiven() throws {
        let req = ProfileUpdateRequest.nameOnly("Клаус")
        let data = try JSONEncoder().encode(req)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["displayName"] as? String, "Клаус")
    }

    /// The regression guard with teeth: the full sync payload is exactly what
    /// the backfill must NOT resemble.
    func testTheFullProfilePayloadCarriesTheDeviceMirrorAndSoIsWrongForBackfill() throws {
        let full = ProfileUpdateRequest(
            displayName: "Клаус", avatarEmoji: "😎", profileBackground: "",
            profileLevel: 1, profileXp: 0, currentStreak: 0, bestStreak: 0,
            activeVehicleId: nil, language: "de", showOnPublicMap: false)

        let keys = try encodedKeys(full)
        XCTAssertTrue(keys.contains("showOnPublicMap"))
        XCTAssertTrue(keys.contains("profileLevel"))
        XCTAssertGreaterThan(keys.count, 1)
    }

    // MARK: - A name the server would refuse never gets sent

    func testClampsAnAppleNameLongerThanTheServerCap() {
        let long = "Александра Константиновна Раевская"  // 33 characters
        XCTAssertGreaterThan(long.count, ContentFilter.Field.displayName.maxLength)

        let clamped = ContentFilter.clampedDisplayName(long)

        XCTAssertEqual(clamped.count, ContentFilter.Field.displayName.maxLength,
                       "an over-long name is refused by the server on every retry, forever")
    }

    func testLeavesAnOrdinaryNameAlone() {
        XCTAssertEqual(ContentFilter.clampedDisplayName("Клаус Фишер"), "Клаус Фишер")
    }

    func testStripsTheInvisibleCharactersBeforeMeasuring() {
        // A name padded with zero-width joiners is under the cap once cleaned;
        // measuring first would clamp a perfectly legal name.
        let padded = "Клаус\u{200B}\u{200B}\u{200B} Фишер"

        XCTAssertEqual(ContentFilter.clampedDisplayName(padded), "Клаус Фишер")
    }

    func testClampingNeverSplitsAGrapheme() {
        // Family emoji are single graphemes made of many scalars — a naive
        // prefix on scalars would emit half a person.
        let name = String(repeating: "👨‍👩‍👧‍👦", count: 40)

        let clamped = ContentFilter.clampedDisplayName(name)

        XCTAssertLessThanOrEqual(clamped.count, ContentFilter.Field.displayName.maxLength)
        XCTAssertFalse(clamped.unicodeScalars.contains { $0 == "\u{200D}" && clamped.hasSuffix("\u{200D}") },
                       "must not end mid-grapheme on a zero-width joiner")
    }

    func testAnEmptyNameStaysEmptySoCallersCanRejectIt() {
        XCTAssertTrue(ContentFilter.clampedDisplayName("   ").isEmpty)
    }
}
