import XCTest
@testable import TripTrack

/// The car on a feed trip (0.9.0). The id is new on the wire: a server that
/// sends it makes the chip open the car's page; an older one sends only the
/// name and avatar, and the trip must decode exactly as before — a chip that
/// is a plain label, not a missing car or a dropped trip.
final class SocialFeedVehicleDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> SocialFeedVehicle {
        try JSONDecoder().decode(SocialFeedVehicle.self, from: Data(json.utf8))
    }

    func testOlderServerWithoutIdStillDecodes() throws {
        let v = try decode(#"{"name":"Peugeot","avatarEmoji":"pixel_car_orange"}"#)
        XCTAssertNil(v.id)
        XCTAssertEqual(v.name, "Peugeot")
    }

    func testIdAndSilhouetteArrive() throws {
        let v = try decode(#"{"id":"7A1D0E8E-1111-4222-8333-944455556666","name":"Peugeot","avatarEmoji":"pixel_car_orange","avatarStyle":"hatch"}"#)
        XCTAssertEqual(v.id, UUID(uuidString: "7A1D0E8E-1111-4222-8333-944455556666"))
        XCTAssertEqual(v.avatarStyle, "hatch")
    }

    func testLowercaseIdFromPostgresDecodes() throws {
        // Postgres sends uuids lower-case; Swift's UUID parses either.
        let v = try decode(#"{"id":"7a1d0e8e-1111-4222-8333-944455556666","name":"Peugeot","avatarEmoji":"🚗"}"#)
        XCTAssertEqual(v.id, UUID(uuidString: "7A1D0E8E-1111-4222-8333-944455556666"))
    }
}
