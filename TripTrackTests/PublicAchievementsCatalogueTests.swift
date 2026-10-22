import XCTest
@testable import TripTrack

/// Somebody else's achievements (0.9.1): the «Достижения» screen built from
/// the ids `/users/:id/badges` sends instead of a walk over your own trips.
/// The counts must be the ones your own screen would print for the same set.
final class PublicAchievementsCatalogueTests: XCTestCase {
    func testCountsTheIdsWithTheSameDenominatorAsYourOwnScreen() throws {
        let secret = try XCTUnwrap(Badge.all.first { $0.isHidden })
        let plain = try XCTUnwrap(Badge.all.first { !$0.isHidden })

        let catalogue = AchievementsCatalogue.build(
            unlockedIds: [plain.id, secret.id, "badge_from_a_newer_build"])

        // An id this build doesn't know drops out rather than drawing blank.
        XCTAssertEqual(catalogue.unlockedIds, [plain.id, secret.id])
        XCTAssertEqual(catalogue.unlockedCount, 2)
        // A hidden badge joins the denominator only once earned.
        XCTAssertEqual(catalogue.totalCount, Badge.all.filter { !$0.isHidden }.count + 1)
    }

    func testAnEarnedSecretIsATileAndTheRestStaySecret() throws {
        let secrets = Badge.all.filter(\.isHidden)
        let earned = try XCTUnwrap(secrets.first)
        let other = try XCTUnwrap(secrets.dropFirst().first)

        let catalogue = AchievementsCatalogue.build(unlockedIds: [earned.id])

        guard case .unlocked = catalogue.state(for: earned) else {
            return XCTFail("an earned secret must read as earned")
        }
        guard case .secret = catalogue.state(for: other) else {
            return XCTFail("an unearned secret must stay a secret")
        }
    }

    func testTheRarestLeadTheGrid() {
        let unlocked = AchievementsCatalogue
            .build(unlockedIds: Badge.all.map(\.id))
            .badges(for: .unlocked)

        XCTAssertEqual(unlocked.count, Badge.all.count)
        XCTAssertEqual(unlocked.map(\.displayRarity), unlocked.map(\.displayRarity).sorted(by: >))
    }

    func testAnEmptyCollectionStillCountsTheCatalogue() {
        let catalogue = AchievementsCatalogue.build(unlockedIds: [])

        XCTAssertEqual(catalogue.unlockedCount, 0)
        XCTAssertEqual(catalogue.totalCount, Badge.all.filter { !$0.isHidden }.count)
        XCTAssertTrue(catalogue.badges(for: .unlocked).isEmpty)
    }

    func testEndpointAndResponse() throws {
        XCTAssertEqual(APIEndpoint.userBadges("AC2DE883"), "/users/AC2DE883/badges")

        let json = Data(#"{"badges":["first_trip","iron_butt"]}"#.utf8)
        let response = try JSONDecoder().decode(SocialBadgesResponse.self, from: json)

        XCTAssertEqual(response.badges, ["first_trip", "iron_butt"])
    }
}
