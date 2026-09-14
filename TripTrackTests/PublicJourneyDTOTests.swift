import XCTest
@testable import TripTrack

/// Decoding coverage for the public-journey DTOs added in 0.6.8
/// (`TripTrack/Models/Social/SocialDTOs.swift`): `SocialFeedTrip.journey`
/// and `PublicJourneysResponse`.
final class PublicJourneyDTOTests: XCTestCase {

    /// Mirrors `APIClient`'s private decoder (see `CompanionsDTOTests`):
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

    func testFeedTripDecodesJourneyAndSurvivesItsAbsence() throws {
        let with = Data(#"{"id":"11111111-1111-4111-8111-111111111111","author":{"id":"22222222-2222-4222-8222-222222222222","displayName":"A","avatarEmoji":null,"profileLevel":1},"title":null,"description":null,"startDate":"2026-09-13T10:00:00.000Z","endDate":null,"distance":1000,"duration":60,"maxSpeed":null,"elevation":null,"maxAltitude":null,"drivingTime":null,"stoppedTime":null,"region":null,"isPrivate":false,"previewPolyline":null,"photoCount":0,"firstPhotoThumbnail":null,"vehicle":null,"reactionCount":0,"reactionBreakdown":[],"myReaction":null,"badgeIds":[],"commentCount":0,"journey":{"id":"33333333-3333-4333-8333-333333333333","title":"Грузия","startDate":"2026-09-12T00:00:00.000Z","endDate":null}}"#.utf8)
        let t = try decoder.decode(SocialFeedTrip.self, from: with)
        XCTAssertEqual(t.journey?.title, "Грузия")
        XCTAssertNil(t.journey?.endDate)
        let without = try decoder.decode(SocialFeedTrip.self, from: Data(String(decoding: with, as: UTF8.self).replacingOccurrences(of: ",\"journey\":{\"id\":\"33333333-3333-4333-8333-333333333333\",\"title\":\"Грузия\",\"startDate\":\"2026-09-12T00:00:00.000Z\",\"endDate\":null}", with: "").utf8))
        XCTAssertNil(without.journey)
    }

    func testPublicJourneysResponseDecodes() throws {
        let json = Data(#"{"journeys":[{"id":"33333333-3333-4333-8333-333333333333","title":null,"startDate":"2026-09-12T00:00:00.000Z","endDate":"2026-09-17T00:00:00.000Z","coverPhotoId":null,"legCount":1,"legs":[{"id":"11111111-1111-4111-8111-111111111111","startDate":"2026-09-13T10:00:00.000Z","endDate":"2026-09-13T12:00:00.000Z","distance":480000,"duration":7200,"region":"Краснодарский край","previewPolyline":null}]}],"nextCursor":null}"#.utf8)
        let r = try decoder.decode(PublicJourneysResponse.self, from: json)
        XCTAssertEqual(r.journeys.first?.legs.first?.distance, 480_000)
        XCTAssertNil(r.nextCursor)
    }
}
