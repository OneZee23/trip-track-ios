import XCTest
import CoreData
@testable import TripTrack

/// Coverage for Task 7 — `Trip.companions` repurposed as an OFFLINE CACHE of
/// the server's roster for the viewer's OWN trips, instead of the
/// locally-invented labels it used to hold. `CompanionsStore.list(tripId:)`
/// writes that cache after a successful `/companions/list` fetch;
/// `CompanionsCardModel.decide` reads it back only when today's fetch
/// fails AND nothing survived in memory either.
///
/// Every CoreData interaction here goes through an ISOLATED in-memory
/// `PersistenceController`/`CoreDataTripRepository` pair (same pattern as
/// `WithMeSectionTests.insertLocalTrip`), never the shared on-disk store —
/// so the foreign-trip row count in test 2 can't be polluted by (or
/// pollute) anything else in the suite.
///
/// Each test is built to fail if the rule it names is removed. Verified by
/// temporarily breaking the corresponding production code, re-running this
/// file, watching the right test fail, then reverting — see the report for
/// the exact mutations used.
@MainActor
final class CompanionsCachePersistenceTests: XCTestCase {

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

    /// A trip that DOES have a local `TripEntity` — the only kind
    /// `TripRepository.updateCompanions` will ever actually write to.
    @discardableResult
    private func insertLocalTrip(id: UUID = UUID()) -> UUID {
        let ctx = pc.container.viewContext
        let entity = TripEntity(context: ctx)
        entity.id = id
        entity.userId = SettingsManager.shared.localUserId
        entity.startDate = Date()
        entity.endDate = Date().addingTimeInterval(600)
        entity.distance = 1000
        entity.isPrivate = true
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.lastModifiedAt = Date()
        try? ctx.save()
        return id
    }

    private func tripEntityCount(id: UUID) -> Int {
        let ctx = pc.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return (try? ctx.count(for: request)) ?? -1
    }

