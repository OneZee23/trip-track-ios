import XCTest
@testable import TripTrack

/// Coverage for `CompanionsStore.candidates(tripId:query:reset:)` — Fix 9
/// (companions review, second wave): a FAILED `reset: true` candidates load
/// must not leave `candidates` holding whatever a PREVIOUS picker session
/// last successfully loaded — possibly another trip's rows entirely.
/// `CompanionsPickerSheet` mirrors `store.candidates` straight into its own
/// `displayedCandidates`, so a stale array here surfaced as wrong rows
/// sitting next to the picker's error banner instead of its proper empty/
/// error state.
@MainActor
final class CompanionsStoreCandidatesTests: XCTestCase {
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

    private func okHandler(accountId: UUID) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"""
            {"status":"ok","payload":{"items":[{"id":"\#(accountId.uuidString)","displayName":"Trip A candidate","avatarEmoji":"🙂","profileLevel":1}],"nextCursor":null}}
            """#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    private func errorHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"{"status":"error","code":"UNKNOWN_SERVER_ERROR","message":"nope"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    // MARK: - Fix 9: a failed reset load does not republish a previous session's rows

    /// THE regression: trip A's picker session loads successfully
    /// (`candidates` now holds A's rows). The picker is closed and reopened
    /// for trip B (`reset: true`) and THAT load fails outright — before
    /// this fix, `candidates` still held trip A's rows (`performCandidates`
    /// only ever overwrote them on SUCCESS), so the picker showed A's
    /// candidates next to an error banner instead of B's proper error
    /// state. Fails if `candidates(reset: true)` stops clearing `candidates`
    /// up front (i.e. only clears it inside `performCandidates` on success,
    /// same as before the fix).
    func testFailedResetLoad_DoesNotRepublishPreviousSessionRows() async throws {
        let tripA = UUID()
        let tripB = UUID()
        let candidateOnTripA = UUID()
        let store = CompanionsStore(client: client, repository: repo)

        MockURLProtocol.requestHandler = okHandler(accountId: candidateOnTripA)
        await store.candidates(tripId: tripA, reset: true)
        XCTAssertEqual(store.candidates.map(\.accountId), [candidateOnTripA], "sanity: trip A loaded successfully")

        MockURLProtocol.requestHandler = errorHandler()
        await store.candidates(tripId: tripB, reset: true)

        XCTAssertTrue(
            store.candidates.isEmpty,
            "a failed load for trip B must not still be showing trip A's candidates")
        XCTAssertEqual(store.candidatesLoadState, .failed)
    }

    /// Baseline: a SUCCESSFUL reset load for a new trip still correctly
    /// replaces the previous session's rows (proves the fix didn't
    /// overcorrect into never publishing anything).
    func testSuccessfulResetLoad_ReplacesPreviousSessionRows() async throws {
        let tripA = UUID()
        let tripB = UUID()
        let candidateOnTripA = UUID()
        let candidateOnTripB = UUID()
        let store = CompanionsStore(client: client, repository: repo)

        MockURLProtocol.requestHandler = okHandler(accountId: candidateOnTripA)
        await store.candidates(tripId: tripA, reset: true)

        MockURLProtocol.requestHandler = okHandler(accountId: candidateOnTripB)
        await store.candidates(tripId: tripB, reset: true)

        XCTAssertEqual(store.candidates.map(\.accountId), [candidateOnTripB])
        XCTAssertEqual(store.candidatesLoadState, .loaded)
    }
}
