import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Дверь пула в открытый мир: поездка, приехавшая `/sync/pull`, обязана
/// получить туман в ТОМ ЖЕ сеансе, а разбирается ровно то, что пул привёз, —
/// по списку id, а не по окну времени.
@MainActor
final class RevealedLayerSyncTests: XCTestCase {
    private var pc: PersistenceController!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: RevealedLayerStore!
    private var sync: RevealedLayerSync!
    /// Свой центр уведомлений: пост в общий разбудил бы продакшен-синглтоны
    /// поверх `PersistenceController.shared` — тот самый чужой хвост.
    private var center: NotificationCenter!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        suiteName = "reveal-sync-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = RevealedLayerStore(persistence: pc, defaults: defaults)
        center = NotificationCenter()
    }

    /// Каждое поле обнуляется: XCTest держит экземпляры до конца прогона, и
    /// незакрытая `PersistenceController(inMemory:)` тянет свою модель — в логе
    /// это «Multiple NSEntityDescriptions claim TripEntity» в ЧУЖОМ классе.
    override func tearDown() {
        sync = nil
        center = nil
        store = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        pc = nil
        super.tearDown()
    }

    // MARK: - Фикстуры

    /// Ровно то, чем поездка пула и является: строка с превью и БЕЗ единой
    /// точки трека (`applyRemoteTrip` кладёт `previewPolyline`, точки пул не
    /// везёт вовсе).
    @discardableResult
    private func makePulledTrip(
        northMetres: Double = 3_000,
        from origin: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)
    ) -> UUID {
        let context = pc.container.viewContext
        let entity = TripEntity(context: context)
        let id = UUID()
        entity.id = id
        entity.startDate = Date().addingTimeInterval(-1_800)
        entity.endDate = Date()
        entity.syncStatus = SyncStatus.synced.rawValue
        let coords = (0..<3).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / 2
            return CLLocationCoordinate2D(
                latitude: origin.latitude + (northMetres * t) / 111_320.0,
                longitude: origin.longitude
            )
        }
        entity.previewPolyline = Trip.encodePolyline(coords)
        try? context.save()
        return id
    }

    private func storedTileCount() -> Int {
        let request: NSFetchRequest<RevealedCellEntity> = RevealedCellEntity.fetchRequest()
        return (try? pc.container.viewContext.count(for: request)) ?? 0
    }

    private func cellCount() async -> Int {
        await store.tiles().reduce(0) { $0 + $1.cellSet.count }
    }

    private func postPull(appliedTripIds: [UUID]?) {
        center.post(
            name: .syncPullCompleted,
            object: nil,
            userInfo: appliedTripIds.map { [SyncPullNotification.appliedTripIds: $0] }
        )
    }

    // MARK: - Пул

    /// Проба 3 расследования 15 сен: запуск проходит миграции на пустой
    /// библиотеке, пул приносит поездки — и до этой двери они не получали
    /// тумана весь сеанс (а с прежним безусловным латчем — никогда).
    func testPulledTripReachesTheStoreWithinTheSession() async {
        await store.rebuildIfNeeded()
        XCTAssertEqual(storedTileCount(), 0, "запуск: библиотека ещё не приехала")
        sync = RevealedLayerSync(store: store, center: center)

        let opened = expectation(forNotification: .revealedLayerChanged, object: nil)
        let id = makePulledTrip()
        postPull(appliedTripIds: [id])
        await fulfillment(of: [opened], timeout: 5)
        await sync.settle()

        let tiles = await store.tiles()
        XCTAssertGreaterThan(tiles.count, 0)
        XCTAssertGreaterThan(tiles.reduce(0) { $0 + $1.cellSet.count }, 30)
    }

    /// Уведомление БЕЗ ключа — «неизвестно, что приехало»: полный проход.
    /// Так выглядит чужой постер и старый бинарник.
    func testPullWithoutIdsSweepsTheWholeLibrary() async {
        sync = RevealedLayerSync(store: store, center: center)
        makePulledTrip(from: CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753))
        makePulledTrip(from: CLLocationCoordinate2D(latitude: 46.5, longitude: 39.5))

        let opened = expectation(forNotification: .revealedLayerChanged, object: nil)
        postPull(appliedTripIds: nil)
        await fulfillment(of: [opened], timeout: 5)
        await sync.settle()

        let layer = await store.layer()
        XCTAssertEqual(layer.openedKm, 6.0, accuracy: 0.8, "обе поездки разобраны")
    }

    func testRequestFromNotificationReadsTheIds() {
        let id = UUID()
        let withIds = Notification(
            name: .syncPullCompleted, object: nil,
            userInfo: [SyncPullNotification.appliedTripIds: [id]]
        )
        let withoutIds = Notification(name: .syncPullCompleted, object: nil, userInfo: nil)

        XCTAssertEqual(RevealedLayerSync.request(from: withIds), .ids([id]))
        XCTAssertEqual(RevealedLayerSync.request(from: withoutIds), .full)
    }

    // MARK: - Разбирается ровно привезённое

    func testOnlyTheAppliedTripsAreIngested() async {
        let pulled = makePulledTrip(from: CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753))
        makePulledTrip(from: CLLocationCoordinate2D(latitude: 46.5, longitude: 39.5))

        let outcome = await store.reconcile(.ids([pulled]))

        let cells = await cellCount()
        XCTAssertEqual(outcome, .done(trips: 1, cells: cells))
        let layer = await store.layer()
        XCTAssertEqual(layer.openedKm, 3.0, accuracy: 0.4, "вторая поездка пулом не приезжала")
    }

    /// Пустой список — «пул ничего не привёз», и это НЕ повод идти по
    /// библиотеке: иначе каждый заход в приложение стоил бы полного прохода.
    func testEmptyPullDoesNothing() async {
        makePulledTrip()

        let outcome = await store.reconcile(.ids([]))

        XCTAssertEqual(outcome, .done(trips: 0, cells: 0))
        XCTAssertEqual(storedTileCount(), 0)
    }

    /// Повторная сверка не открывает ничего: ячейки идемпотентны.
    func testSecondReconcileOpensNothing() async {
        let id = makePulledTrip()
        await store.reconcile(.ids([id]))
        let cells = await cellCount()

        let outcome = await store.reconcile(.ids([id]))

        XCTAssertEqual(outcome, .done(trips: 1, cells: 0))
        let after = await cellCount()
        XCTAssertEqual(after, cells)
    }

    // MARK: - Очередь

    func testMergedRequestUnionsIds() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(RevealedLayerStore.ReconcileRequest.merged(nil, .ids([a])), .ids([a]))
        XCTAssertEqual(RevealedLayerStore.ReconcileRequest.merged(.ids([a]), .ids([b])), .ids([a, b]))
        XCTAssertEqual(RevealedLayerStore.ReconcileRequest.merged(.ids([a]), .full), .full)
        XCTAssertEqual(RevealedLayerStore.ReconcileRequest.merged(.full, .ids([a])), .full)
        XCTAssertEqual(RevealedLayerStore.ReconcileRequest.merged(nil, .full), .full)
    }

    /// Пул, пришедший во время идущей сверки, обязан быть разобран — его
    /// строки легли в базу уже ПОСЛЕ того, как идущий проход выбрал превью.
    /// Шлагбаум держит тест, а не скорость машины.
    func testQueuedPullIsRunAfterTheCurrentPass() async {
        let gate = PassGate()
        store = RevealedLayerStore(persistence: pc, defaults: defaults,
                                   beforePass: { await gate.wait() })
        let first = makePulledTrip(from: CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753))
        let running = Task { await self.store.reconcile(.ids([first])) }
        await gate.waitUntilArrived()

        // Второй пул приезжает, пока первый проход стоит у шлагбаума.
        let second = makePulledTrip(from: CLLocationCoordinate2D(latitude: 46.5, longitude: 39.5))
        let queued = await store.reconcile(.ids([second]))
        XCTAssertEqual(queued, .queued)

        await gate.open()
        let outcome = await running.value

        let cells = await cellCount()
        XCTAssertEqual(outcome, .done(trips: 2, cells: cells),
                       "оба прохода сделаны одной задачей")
        let layer = await store.layer()
        XCTAssertEqual(layer.openedKm, 6.0, accuracy: 0.8, "поездка второго пула не потеряна")
    }
}

/// Шлагбаум перед проходом сверки: первый проход встаёт и сообщает об этом,
/// открывается — навсегда.
private actor PassGate {
    private var opened = false
    private var arrived = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrival: CheckedContinuation<Void, Never>?

    func wait() async {
        if !arrived {
            arrived = true
            arrival?.resume()
            arrival = nil
        }
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilArrived() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
