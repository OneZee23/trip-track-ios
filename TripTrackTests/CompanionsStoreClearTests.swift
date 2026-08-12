import XCTest
@testable import TripTrack

/// Coverage for `CompanionsStore.clear()` — Fix 7 (companions review,
/// second wave): signing out must not just blank the published state, it
/// must also cancel whatever `candidates`/`loadMyTrips` request is still
/// in flight AND bump both generation counters — otherwise a response that
/// belongs to the account that JUST signed out can land after `clear()`
/// runs and repopulate the store for whichever account signs in next.
///
/// The race is reproduced deterministically with a request handler that
/// sleeps for a fixed, generous window before responding (same technique
/// `CompanionsCachePersistenceTests`'s `testUpdateCompanions_DoesNotChangeLastModifiedAt`
/// uses `Thread.sleep` for, just applied to the network layer instead of a
/// wall clock): the request handler runs on `URLSession`'s own background
/// queue, so blocking IT with `Thread.sleep` does not block this test's
/// `async` code — it only guarantees `clear()` gets a chance to run WHILE
/// the request is still outstanding.
@MainActor
final class CompanionsStoreClearTests: XCTestCase {
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
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func delayedCandidatesHandler(
        seconds: TimeInterval, accountId: UUID
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            Thread.sleep(forTimeInterval: seconds)
            let body = Data(#"""
            {"status":"ok","payload":{"items":[{"id":"\#(accountId.uuidString)","displayName":"Stale","avatarEmoji":"🙂","profileLevel":1}],"nextCursor":null}}
            """#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    // MARK: - Fix 7: a response landing after clear() must not repopulate the store

    /// THE regression: before this fix, `clear()` nulled `candidatesTask`
    /// WITHOUT calling `.cancel()` and never bumped `candidatesGeneration`
    /// — so `performCandidates`'s own `guard generation ==
    /// candidatesGeneration` still passed for a request that was already
    /// in flight when `clear()` ran, and its (stale, belongs-to-the-signed-
    /// -out-account) response landed straight into `candidates` and
    /// `candidatesLoadState` regardless. Fails if `clear()` stops bumping
    /// `candidatesGeneration` before the response resolves (removing the
    /// `.cancel()` call alone does NOT fail this test — cancellation is
    /// only cooperative and this handler ignores it — which is exactly why
    /// the generation bump, not the cancel, is the guarantee this test
    /// pins).
    func testClear_DiscardsCandidatesResponseThatResolvesAfterward() async throws {
        let tripId = UUID()
        let staleAccountId = UUID()
        MockURLProtocol.requestHandler = delayedCandidatesHandler(seconds: 0.3, accountId: staleAccountId)
        let store = CompanionsStore(client: client, repository: repo)

        let inFlight = Task { await store.candidates(tripId: tripId, reset: true) }
        // Give the request enough time to actually start (enter
        // `performCandidates`, reach the network call, and start blocking
        // in the handler's `Thread.sleep`) before clearing — the 0.3s
        // response delay above comfortably outlasts this.
        try await Task.sleep(nanoseconds: 50_000_000)

        store.clear()

        // Let the slow, now-stale response actually land before asserting.
        await inFlight.value

        XCTAssertTrue(
            store.candidates.isEmpty,
            "a response that resolved AFTER clear() must not repopulate the store")
        XCTAssertEqual(
            store.candidatesLoadState, .idle,
            "clear()'s .idle reset must survive a late in-flight response landing after it")
    }
}
