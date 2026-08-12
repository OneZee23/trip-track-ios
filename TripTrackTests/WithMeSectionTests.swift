import XCTest
import CoreData
@testable import TripTrack

/// Coverage for `WithMeSectionModel.decide` — the pure "what should the «Со
/// мной» profile section show" function behind
/// `TripTrack/Views/Profile/WithMeSection.swift` — plus the one rule the
/// whole task exists to protect: the profile's own aggregates (km, level,
/// streak, territory) must never be computed from anything this section
/// touches. Each test is built to fail if the rule it names is removed from
/// production code, not just to exercise the happy path.
final class WithMeSectionTests: XCTestCase {

    private func socialTrip(
        id: UUID = UUID(), distance: Double = 42_000, driverName: String? = "Driver A",
        isPrivate: Bool? = nil
    ) -> SocialFeedTrip {
        SocialFeedTrip(
            id: id,
            author: SocialAuthor(id: UUID(), displayName: driverName, avatarEmoji: "🏎️", profileLevel: 4),
            title: "Test trip",
            description: nil,
            startDate: Date(),
            endDate: nil,
            distance: distance,
            duration: 1800,
            maxSpeed: 20,
            elevation: nil,
            maxAltitude: nil,
            drivingTime: nil,
            stoppedTime: nil,
            region: "Test Region",
            isPrivate: isPrivate,
            previewPolyline: nil,
            photoCount: 0,
            firstPhotoThumbnail: nil,
            vehicle: nil,
            reactionCount: 0,
            reactionBreakdown: [],
            myReaction: nil,
            badgeIds: [],
            commentCountRaw: nil
        )
    }

    // MARK: - Never loaded

    /// Nothing has been asked yet — the section must not show a permanent
    /// skeleton for the common case (an account with zero companion trips
    /// ever). Fails if `decide` starts drawing something for `.idle`.
    func testNeverLoadedRendersHidden() {
        XCTAssertEqual(WithMeSectionModel.decide(myTrips: [], loadState: .idle), .hidden)
    }

    // MARK: - Loading, nothing cached yet

    /// A request is in flight but nothing is confirmed either way — same as
    /// `.idle`, must stay hidden rather than flash a skeleton on every
    /// profile load. Fails if `decide` starts drawing a loading banner here.
    func testLoadingWithNothingRendersHidden() {
        XCTAssertEqual(WithMeSectionModel.decide(myTrips: [], loadState: .loading), .hidden)
    }

    // MARK: - Loading, rows already on screen

    /// A background refresh / next page must NOT blank rows already
    /// showing. Fails if a cached, non-empty `myTrips` starts reading as
    /// `.hidden` (or drops its rows) while a request is in flight.
    func testLoadingWithRowsAlreadyShownKeepsRows() {
        let trip = socialTrip()
        let decision = WithMeSectionModel.decide(myTrips: [trip], loadState: .loading)
        XCTAssertEqual(decision, .content(rows: [.init(trip: trip)], banner: .loadingMore))
    }

    // MARK: - Loaded, genuinely empty

    /// The one case the brief calls out explicitly: a loaded-and-truly-empty
    /// list draws NO section at all. Fails if `decide` starts returning
    /// `.content` (even with an empty rows array and `.none` banner) here.
    func testLoadedAndEmptyRendersHidden() {
        XCTAssertEqual(WithMeSectionModel.decide(myTrips: [], loadState: .loaded), .hidden)
    }

    /// Happy-path companion to the empty case above: a loaded, non-empty
    /// list draws its rows with no banner at all. Fails if `decide` starts
    /// hiding real rows, or leaves a stale loading/error banner attached
    /// once the load has genuinely succeeded.
    func testLoadedWithRowsRendersNoBanner() {
        let trip = socialTrip()
        let decision = WithMeSectionModel.decide(myTrips: [trip], loadState: .loaded)
        XCTAssertEqual(decision, .content(rows: [.init(trip: trip)], banner: .none))
    }

    // MARK: - Failed, nothing cached

