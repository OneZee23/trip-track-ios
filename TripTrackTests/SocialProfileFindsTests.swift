import XCTest
@testable import TripTrack

/// «Находки» на публичном профиле (0.7.0, спека §4, wave 4 task 4):
/// `SocialProfile.finds` / `SocialFind` in `TripTrack/Models/Social/SocialDTOs.swift`.
final class SocialProfileFindsTests: XCTestCase {

    /// Mirrors `APIClient`'s private decoder (see `PublicJourneyDTOTests`):
    /// the server sends dates as ISO-8601 strings with millisecond
    /// fractions, which the built-in `.iso8601` strategy does not parse —
    /// only the app's own `ISODate.parse` does.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = ISODate.parse(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "invalid ISO8601: \(s)")
            }
            return date
        }
        return d
    }()

    private func profileJSON(finds: String?) -> Data {
        let findsField = finds.map { #","finds":\#($0)"# } ?? ""
        let json = """
        {"id":"11111111-1111-4111-8111-111111111111","displayName":"A","avatarEmoji":null,\
        "profileLevel":1,"profileBackground":null,"currentStreak":0,"bestStreak":0,\
        "stats":{"totalKm":100,"tripCount":5,"regionsCount":1,"publicTripCount":5},\
        "activeVehicle":null,"recentBadges":[],"recentTrips":[],"followerCount":0,\
        "followingCount":0,"isFollowing":null,"bio":null,"visibility":null\(findsField)}
        """
        return Data(json.utf8)
    }

    // MARK: - Decoding

    /// A server that doesn't know about finds yet omits the key entirely —
    /// the whole profile must still decode, with `finds == nil` (not an
    /// empty array standing in for "server doesn't send this").
    func testProfileDecodesWithoutFindsKey() throws {
        let p = try decoder.decode(SocialProfile.self, from: profileJSON(finds: nil))
        XCTAssertNil(p.finds)
    }

    /// An empty array is a real answer ("nothing verified yet"), distinct
    /// from the key being absent.
    func testProfileDecodesWithEmptyFindsArray() throws {
        let p = try decoder.decode(SocialProfile.self, from: profileJSON(finds: "[]"))
        XCTAssertEqual(p.finds, [])
    }

    func testProfileDecodesFindsList() throws {
        let findsJSON = """
        [{"secretId":"s1","kind":"secret","symbol":"mountain.2","rarity":"few",\
        "foundAt":"2026-09-12T00:00:00.000Z","first":true},\
        {"secretId":"s2","kind":"riddle","symbol":"light.beacon.max","rarity":"many",\
        "foundAt":"2026-09-13T10:00:00.000Z","first":false}]
        """
        let p = try decoder.decode(SocialProfile.self, from: profileJSON(finds: findsJSON))
        XCTAssertEqual(p.finds?.count, 2)
        XCTAssertEqual(p.finds?.first?.secretId, "s1")
        XCTAssertEqual(p.finds?.first?.kind, "secret")
        XCTAssertEqual(p.finds?.first?.rarity, "few")
        XCTAssertEqual(p.finds?.first?.first, true)
        XCTAssertEqual(p.finds?.last?.first, false)
    }

    // MARK: - Unknown kind/symbol fallback

    /// A `kind`/`symbol` this build doesn't recognise (server learned a new
    /// one first) must not crash the decode or the painter lookup — it falls
    /// back to the most common seal rather than disappearing.
    func testUnknownKindAndSymbolFallBackWithoutCrashing() {
        let find = SocialFind(
            secretId: "s9", kind: "future_kind", symbol: "future.symbol",
            rarity: "future_rarity", foundAt: Date(), first: false)
        XCTAssertEqual(find.discoveryKind, .secret)
        XCTAssertEqual(find.sealSymbol, .generic)
        // Painting it must not trap — the whole point of the fallback.
        _ = SealPainter.image(kind: find.discoveryKind, symbol: find.sealSymbol, size: 26, scale: 2)
    }

    func testKnownKindAndSymbolResolve() {
        let find = SocialFind(
            secretId: "s1", kind: "riddle", symbol: "light.beacon.max",
            rarity: "tens", foundAt: Date(), first: false)
        XCTAssertEqual(find.discoveryKind, .riddle)
        XCTAssertEqual(find.sealSymbol, .lighthouse)
    }

    // MARK: - Visibility rule

    func testSectionHiddenWhenFindsIsNilOrEmpty() {
        XCTAssertFalse(socialFindsAreVisible(nil))
        XCTAssertFalse(socialFindsAreVisible([]))
    }

    func testSectionVisibleWhenFindsIsNonEmpty() {
        let find = SocialFind(
            secretId: "s1", kind: "secret", symbol: "mountain.2",
            rarity: "few", foundAt: Date(), first: true)
        XCTAssertTrue(socialFindsAreVisible([find]))
    }

    // MARK: - Rarity strings (LocalizationTests covers table parity)

    func testKnownRaritiesHaveLabels() {
        for raw in ["few", "tens", "hundreds", "many"] {
            XCTAssertNotNil(AppStrings.findRarityLabel(.en, raw: raw), raw)
            XCTAssertNotNil(AppStrings.findRarityLabel(.ru, raw: raw), raw)
        }
    }

    func testUnknownRarityHasNoLabel() {
        XCTAssertNil(AppStrings.findRarityLabel(.en, raw: "future_rarity"))
    }
}
