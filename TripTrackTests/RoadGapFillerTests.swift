import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Дорога вместо прямой (спека §2.3) и проход по старым поездкам (§2.5).
@MainActor
final class RoadGapFillerTests: XCTestCase {
    private var pc: PersistenceController!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        pc = nil
        super.tearDown()
    }

    private func tunnelSpecs() -> [TrackTestKit.PointSpec] {
        (0...20).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
            + (80...100).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
    }

    /// Дыра с 20-й по 80-ю секунду между (0, 200) и (0, 800), уже с прямой.
    private func processedTunnelTrip() async throws -> TripEntity {
        let entity = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs())
        await PostTripTrackProcessor(persistenceController: pc).processTrip(try XCTUnwrap(entity.id))
        return entity
    }

    /// Крюк на 150 м вбок: 700 м пути, 90 с езды — правдоподобно.
    private static let detour: [CLLocationCoordinate2D] = [
        TrackTestKit.coordinate(east: 0, north: 200), TrackTestKit.coordinate(east: 150, north: 400),
        TrackTestKit.coordinate(east: 150, north: 600), TrackTestKit.coordinate(east: 0, north: 800),
    ]

    private func road(distance: Double = 800) -> RoadRoute {
        RoadRoute(coordinates: Self.detour, distance: distance, expectedTravelTime: 90)
    }

    private func filler(_ router: RoadRouter, online: Bool = true) -> RoadGapFiller {
        RoadGapFiller(router: router, persistence: pc, isAllowedToRun: { online },
                      pause: { _ in }, reveal: { _ in })
    }

    private func fills(_ entity: TripEntity) -> [TrackPointEntity] {
        (entity.trackPoints?.array as? [TrackPointEntity] ?? []).filter(\.isInterpolated)
    }

    func testPlausibleRoadReplacesTheStraightFill() async throws {
        let entity = try await processedTunnelTrip()
        let distanceBefore = entity.distance
        let router = StubRoadRouter { _, _ in self.road() }
        let outcome = await filler(router).fill(tripId: try XCTUnwrap(entity.id))
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(entity.roadFillState, RoadFillState.done.rawValue)
        XCTAssertTrue(fills(entity).contains { $0.longitude > TrackTestKit.origin.longitude + 0.001 },
                      "достройка ушла на дорогу")
        XCTAssertEqual(entity.distance, distanceBefore, "километры достройку не видят")
    }

    func testImplausibleRoadKeepsTheStraightLine() async throws {
        let entity = try await processedTunnelTrip()
        let router = StubRoadRouter { _, _ in self.road(distance: 5000) }
        _ = await filler(router).fill(tripId: try XCTUnwrap(entity.id))
        XCTAssertEqual(entity.roadFillState, RoadFillState.done.rawValue)
        XCTAssertTrue(fills(entity).allSatisfy { abs($0.longitude - TrackTestKit.origin.longitude) < 0.0001 })
    }

    /// Review Focus 4: лимит или сеть — поездка ждёт, прямая цела, повтор не
    /// плодит второй достройки и дорогу второй раз не спрашивает.
    func testThrottledKeepsPendingAndTheRetryDoesNotDuplicate() async throws {
        let entity = try await processedTunnelTrip()
        let id = try XCTUnwrap(entity.id)
        let straightCount = fills(entity).count

        let router = StubRoadRouter { _, _ in throw RoadRouteError.throttled }
        let first = await filler(router).fill(tripId: id)
        XCTAssertEqual(first, .stillPending)
        XCTAssertEqual(entity.roadFillState, RoadFillState.pending.rawValue)
        XCTAssertEqual(fills(entity).count, straightCount)

        router.answer = { _, _ in self.road() }
        let second = await filler(router).fill(tripId: id)
        XCTAssertEqual(second, .done)
        let expected = GapFill.resample(Self.detour, from: TrackTestKit.epoch.addingTimeInterval(20),
                                        to: TrackTestKit.epoch.addingTimeInterval(80),
                                        altitudeFrom: 30, altitudeTo: 30).count
        XCTAssertEqual(fills(entity).count, expected)

        let third = await filler(router).fill(tripId: id)
        XCTAssertEqual(third, .done)
        XCTAssertEqual(router.calls, 2, "дорогу второй раз не спрашивают")
    }

    func testNotAllowedToRunLeavesEverythingAsIs() async throws {
        let entity = try await processedTunnelTrip()
        let router = StubRoadRouter { _, _ in self.road() }
        let outcome = await filler(router, online: false).fill(tripId: try XCTUnwrap(entity.id))
        XCTAssertEqual(outcome, .stillPending)
        XCTAssertEqual(router.calls, 0)
    }

    func testLibraryScanFillsOldTripsWithoutMovingTheirKilometres() async throws {
        let old = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs(), processed: true)
        old.distance = 1234.5   // что бы там ни лежало — не трогаем
        try pc.container.viewContext.save()

        let router = StubRoadRouter { _, _ in throw RoadRouteError.offline }
        let pending = await filler(router).scanLibrary()
        XCTAssertEqual(pending, 1)
        pc.container.viewContext.refreshAllObjects()
        XCTAssertEqual(old.roadFillState, RoadFillState.pending.rawValue)
        XCTAssertFalse(fills(old).isEmpty)
        XCTAssertEqual(old.distance, 1234.5)
    }

    /// Review Focus 5: поездка пула уже с достройкой.
    func testLibraryScanLeavesAlreadyFilledTripsAlone() async throws {
        var specs = (0...20).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
        specs.append(.init(east: 0, north: 500, seconds: 50, accuracy: -1, speed: -1, interpolated: true))
        specs += (80...100).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
        let pulled = TrackTestKit.insertTrip(into: pc, points: specs, processed: true)

        let router = StubRoadRouter { _, _ in throw RoadRouteError.offline }
        let pending = await filler(router).scanLibrary()
        XCTAssertEqual(pending, 0)
        pc.container.viewContext.refreshAllObjects()
        XCTAssertEqual(fills(pulled).count, 1)
        XCTAssertEqual(pulled.roadFillState, RoadFillState.done.rawValue)
    }
}
