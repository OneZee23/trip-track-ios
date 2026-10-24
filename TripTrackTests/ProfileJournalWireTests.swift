import XCTest
@testable import TripTrack

final class ProfileJournalWireTests: XCTestCase {
    private let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private func decodeMe(_ json: String) throws -> MeResponse {
        try JSONDecoder().decode(MeResponse.self, from: Data(json.utf8))
    }

    func testMeWithoutJournalKeysMeansNotSaid() throws {
        let me = try decodeMe(#"{"isPublic":true}"#)
        XCTAssertNil(me.bio)
        XCTAssertFalse(me.bioProvided)
        XCTAssertNil(me.photos)
        XCTAssertNil(me.pinnedTripIds)
    }

    func testMeJournalAndNullBio() throws {
        let json = """
        {"isPublic":true,"bio":"Дороги","photos":[{"id":"\(id)","thumbnailUrl":"https://example.invalid/a.jpg"}],"pinnedTripIds":["\(id)"]}
        """
        let me = try decodeMe(json)
        XCTAssertEqual(me.bio, "Дороги")
        XCTAssertEqual(me.photos?.first?.id, id)
        XCTAssertNil(me.photos?.first?.sortOrder)
        XCTAssertEqual(me.pinnedTripIds, [id])
        let cleared = try decodeMe(#"{"isPublic":true,"bio":null,"photos":[],"pinnedTripIds":[]}"#)
        XCTAssertTrue(cleared.bioProvided)
        XCTAssertNil(cleared.bio)
        XCTAssertEqual(cleared.photos, [])
        XCTAssertEqual(cleared.pinnedTripIds, [])
    }

    func testMalformedOptionalMeFieldsDoNotBreakAccount() throws {
        let me = try decodeMe(#"{"isPublic":true,"photos":"future","pinnedTripIds":["invalid"],"bio":4}"#)
        XCTAssertTrue(me.isPublic)
        XCTAssertFalse(me.bioProvided)
        XCTAssertNil(me.photos)
        XCTAssertNil(me.pinnedTripIds)
    }

    private func profile(_ fields: String = "") throws -> SocialProfile {
        let json = """
        {"id":"\(id)","profileLevel":1,"currentStreak":0,"bestStreak":0,
         "stats":{"totalKm":100,"tripCount":1,"regionsCount":1,"publicTripCount":1},
         "recentBadges":[],"recentTrips":[],"followerCount":0,"followingCount":0\(fields)}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SocialProfile.self, from: Data(json.utf8))
    }

    func testPublicProfileWithoutJournalKeys() throws {
        let p = try profile()
        XCTAssertNil(p.photos)
        XCTAssertNil(p.pinnedTrips)
    }

    func testPublicProfileWithPhotosAndPinnedTrip() throws {
        let fields = """
        ,"photos":[{"id":"\(id)","thumbnailUrl":"https://example.invalid/a.jpg","originalUrl":null,"takenAt":null}],
        "pinnedTrips":[{"id":"\(id)","startDate":"2026-10-20T09:00:00Z","distance":1000}]
        """
        let p = try profile(fields)
        XCTAssertEqual(p.photos?.first?.id, id)
        XCTAssertEqual(p.pinnedTrips?.first?.id, id)
        XCTAssertEqual(p.pinnedTrips?.first?.distance, 1000)
        let malformed = try profile(#","photos":false,"pinnedTrips":"future""#)
        XCTAssertNil(malformed.photos)
        XCTAssertNil(malformed.pinnedTrips)
    }

    func testProfileUpdateOmitsNilAndEncodesExplicitClears() throws {
        var request = ProfileUpdateRequest(
            displayName: nil, avatarEmoji: nil, profileBackground: nil,
            profileLevel: nil, profileXp: nil, currentStreak: nil, bestStreak: nil,
            activeVehicleId: nil, language: nil, showOnPublicMap: nil)
        func object() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        }
        XCTAssertNil(try object()["bio"])
        XCTAssertNil(try object()["pinnedTripIds"])
        request.bio = ""
        request.pinnedTripIds = []
        XCTAssertEqual(try object()["bio"] as? String, "")
        XCTAssertEqual(try object()["pinnedTripIds"] as? [String], [])
        request.bio = "Roads"
        request.pinnedTripIds = [id.uuidString.lowercased()]
        XCTAssertEqual(try object()["bio"] as? String, "Roads")
        XCTAssertEqual(try object()["pinnedTripIds"] as? [String], [id.uuidString.lowercased()])
    }
}
