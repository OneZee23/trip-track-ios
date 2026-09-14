import XCTest
import CoreData
@testable import TripTrack

/// Публикация путешествия (0.6.8): плечи открываются каждое своим апсертом,
/// путешествие становится публичным ПОСЛЕ них. Самое рискованное место
/// версии (спека §5) — публикация флипает приватность нескольких поездок
/// одним действием, и «ни одна поездка не становится публичной без своего
/// апсерта» здесь проверяется буквально: по операции синка на каждое
/// открытое плечо.
///
/// Хранилище ОБЩЕЕ (`PersistenceController.shared`), а не изолированное
/// in-memory, — вынужденно: гейт синка (`SyncEnqueuer.fetchTripEntity`/
/// `fetchJourneyEntity`) читает его напрямую и подменить нечем (тот же
/// приём, что у `VehicleDashboardUnitsWireTests`). Строки заводятся руками
/// и руками убираются в `tearDown`.
@MainActor
final class JourneyPublishTests: XCTestCase {
    private var repo: CoreDataTripRepository!
    private var tripManager: TripManager!
    private var manager: JourneyManager!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private var cloudSyncBefore = false
    private var insertedTripIds: [UUID] = []
    private var insertedJourneyIds: [UUID] = []

    override func setUp() {
        super.setUp()
        cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        SettingsManager.shared.cloudSyncEnabled = false
        SyncQueue.shared.clearAll()
        // `SyncEnqueuer.enqueue` также требует подписанного в аккаунт
        // человека — реального входа в юнит-тесте не поставить без живого
        // POST'а, так что гейт авторизации подменяется, а гейт приватности
        // (собственно то, что здесь проверяется) остаётся настоящим.
        SyncEnqueuer.isAuthorizedToEnqueue = { true }
        repo = CoreDataTripRepository()
        tripManager = TripManager(locationManager: LocationManager(), repository: repo)
        manager = JourneyManager(repository: repo)
    }

    override func tearDown() {
        let ctx = PersistenceController.shared.container.viewContext
        for id in insertedJourneyIds {
            let req: NSFetchRequest<JourneyEntity> = JourneyEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? ctx.fetch(req).first { ctx.delete(entity) }
        }
        for id in insertedTripIds {
            let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? ctx.fetch(req).first { ctx.delete(entity) }
        }
        try? ctx.save()
        insertedJourneyIds = []
        insertedTripIds = []
        SyncQueue.shared.clearAll()
        SettingsManager.shared.cloudSyncEnabled = cloudSyncBefore
        SyncEnqueuer.isAuthorizedToEnqueue = { AuthService.shared.isSignedIn }
        manager = nil
        tripManager = nil
        repo = nil
        super.tearDown()
    }

    @discardableResult
    private func trip(daysFromT0 d: Double, isPrivate: Bool, km: Double = 100) -> UUID {
        let ctx = PersistenceController.shared.container.viewContext
        let e = TripEntity(context: ctx)
        let id = UUID()
        e.id = id
        e.startDate = t0.addingTimeInterval(d * 86_400)
        e.endDate = e.startDate!.addingTimeInterval(3_600)
        e.distance = km * 1_000
        e.isPrivate = isPrivate
        try? ctx.save()
        insertedTripIds.append(id)
        return id
    }

    private func fetchTrip(_ id: UUID) -> Trip {
        // Force-unwrap: тестовая опора, а не восстановимая ошибка — если
        // поездки нет, тест-хелпер сам сломан.
        repo.fetchAllTrips().first(where: { $0.id == id })!
    }

    /// `TripManager.updatePrivacy` ставит энкью в `Task { @MainActor in }`
    /// (`TripRepository.updatePrivacy`) — не синхронно. Короткая пауза даёт
    /// этим задачам реально прогнаться перед тем, как тест читает очередь,
    /// тем же приёмом, что `SyncQueueTests` использует для батч-отправки.
    private func settleDeferredEnqueue() async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    func testPublishFlipsEachPrivateLegThroughItsOwnUpsert() async throws {
        let a = trip(daysFromT0: 0, isPrivate: true), b = trip(daysFromT0: 1, isPrivate: true), c = trip(daysFromT0: 2, isPrivate: false)
        let j = try manager.create(from: [fetchTrip(a), fetchTrip(b), fetchTrip(c)], title: "Грузия")
        insertedJourneyIds.append(j.id)
        XCTAssertEqual(manager.privateLegs(in: j).map(\.id).sorted(), [a, b].sorted())

        try manager.publish(id: j.id, tripManager: tripManager)
        try await settleDeferredEnqueue()

        for id in [a, b, c] { XCTAssertFalse(fetchTrip(id).isPrivate) }
        // Никакая поездка не становится публичной без своего апсерта: по операции на каждое ОТКРЫТОЕ плечо.
        let tripOps = SyncQueue.shared.pending.filter { $0.entityType == .trip }
        XCTAssertEqual(Set(tripOps.map(\.entityId)), Set([a, b]))
        let journey = try XCTUnwrap(manager.journeys.first { $0.id == j.id })
        XCTAssertFalse(journey.isPrivate)
        XCTAssertTrue(SyncQueue.shared.pending.contains { $0.entityType == .journey && $0.entityId == j.id })
    }

    func testHideLeavesLegsAlone() async throws {
        let a = trip(daysFromT0: 0, isPrivate: true)
        let j = try manager.create(from: [fetchTrip(a)], title: nil)
        insertedJourneyIds.append(j.id)
        try manager.publish(id: j.id, tripManager: tripManager)
        try await settleDeferredEnqueue()
        SyncQueue.shared.clearAll()

        manager.hide(id: j.id)

        let hidden = try XCTUnwrap(manager.journeys.first { $0.id == j.id })
        XCTAssertTrue(hidden.isPrivate)
        XCTAssertFalse(fetchTrip(a).isPrivate)  // обратное несимметрично
        XCTAssertTrue(SyncQueue.shared.pending.contains { $0.entityType == .journey && $0.action == .unpublish })
    }
}
