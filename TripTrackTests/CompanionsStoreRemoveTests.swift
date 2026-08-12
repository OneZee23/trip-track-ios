import XCTest
@testable import TripTrack

/// Coverage for `CompanionsStore.remove(tripId:accountId:)` — Fix 3
/// (companions review, second wave): a companion leaving a trip via
/// `TripDetailView`'s new «Покинуть поездку» affordance must make that
/// trip disappear from «Со мной» (`myTrips`), not just from the roster
/// (`companionsByTrip`) the trip-detail card itself reads.
@MainActor
final class CompanionsStoreRemoveTests: XCTestCase {
    private var session: URLSession!
    private var client: APIClient!
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private let myId = UUID()
    private let otherCompanionId = UUID()

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
        TokenStore.shared.setAccountId(myId)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        TokenStore.shared.clear()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func myTripsHandler(items: [UUID]) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let itemsJSON = items.map { id -> String in
                #"{"id":"\#(id.uuidString)","author":{"id":"\#(UUID().uuidString)","displayName":"Driver","avatarEmoji":"🚗","profileLevel":1},"title":"T","startDate":"2026-08-10T18:19:21.136Z","distance":1000,"duration":0,"photoCount":0,"reactionCount":0,"reactionBreakdown":[],"badgeIds":[]}"#
            }.joined(separator: ",")
            let body = Data(#"{"status":"ok","payload":{"items":[\#(itemsJSON)],"nextCursor":null}}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    private func removeOkHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"{"status":"ok","payload":{"ok":true}}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    private func removeFailureHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"{"status":"error","code":"COMPANION_FORBIDDEN","message":"nope"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    /// Seeds `store.myTrips` with a real successful `loadMyTrips` fetch —
    /// `myTrips` has no settable init parameter, so this is the only way
    /// to get a trip into it under test.
    private func seedMyTrips(_ store: CompanionsStore, tripId: UUID, otherTripId: UUID) async {
        MockURLProtocol.requestHandler = myTripsHandler(items: [tripId, otherTripId])
        await store.loadMyTrips(reset: true)
        XCTAssertEqual(Set(store.myTrips.map(\.id)), [tripId, otherTripId], "sanity: seed landed")
    }

    // MARK: - Fix 3: leaving removes the trip from myTrips

    /// THE regression: leaving a trip (self-removal) used to only touch
    /// `companionsByTrip` — «Со мной» kept showing the trip until the next
    /// full `loadMyTrips(reset: true)`. Fails if `remove` stops special-
    /// casing `accountId == TokenStore.shared.accountId`.
    func testLeavingTripRemovesItFromMyTrips() async throws {
        let tripId = UUID()
        let otherTripId = UUID()
        let store = CompanionsStore(client: client, repository: repo)
        await seedMyTrips(store, tripId: tripId, otherTripId: otherTripId)

        MockURLProtocol.requestHandler = removeOkHandler()
        try await store.remove(tripId: tripId, accountId: myId)

        XCTAssertEqual(store.myTrips.map(\.id), [otherTripId], "the left trip must be gone; unrelated trips stay")
    }

    /// Contrast case: the OWNER removing SOMEONE ELSE from a trip must NOT
    /// touch `myTrips` — that trip was never the viewer's own «Со мной»
    /// entry to begin with (viewer is the owner, not a companion on it).
    func testOwnerRemovingSomeoneElseDoesNotTouchMyTrips() async throws {
        let tripId = UUID()
        let otherTripId = UUID()
        let store = CompanionsStore(client: client, repository: repo)
        await seedMyTrips(store, tripId: tripId, otherTripId: otherTripId)

        MockURLProtocol.requestHandler = removeOkHandler()
        try await store.remove(tripId: tripId, accountId: otherCompanionId)

        XCTAssertEqual(
            Set(store.myTrips.map(\.id)), [tripId, otherTripId],
            "removing a DIFFERENT account must not prune the viewer's own myTrips")
    }

    /// A failed leave must restore the trip to `myTrips` — otherwise a
    /// network blip would make the trip vanish from «Со мной» client-side
    /// even though the server never actually removed the companion row.
    func testFailedLeaveRestoresMyTrips() async throws {
        let tripId = UUID()
        let otherTripId = UUID()
        let store = CompanionsStore(client: client, repository: repo)
        await seedMyTrips(store, tripId: tripId, otherTripId: otherTripId)

        MockURLProtocol.requestHandler = removeFailureHandler()
        do {
            try await store.remove(tripId: tripId, accountId: myId)
            XCTFail("expected throw")
        } catch {
            // expected
        }

        XCTAssertEqual(Set(store.myTrips.map(\.id)), [tripId, otherTripId], "myTrips must be restored on failure")
    }
}
