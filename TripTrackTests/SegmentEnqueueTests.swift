import XCTest
import CoreData
@testable import TripTrack

/// Обёртка `TripManager.addSegment` ставит поездку в очередь синка — но
/// только когда отрезок ДЕЙСТВИТЕЛЬНО завёлся. Повтор той же пары
/// возвращает прежний отрезок и в базе не меняет ничего, а очередь про это
/// знать не умеет: операция прошла бы до сервера пустым апсертом.
///
/// Хранилище своё, in-memory: гейт синка читает `PersistenceController
/// .shared` напрямую, но только когда Cloud Sync ВЫКЛЮЧЕН — с включённым
/// `shouldEnqueue` пропускает всё первой строкой и в базу не ходит. Поэтому
/// здесь он включён, и общее хранилище (где чужие тесты стирают строки
/// пакетно) этому классу не нужно.
@MainActor
final class SegmentEnqueueTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var manager: TripManager!
    private var tripId: UUID!
    private var cloudSyncBefore = false

    override func setUp() {
        super.setUp()
        cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        SettingsManager.shared.cloudSyncEnabled = true
        SyncQueue.shared.clearAll()
        // Реального входа в аккаунт в юнит-тесте не поставить — гейт
        // авторизации подменяется, как в `JourneyPublishTests`.
        SyncEnqueuer.isAuthorizedToEnqueue = { true }
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        manager = TripManager(locationManager: LocationManager(), repository: repo)

        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        tripId = UUID()
        trip.id = tripId
        trip.startDate = Date()
        trip.endDate = Date()
        trip.isPrivate = false
        trip.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
    }

    /// XCTest держит экземпляры тестов до конца прогона: поле, не обнулённое
    /// здесь, тянет свою `NSManagedObjectModel` в чужие классы (см. «Ловушки»
    /// в CLAUDE.md — «Multiple NSEntityDescriptions claim TripEntity»).
    override func tearDown() {
        SyncQueue.shared.clearAll()
        SettingsManager.shared.cloudSyncEnabled = cloudSyncBefore
        SyncEnqueuer.isAuthorizedToEnqueue = { AuthService.shared.isSignedIn }
        manager = nil
        repo = nil
        pc = nil
        tripId = nil
        super.tearDown()
    }

    private func checkpoint(elapsed: TimeInterval) -> TripCheckpoint {
        let cp = TripCheckpoint(timestamp: Date().addingTimeInterval(elapsed), latitude: 45,
                                longitude: 38.9, distanceFromStart: elapsed * 10, elapsedFromStart: elapsed)
        guard let saved = repo.addCheckpoint(cp, to: tripId) else {
            XCTFail("отметка не сохранилась"); return cp
        }
        return saved
    }

    /// `enqueueTripUpdate` уходит в `Task { @MainActor in }` — короткая пауза
    /// даёт задаче прогнаться перед чтением очереди (приём `JourneyPublishTests`).
    private func settleDeferredEnqueue() async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    private var tripOps: Int {
        SyncQueue.shared.pending.filter { $0.entityType == .trip && $0.entityId == tripId }.count
    }

    func testNewSegmentEnqueuesTripUpdate() async throws {
        let a = checkpoint(elapsed: 60), b = checkpoint(elapsed: 3_600)

        XCTAssertNotNil(manager.addSegment(tripId: tripId, from: a.id, to: b.id))
        try await settleDeferredEnqueue()

        XCTAssertEqual(tripOps, 1)
    }

    func testDuplicatePairDoesNotEnqueueAgain() async throws {
        let a = checkpoint(elapsed: 60), b = checkpoint(elapsed: 3_600)
        let first = manager.addSegment(tripId: tripId, from: a.id, to: b.id)
        try await settleDeferredEnqueue()
        SyncQueue.shared.clearAll()

        // Та же пара, выбранная с другого конца, — тот же отрезок.
        let again = manager.addSegment(tripId: tripId, from: b.id, to: a.id)
        try await settleDeferredEnqueue()

        XCTAssertEqual(again?.id, first?.id)
        XCTAssertEqual(tripOps, 0, "дубль ничего не изменил — очередь трогать не за чем")
    }
}
