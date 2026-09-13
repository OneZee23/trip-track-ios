import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Хранилище мест и проездов: одна ячейка — одно место, проезды заменяются
/// парой (место, поездка) целиком, удалённая поездка забирает свои проезды.
final class PlaceStoreTests: XCTestCase {
    private var pc: PersistenceController!
    private var store: CoreDataPlaceStore!
    private var repo: CoreDataTripRepository!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private let jubga = CLLocationCoordinate2D(latitude: 44.3196, longitude: 38.7089)

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = CoreDataPlaceStore(context: pc.container.viewContext)
        repo = CoreDataTripRepository(persistenceController: pc)
    }

    override func tearDown() {
        store = nil; repo = nil; pc = nil
        super.tearDown()
    }

    private func pass(place: UUID, trip: UUID, t: TimeInterval, course: Double = 0) -> PlacePass {
        PlacePass(placeId: place, tripId: trip, timestamp: t0.addingTimeInterval(t),
                  elapsedFromStart: t, distanceFromStart: t * 14, course: course)
    }

    func testSameCellIsOnePlaceAndKeepsFirstName() {
        let cell = Place.cell(latitude: jubga.latitude, longitude: jubga.longitude)
        let first = store.upsertPlace(cell: cell, coordinate: jubga, name: nil)
        XCTAssertTrue(first.isNew)
        XCTAssertEqual(first.place.id, Place.id(forCell: cell))
        let second = store.upsertPlace(cell: cell, coordinate: jubga, name: "Джубга")
        XCTAssertFalse(second.isNew)
        XCTAssertEqual(second.place.id, first.place.id)
        XCTAssertEqual(second.place.name, "Джубга", "имя достаётся месту, когда оно ещё безымянно")
        let third = store.upsertPlace(cell: cell, coordinate: jubga, name: "Поворот")
        XCTAssertEqual(third.place.name, "Джубга", "первое имя остаётся")
        XCTAssertEqual(store.fetchPlaces().count, 1)
    }

    func testCentroidIsMeanOfCheckpoints() {
        let cell = Place.cell(latitude: 44.3196, longitude: 38.7089)
        let p = store.upsertPlace(cell: cell, coordinate: jubga, name: nil).place
        store.recomputeCentroid(placeId: p.id, from: [
            CLLocationCoordinate2D(latitude: 44.3190, longitude: 38.7080),
            CLLocationCoordinate2D(latitude: 44.3200, longitude: 38.7100),
        ])
        let stored = store.fetchPlace(id: p.id)
        XCTAssertEqual(stored?.latitude ?? 0, 44.3195, accuracy: 1e-6)
        XCTAssertEqual(stored?.longitude ?? 0, 38.7090, accuracy: 1e-6)
    }

    func testReplacePassesIsIdempotentPerPlaceAndTrip() {
        let place = UUID(), tripA = UUID(), tripB = UUID()
        store.replacePasses(placeId: place, tripId: tripA, with: [pass(place: place, trip: tripA, t: 100), pass(place: place, trip: tripA, t: 900, course: 180)])
        store.replacePasses(placeId: place, tripId: tripB, with: [pass(place: place, trip: tripB, t: 300)])
        XCTAssertEqual(store.passes(placeId: place).count, 3)
        store.replacePasses(placeId: place, tripId: tripA, with: [pass(place: place, trip: tripA, t: 100)])
        XCTAssertEqual(store.passes(placeId: place).count, 2, "повтор сверки не удваивает проезды")
        XCTAssertEqual(store.passes(tripId: tripB).count, 1)
        XCTAssertEqual(store.passCount(placeId: place), 2)
    }

    func testDeletingPassesOfATripAndDeletingAPlace() {
        let place = UUID(), tripA = UUID(), tripB = UUID()
        store.replacePasses(placeId: place, tripId: tripA, with: [pass(place: place, trip: tripA, t: 100)])
        store.replacePasses(placeId: place, tripId: tripB, with: [pass(place: place, trip: tripB, t: 200)])
        store.deletePasses(tripId: tripA)
        XCTAssertEqual(store.passes(placeId: place).map(\.tripId), [tripB])
        let cell = Place.cell(latitude: jubga.latitude, longitude: jubga.longitude)
        let p = store.upsertPlace(cell: cell, coordinate: jubga, name: nil).place
        store.replacePasses(placeId: p.id, tripId: tripB, with: [pass(place: p.id, trip: tripB, t: 200)])
        store.deletePlace(id: p.id)
        XCTAssertNil(store.fetchPlace(id: p.id))
        XCTAssertTrue(store.passes(placeId: p.id).isEmpty, "проезды уходят вместе с местом")
    }

    // MARK: Репозиторий

    @discardableResult
    private func trip(withCheckpointAt coordinate: CLLocationCoordinate2D?, ended: Bool = true, mirrored: Bool = false) -> UUID {
        let ctx = pc.container.viewContext
        let e = TripEntity(context: ctx)
        let id = UUID()
        e.id = id; e.startDate = t0; e.endDate = ended ? t0.addingTimeInterval(3600) : nil
        e.distance = 100_000; e.isPrivate = true
        // `mirrored` — поездка, у которой есть копия на сервере: `deleteTrip`
        // без него ушёл бы коротким замыканием в `deleteTripHard` сам, а тест
        // должен звать `deleteTripHard` напрямую — как это делает транспорт.
        if mirrored { e.serverCreatedAt = t0 }
        if let coordinate {
            let c = TripCheckpointEntity(context: ctx)
            c.id = UUID(); c.timestamp = t0.addingTimeInterval(600)
            c.latitude = coordinate.latitude; c.longitude = coordinate.longitude
            c.trip = e
        }
        try? ctx.save()
        return id
    }

    func testCheckpointsWithoutPlaceAndSettingPlaceIdDoesNotFlipSync() {
        let tripId = trip(withCheckpointAt: jubga)
        let pending = repo.checkpointsWithoutPlace()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].tripId, tripId)
        let statusBefore = (try? pc.container.viewContext.fetch(TripEntity.fetchRequest()))?.first?.syncStatus
        repo.setPlaceId(forCheckpoint: pending[0].checkpoint.id, placeId: Place.id(forCell: "szgs0u4"))
        XCTAssertTrue(repo.checkpointsWithoutPlace().isEmpty)
        XCTAssertEqual(repo.fetchTripDetail(id: tripId)?.checkpoints.first?.placeId, Place.id(forCell: "szgs0u4"))
        let statusAfter = (try? pc.container.viewContext.fetch(TripEntity.fetchRequest()))?.first?.syncStatus
        XCTAssertEqual(statusAfter, statusBefore, "выведенный placeId не взводит pendingUpload")
        XCTAssertEqual(repo.checkpointCoordinates(placeId: Place.id(forCell: "szgs0u4")).count, 1)
    }

    func testTripPreviewsNeedingMatchAndMarking() {
        let done = trip(withCheckpointAt: nil)
        let open = trip(withCheckpointAt: nil, ended: false)
        XCTAssertEqual(Set(repo.tripPreviews(needingPlaceMatch: true).map(\.id)), [done], "незавершённая поездка не сверяется")
        repo.markPlacesMatched(tripId: done)
        XCTAssertTrue(repo.tripPreviews(needingPlaceMatch: true).isEmpty)
        XCTAssertEqual(repo.tripPreviews(needingPlaceMatch: false).map(\.id), [done])
        _ = open
    }

    func testDeletingATripForgetsItsPasses() {
        let tripId = trip(withCheckpointAt: nil)
        let place = UUID()
        store.replacePasses(placeId: place, tripId: tripId, with: [pass(place: place, trip: tripId, t: 100)])
        repo.deleteTrip(id: tripId)   // serverCreatedAt == nil → твёрдое удаление сразу
        XCTAssertTrue(store.passes(tripId: tripId).isEmpty)
    }

    /// Транспорт зовёт `deleteTripHard` НАПРЯМУЮ, мимо `deleteTrip` — при
    /// `tripNotFound` во время загрузки и после подтверждения удаления
    /// сервером. Оба пути должны забирать проезды тоже.
    func testHardDeleteFromTransportForgetsPasses() {
        let tripId = trip(withCheckpointAt: nil, mirrored: true)
        let place = UUID()
        store.replacePasses(placeId: place, tripId: tripId, with: [pass(place: place, trip: tripId, t: 100)])
        repo.deleteTripHard(id: tripId)
        XCTAssertTrue(store.passes(tripId: tripId).isEmpty)
    }
}
