import XCTest
@testable import TripTrack

/// Coverage for `CompanionsStore.respond(tripId:notificationId:accept:)` —
/// Fix 4 (companions review, second wave): accepting an invite must
/// invalidate `myTrips` so «Со мной» shows the newly-accepted trip without
/// the user having to leave the profile tab and come back. Also exercises
/// Fix 1's `respondedInvitationIds` bookkeeping through the real network
/// path (complementing `CompanionsStorePersistenceTests`'s pure
/// UserDefaults-seeded proof of the same rule).
@MainActor
final class CompanionsStoreRespondTests: XCTestCase {
    private var session: URLSession!
    private var client: APIClient!
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(session: session, tokenStore: TokenStore.shared)
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        TokenStore.shared.clear()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        TokenStore.shared.clear()
        UserDefaults.standard.removeObject(forKey: "com.triptrack.companions.respondedTripIds")
        UserDefaults.standard.removeObject(forKey: "com.triptrack.companions.respondedInvitationIds")
        super.tearDown()
    }

    // MARK: - Fixtures

    /// Dispatches by request path so a single `respond(accept: true)` call
    /// — which hits BOTH `/companions/respond` and (Fix 4) `/companions/
    /// my-trips` in sequence — gets the right canned response for each.
    private func respondThenMyTripsHandler(
        respondStatus: Int, myTripsTripId: UUID
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let path = req.url!.path
            let body: Data
            if path.hasSuffix("/companions/respond") {
                body = Data(#"{"status":"ok","payload":{"status":\#(respondStatus)}}"#.utf8)
            } else if path.hasSuffix("/companions/my-trips") {
                body = Data(#"""
                {"status":"ok","payload":{"items":[{
                    "id":"\#(myTripsTripId.uuidString)",
                    "author":{"id":"\#(UUID().uuidString)","displayName":"Driver","avatarEmoji":"🚗","profileLevel":1},
                    "title":"Accepted trip",
                    "startDate":"2026-08-10T18:19:21.136Z",
                    "distance":1000,
                    "duration":0,
                    "photoCount":0,
                    "reactionCount":0,
                    "reactionBreakdown":[],
                    "badgeIds":[]
                }],"nextCursor":null}}
                """#.utf8)
            } else {
                XCTFail("unexpected request path: \(path)")
                body = Data(#"{"status":"error","code":"UNEXPECTED","message":"unexpected"}"#.utf8)
            }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    private func respondFailureHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"{"status":"error","code":"COMPANION_INVITE_NOT_FOUND","message":"nope"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    // MARK: - Fix 4: accepting invalidates myTrips

    /// THE regression: before this fix, `respond(accept: true)` never
    /// touched `myTrips` at all — the newly-accepted trip stayed missing
    /// from «Со мной» until something else happened to call
    /// `loadMyTrips(reset: true)` (leaving the profile tab and returning).
    /// Fails if `respond` stops calling `loadMyTrips(reset: true)` after a
    /// successful accept.
    func testAcceptingInvitationInvalidatesMyTrips() async throws {
        let tripId = UUID()
        let notificationId = UUID()
        MockURLProtocol.requestHandler = respondThenMyTripsHandler(respondStatus: 1, myTripsTripId: tripId)
        let store = CompanionsStore(client: client, repository: repo)
        XCTAssertTrue(store.myTrips.isEmpty, "sanity: nothing loaded yet")

        try await store.respond(tripId: tripId, notificationId: notificationId, accept: true)

        XCTAssertEqual(store.myTrips.map(\.id), [tripId], "the accepted trip must be in myTrips right after respond() returns")
        XCTAssertEqual(store.myTripsLoadState, .loaded)
    }

    /// Contrast case: DECLINING must NOT trigger a `myTrips` fetch at all —
    /// there's nothing to invalidate (a declined invite was never going to
    /// appear in «Со мной»), and firing one anyway would be a wasted
    /// request. `myTripsLoadState` can only leave `.idle` by way of
    /// `performLoadMyTrips` running (success or failure both move it to
    /// `.loaded`/`.failed`) — so it reading back `.idle` is a direct proof
    /// `loadMyTrips` was never called, not just an absence-of-evidence
    /// check.
    func testDecliningInvitationDoesNotTouchMyTrips() async throws {
        let tripId = UUID()
        let notificationId = UUID()
        MockURLProtocol.requestHandler = respondThenMyTripsHandler(respondStatus: 2, myTripsTripId: tripId)
        let store = CompanionsStore(client: client, repository: repo)

        try await store.respond(tripId: tripId, notificationId: notificationId, accept: false)

        XCTAssertTrue(store.myTrips.isEmpty)
        XCTAssertEqual(store.myTripsLoadState, .idle, "declining must never touch myTripsLoadState")
    }

    // MARK: - Fix 1: respond() records the ANSWERED notification id

    /// The real-network-path companion to `CompanionsStorePersistenceTests
    /// .testFreshInvitationAfterDeclineIsAnswerable` — this one drives the
    /// actual `respond()` call (rather than seeding `UserDefaults`
    /// directly) to prove the WRITE side of Fix 1, not just the read side.
    func testRespondRecordsAnsweredNotificationId() async throws {
        let tripId = UUID()
        let notificationId = UUID()
        let otherNotificationId = UUID()
        MockURLProtocol.requestHandler = respondThenMyTripsHandler(respondStatus: 2, myTripsTripId: tripId)
        let store = CompanionsStore(client: client, repository: repo)

        try await store.respond(tripId: tripId, notificationId: notificationId, accept: false)

        XCTAssertEqual(store.respondedStatus(for: tripId, notificationId: notificationId), .declined)
        XCTAssertNil(
            store.respondedStatus(for: tripId, notificationId: otherNotificationId),
            "a DIFFERENT notification id for the same trip must still read as unanswered")
    }

    /// A failed respond must roll back BOTH the trip-level AND the
    /// invitation-id bookkeeping — not just one of the two — or a retried
    /// accept/decline after a network blip could leave the two dictionaries
    /// disagreeing with each other.
    func testFailedRespondRollsBackInvitationId() async throws {
        let tripId = UUID()
        let notificationId = UUID()
        MockURLProtocol.requestHandler = respondFailureHandler()
        let store = CompanionsStore(client: client, repository: repo)

        do {
            try await store.respond(tripId: tripId, notificationId: notificationId, accept: true)
            XCTFail("expected throw")
        } catch {
            // expected
        }

        XCTAssertNil(store.respondedStatus(for: tripId, notificationId: notificationId))
        XCTAssertNil(store.respondedStatus(for: tripId))
    }
}