    private func listResponseHandler(
        items: [(id: UUID, name: String?, emoji: String?, status: Int)]
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let itemsJSON = items.map { row -> String in
                let nameJSON = row.name.map { "\"\($0)\"" } ?? "null"
                let emojiJSON = row.emoji.map { "\"\($0)\"" } ?? "null"
                return #"{"accountId":"\#(row.id.uuidString)","displayName":\#(nameJSON),"avatarEmoji":\#(emojiJSON),"status":\#(row.status)}"#
            }.joined(separator: ",")
            // `APIClient.post` expects the `{"status":"ok","payload":...}`
            // envelope (see `CompanionPhotoUploadTests.okResponseHandler`) —
            // NOT the bare `CompanionsListResponse` shape `CompanionsDTOTests`
            // decodes directly with its own standalone `JSONDecoder`.
            let body = Data(#"{"status":"ok","payload":{"items":[\#(itemsJSON)],"isOwnerView":true}}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    /// Same shape `CompanionPhotoUploadTests.errorResponseHandler` uses — a
    /// 200 carrying `APIClient`'s error envelope, which is what a real
    /// server-side failure looks like on the wire.
    private func errorResponseHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"{"status":"error","code":"COMPANIONS_LIST_FAILED","message":"nope"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    /// The exact wire shape `resolveTripAccess` sends for a trip it can't
    /// find (`TripNotFound` → `"TRIP_NOT_FOUND"` → `APIError.tripNotFound`
    /// — see `APIError.from`). This is what the server answers for a trip
    /// this device has locally but never uploaded — no server row exists
    /// to look up at all — AND for a genuine record→upload race.
    private func tripNotFoundResponseHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"{"status":"error","code":"TRIP_NOT_FOUND","message":"nope"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    // MARK: - 1. Successful list on an OWN trip writes the cache

    /// The core of this task: a successful `/companions/list` response for
    /// a trip this device actually has locally must land in
    /// `companionsJSON` via `TripRepository.updateCompanions`, readable
    /// straight back out through `fetchTripDetail`. Fails if
    /// `CompanionsStore.list` stops calling that write after success.
    func testSuccessfulList_OwnTrip_WritesCache() async throws {
        let tripId = insertLocalTrip()
        let companionId = UUID()
        MockURLProtocol.requestHandler = listResponseHandler(
            items: [(id: companionId, name: "Аня", emoji: "🙂", status: 1)])
        let store = CompanionsStore(client: client, repository: repo)

        _ = try await store.list(tripId: tripId)

        let cached = repo.fetchTripDetail(id: tripId)?.companions
        XCTAssertEqual(cached?.count, 1)
        XCTAssertEqual(cached?.first?.accountId, companionId)
        XCTAssertEqual(cached?.first?.displayName, "Аня")
        XCTAssertEqual(cached?.first?.avatarEmoji, "🙂")
        XCTAssertEqual(cached?.first?.status, .accepted)
    }

    // MARK: - 2. Successful list on a FOREIGN trip writes nothing, creates no row

    /// THE rule the whole "Со мной" design rests on: a trip with no local
    /// `TripEntity` must never get one just because its roster loaded.
    /// Counts real CoreData rows before/after rather than trusting a mock —
    /// a regression that started calling something OTHER than
    /// `TripRepository.updateCompanions` (which itself no-ops for a missing
    /// entity) could still slip past an assertion phrased only against the
    /// store's in-memory state.
    func testSuccessfulList_ForeignTrip_CreatesNoRow() async throws {
        let foreignTripId = UUID() // never inserted locally
        let before = tripEntityCount(id: foreignTripId)
        XCTAssertEqual(before, 0, "sanity: nothing should exist for a fresh random id yet")
        MockURLProtocol.requestHandler = listResponseHandler(
            items: [(id: UUID(), name: "Дима", emoji: "😎", status: 1)])
        let store = CompanionsStore(client: client, repository: repo)

        _ = try await store.list(tripId: foreignTripId)

        XCTAssertEqual(
            tripEntityCount(id: foreignTripId), before,
            "a foreign trip must never gain a local CoreData row just because its roster loaded")
    }

    // MARK: - 3. Failed list with a populated cache falls back with a stale indication

    /// The offline-fallback half of the task: nothing in memory (a fresh
    /// `CompanionsStore`), today's fetch fails, but a PRIOR successful load
    /// already wrote a cache — the card must show those cached rows with a
    /// quiet staleness note (`.stale`), not the bare retry prompt.
    func testFailedList_WithPopulatedCache_FallsBackWithStaleBanner() async throws {
        let tripId = insertLocalTrip()
        let companionId = UUID()
        // Simulate an earlier successful load having already cached a roster.
        repo.updateCompanions(for: tripId, companions: [
            TripCompanion(accountId: companionId, displayName: "Дима", avatarEmoji: "😎", status: .accepted)
        ])
        MockURLProtocol.requestHandler = errorResponseHandler()
        let store = CompanionsStore(client: client, repository: repo)

        do {
            _ = try await store.list(tripId: tripId)
            XCTFail("expected throw")
        } catch {
            // expected — list() rethrows after recording the failure
        }

        let cached = repo.fetchTripDetail(id: tripId)?.companions ?? []
        XCTAssertEqual(cached.map(\.accountId), [companionId], "the pre-existing cache must survive a failed refresh")

        let decision = CompanionsCardModel.decide(
            companions: store.companionsByTrip[tripId] ?? [], isOwn: true,
            loadState: store.loadState(for: tripId), cached: cached.map(\.asCompanionItem))
        guard case .own(let rows, let banner) = decision else {
            return XCTFail("expected .own, got \(decision)")
        }
        XCTAssertEqual(rows.map(\.id), [companionId])
        XCTAssertEqual(banner, .stale)
    }

    // MARK: - 4. Failed list with an empty cache keeps today's error state

    /// The other half: with NOTHING ever cached for this trip, a failed
    /// fetch must render exactly what it does today — the plain
    /// error-with-retry — not manufacture stale rows out of nothing.
    func testFailedList_WithEmptyCache_ShowsPlainErrorState() async throws {
        let tripId = insertLocalTrip() // never had a successful list before
        MockURLProtocol.requestHandler = errorResponseHandler()
        let store = CompanionsStore(client: client, repository: repo)

        do {
            _ = try await store.list(tripId: tripId)
            XCTFail("expected throw")
        } catch {
            // expected
        }

        let cached = repo.fetchTripDetail(id: tripId)?.companions ?? []
        XCTAssertTrue(cached.isEmpty, "sanity: nothing was ever cached for this trip")

        let decision = CompanionsCardModel.decide(
            companions: store.companionsByTrip[tripId] ?? [], isOwn: true,
            loadState: store.loadState(for: tripId), cached: cached.map(\.asCompanionItem))
        XCTAssertEqual(decision, .own(rows: [], banner: .error))
    }

    // MARK: - 5. Fix 2 — TRIP_NOT_FOUND on an own trip is an empty roster, not a failure

    /// The record→upload race this fix closes: `TripCompanionsSection` only
    /// calls `list` once it believes (via the LOCAL `Trip.isOnServer` flag)
    /// the trip is server-side, but the server can still answer
    /// `TRIP_NOT_FOUND` for it — same code a trip that never reached the
    /// server at all gets. On an OWN trip (`treatTripNotFoundAsEmpty:
    /// true`) this must resolve as a normal, successfully-loaded EMPTY
    /// roster: no throw, `loadStateByTrip == .loaded`, not `.failed`. Fails
    /// if `list` stops special-casing `APIError.tripNotFound` and instead
    /// lets it fall through to the generic failure path.
    func testTripNotFoundOnOwnTrip_TreatedAsEmptyLoadedRoster() async throws {
        let tripId = insertLocalTrip()
        MockURLProtocol.requestHandler = tripNotFoundResponseHandler()
        let store = CompanionsStore(client: client, repository: repo)

        let res = try await store.list(tripId: tripId, treatTripNotFoundAsEmpty: true)

        XCTAssertTrue(res.items.isEmpty)
        XCTAssertEqual(store.loadState(for: tripId), .loaded, "must read as a resolved empty roster, not .failed")
        XCTAssertEqual(store.companionsByTrip[tripId], [])
    }

    /// TRIP_NOT_FOUND on an own trip must not ERASE what is already known.
    ///
    /// It used to write an EMPTY roster straight into the offline cache. A trip
    /// taken private leaves the server, so every later list is a
    /// TRIP_NOT_FOUND — and pressing «повторить» on that trip wiped its
    /// companions from the device. The one durable record of who was in the
    /// car, destroyed by a refresh of it.
    func testTripNotFoundOnOwnTrip_KeepsWhatIsAlreadyKnown() async throws {
        let tripId = insertLocalTrip()
        let store = CompanionsStore(client: client, repository: repo)

        MockURLProtocol.requestHandler = listResponseHandler(
            items: [(id: UUID(), name: "Даниил", emoji: "🕵️", status: 1)])
        _ = try await store.list(tripId: tripId, treatTripNotFoundAsEmpty: true)
        XCTAssertEqual(repo.fetchTripDetail(id: tripId)?.companions.count, 1)

        // The trip leaves the server; every list now answers TRIP_NOT_FOUND.
        MockURLProtocol.requestHandler = tripNotFoundResponseHandler()
        let after = try await store.list(tripId: tripId, treatTripNotFoundAsEmpty: true)

        XCTAssertEqual(after.items.count, 1, "the known roster must survive")
        XCTAssertEqual(
            repo.fetchTripDetail(id: tripId)?.companions.count, 1,
            "the offline cache must not be overwritten with an empty roster"
        )
    }

    /// The flag is opt-in — a non-owner's `TRIP_NOT_FOUND` (the default,
    /// `treatTripNotFoundAsEmpty: false`) must still throw and record
    /// `.failed`, exactly as every other error does. Fails if the remap
    /// stops being conditional on the parameter.
    func testTripNotFoundWithoutFlag_StillFails() async throws {
        let tripId = insertLocalTrip()
        MockURLProtocol.requestHandler = tripNotFoundResponseHandler()
        let store = CompanionsStore(client: client, repository: repo)

        do {
            _ = try await store.list(tripId: tripId)
            XCTFail("expected throw when treatTripNotFoundAsEmpty is false")
        } catch {
            // expected
        }
        XCTAssertEqual(store.loadState(for: tripId), .failed)
    }

    // MARK: - 6. Fix 3 — the cache write must not touch lastModifiedAt

    /// `lastModifiedAt` is the last-write-wins clock the sync layer
    /// compares against the server's copy — a pure cache write (drawing the
    /// companions card) has nothing to do with the trip's own data and must
    /// not make the local row look newer than the server's for that reason.
    /// Fails if `updateCompanions` starts stamping `entity.lastModifiedAt =
    /// Date()` again.
    func testUpdateCompanions_DoesNotChangeLastModifiedAt() throws {
        let tripId = insertLocalTrip()
        let ctx = pc.container.viewContext
        let fetch: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        fetch.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
        let entityBefore = try XCTUnwrap(try ctx.fetch(fetch).first)
        let before = try XCTUnwrap(entityBefore.lastModifiedAt)

        // A real clock tick between the fixture's stamp and the cache write
        // — without it, a bug that DOES re-stamp `Date()` could coincidentally
        // land on the same millisecond and the assertion would pass by luck.
        Thread.sleep(forTimeInterval: 0.05)

        repo.updateCompanions(for: tripId, companions: [
            TripCompanion(accountId: UUID(), displayName: "Аня", avatarEmoji: "🙂", status: .accepted)
        ])

        let entityAfter = try XCTUnwrap(try ctx.fetch(fetch).first)
        XCTAssertEqual(entityAfter.lastModifiedAt, before, "the companions cache write must not advance the sync clock")
    }
}