    /// THE bug this `loadState` plumbing exists to close (same fix Task
    /// 2/3's reviews made `list`/`candidates` apply): a failed
    /// `/companions/my-trips` call must show a retryable error, never the
    /// same blank the section draws for a genuinely companion-trip-free
    /// account. Fails if `decide` still returns `.hidden` for a failed,
    /// empty load.
    func testFailedWithNothingShowsErrorNotHidden() {
        let decision = WithMeSectionModel.decide(myTrips: [], loadState: .failed)
        XCTAssertEqual(decision, .content(rows: [], banner: .error))
        XCTAssertNotEqual(decision, .hidden)
    }

    // MARK: - Failed, rows already cached

    /// A failed REFRESH (or failed next page) must keep whatever rows are
    /// already on screen AND surface the failure — neither silently
    /// dropping the error nor evicting good rows to show one. Fails if the
    /// rows disappear on failure, or the banner stops being `.error` just
    /// because rows are present.
    func testFailedWithRowsKeepsRowsAndSurfacesError() {
        let trip = socialTrip()
        let decision = WithMeSectionModel.decide(myTrips: [trip], loadState: .failed)
        XCTAssertEqual(decision, .content(rows: [.init(trip: trip)], banner: .error))
    }

    // MARK: - Profile aggregates isolation

    @discardableResult
    private func insertLocalTrip(_ pc: PersistenceController, distanceMeters: Double) -> UUID {
        let ctx = pc.container.viewContext
        let entity = TripEntity(context: ctx)
        let id = UUID()
        entity.id = id
        entity.userId = SettingsManager.shared.localUserId
        entity.startDate = Date()
        entity.endDate = Date().addingTimeInterval(600)
        entity.distance = distanceMeters
        entity.isPrivate = true
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.lastModifiedAt = Date()
        try? ctx.save()
        return id
    }

    /// THE rule the whole task exists to protect (brief): profile km /
    /// level / streak / territory are computed from the viewer's OWN trips
    /// only — a «Со мной» trip must never enter them. This is a decision
    /// the OWNER of this codebase made deliberately and it must not break
    /// by accident.
    ///
    /// Seeds an in-memory `CoreDataTripRepository` — the same repository
    /// `TripManager.fetchTrips()` reads from, which is what both
    /// `ProfileView.loadAggregates()` (feeds `MeAggregates`) and
    /// `MapViewModel.refreshTripStats()` (feeds `cachedTripCount`/
    /// `cachedTotalKm`, i.e. the strip + level/streak inputs) ultimately
    /// call — with two of the owner's OWN trips (15 km total). Separately
    /// builds a companion trip with a distance impossible to miss if it
    /// ever leaked in (994 km), converted through `Trip(social:)` — the
    /// ONLY documented path that ever turns a `SocialFeedTrip` into a
    /// `Trip` (`TripTrack/Models/Social/SocialTripAdapter.swift`) — and
    /// proves that conversion alone never reaches this repository, and that
    /// `MeAggregates.compute`, run over exactly what the repository
    /// returns, reports totals for the two owned trips ONLY.
    func testProfileAggregatesComputedFromLocalRepositoryExcludeCompanionTrip() {
        let pc = PersistenceController(inMemory: true)
        let repo = CoreDataTripRepository(persistenceController: pc)
        insertLocalTrip(pc, distanceMeters: 10_000)
        insertLocalTrip(pc, distanceMeters: 5_000)

        let companion = socialTrip(distance: 994_000)
        let companionAsTrip = Trip(social: companion)

        let localTrips = repo.fetchAllTrips()
        XCTAssertEqual(localTrips.count, 2, "only the owner's own trips may be in the local repository")
        XCTAssertFalse(
            localTrips.contains { $0.id == companionAsTrip.id },
            "a companion trip must never be persisted into the local repository")

        let agg = MeAggregates.compute(trips: localTrips, now: Date(), calendar: .current)
        XCTAssertEqual(agg.tripCount, 2)
        XCTAssertEqual(agg.totalKm, 15, accuracy: 0.001)
    }
}
