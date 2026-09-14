import XCTest
import CoreData
@testable import TripTrack

/// Отрезки едут внутри поездки той же дисциплиной, что отметки: список целиком
/// заменяет прежний, а ОТСУТСТВИЕ ключа — это старый сервер, а не пустой
/// список. Спутать эти два случая значит стирать отрезки на каждом пуле.
final class TripSegmentSyncTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var tripId: UUID!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        tripId = UUID()
        trip.id = tripId
        trip.startDate = t0
        trip.endDate = t0.addingTimeInterval(7_200)
        trip.isPrivate = false
        trip.syncStatus = SyncStatus.synced.rawValue
        trip.serverCreatedAt = t0
        try? ctx.save()
    }

    /// Поля обнуляем: иначе `PersistenceController(inMemory:)` держит свою
    /// модель до конца прогона и роняет ЧУЖОЙ класс (см. «Ловушки» в CLAUDE.md).
    override func tearDown() {
        repo = nil
        pc = nil
        tripId = nil
        super.tearDown()
    }

    private func checkpoint(elapsed: TimeInterval) -> TripCheckpoint {
        let cp = TripCheckpoint(timestamp: t0.addingTimeInterval(elapsed), latitude: 45, longitude: 38.9,
                                distanceFromStart: elapsed * 20, elapsedFromStart: elapsed)
        return repo.addCheckpoint(cp, to: tripId) ?? cp
    }

    private func payload(
        checkpoints: [TripCheckpoint], segments: [TripSegmentPayload]?
    ) -> TripSyncPayload {
        TripSyncPayload(
            id: tripId, title: "t", description: nil,
            startDate: t0, endDate: t0.addingTimeInterval(7_200),
            distance: 100_000, maxSpeed: 20, averageSpeed: 15, fuelUsed: 0, elevation: 0,
            maxAltitude: nil, drivingTime: nil, stoppedTime: nil, region: nil,
            isPrivate: true, vehicleId: nil, fuelCurrency: nil, previewPolyline: nil,
            badgesJson: nil, xpEarned: 0,
            conflictVersion: 1, lastModifiedAt: t0.addingTimeInterval(10_000),
            serverCreatedAt: t0, trackPoints: nil, photos: nil,
            checkpoints: checkpoints.enumerated().map { index, c in
                TripCheckpointPayload(
                    id: c.id, timestamp: c.timestamp, latitude: c.latitude, longitude: c.longitude,
                    distanceFromStart: c.distanceFromStart, elapsedFromStart: c.elapsedFromStart,
                    name: c.name, photoId: nil, photoIds: nil, placeId: nil, sortOrder: index)
            },
            segments: segments)
    }

    // MARK: - (g) провод несёт отрезки

    func testPayloadCarriesSegments() {
        let a = checkpoint(elapsed: 600)
        let b = checkpoint(elapsed: 5_400)
        repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id)
        repo.updateSegment(id: repo.fetchTripDetail(id: tripId)?.segments.first?.id ?? UUID(), name: "Серпантин")

        guard let trip = repo.fetchTripDetail(id: tripId),
              let entity = repo.fetchEntity(id: tripId) else { return XCTFail("поездка не нашлась") }
        let p = TripSyncPayload(trip: trip, entity: entity)

        XCTAssertEqual(p.segments?.count, 1)
        XCTAssertEqual(p.segments?.first?.fromCheckpointId, a.id)
        XCTAssertEqual(p.segments?.first?.toCheckpointId, b.id)
        XCTAssertEqual(p.segments?.first?.name, "Серпантин")
        XCTAssertEqual(p.segments?.first?.id, trip.segments.first?.id)
    }

    /// Провод не везёт ни времени, ни километров отрезка — их считают из двух
    /// отметок. Второй счёт однажды разошёлся бы с одометром поездки.
    func testWireCarriesNoTimeOrDistance() throws {
        let a = checkpoint(elapsed: 600), b = checkpoint(elapsed: 5_400)
        repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id)
        guard let trip = repo.fetchTripDetail(id: tripId),
              let entity = repo.fetchEntity(id: tripId) else { return XCTFail("поездка не нашлась") }

        let data = try JSONEncoder().encode(TripSyncPayload(trip: trip, entity: entity).segments)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("distance"))
        XCTAssertFalse(json.contains("elapsed"))
        XCTAssertFalse(json.contains("duration"))
    }

    // MARK: - (h) пул

    /// Ключа нет — старый сервер (или список поездок без деталей). Локальные
    /// отрезки не трогаем: иначе каждый пул стирал бы то, что человек только
    /// что создал.
    func testPullWithoutTheSegmentsKeyKeepsLocalSegments() {
        let a = checkpoint(elapsed: 600), b = checkpoint(elapsed: 5_400)
        let local = repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id)

        repo.applyRemoteTrip(payload(checkpoints: [a, b], segments: nil))
        repo.flushPendingApplies()

        XCTAssertEqual(repo.fetchTripDetail(id: tripId)?.segments.map(\.id), [local?.id].compactMap { $0 })
    }

    /// Ключ есть — сервер и есть правда, список заменяется целиком.
    func testPullWithTheSegmentsKeyReplacesLocalSegments() {
        let a = checkpoint(elapsed: 600), b = checkpoint(elapsed: 5_400)
        repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id)

        let fromServer = TripSegmentPayload(
            id: UUID(), fromCheckpointId: a.id, toCheckpointId: b.id, name: "Перевал")
        repo.applyRemoteTrip(payload(checkpoints: [a, b], segments: [fromServer]))
        repo.flushPendingApplies()

        let segments = repo.fetchTripDetail(id: tripId)?.segments ?? []
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.id, fromServer.id)
        XCTAssertEqual(segments.first?.name, "Перевал")
    }

    /// Пустой список — тоже ответ: человек удалил отрезок на другом телефоне.
    func testPullWithAnEmptySegmentsListClearsThem() {
        let a = checkpoint(elapsed: 600), b = checkpoint(elapsed: 5_400)
        repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id)

        repo.applyRemoteTrip(payload(checkpoints: [a, b], segments: []))
        repo.flushPendingApplies()

        XCTAssertTrue(repo.fetchTripDetail(id: tripId)?.segments.isEmpty ?? false)
    }
}
