import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Дверь пула в открытый мир: поездка, приехавшая `/sync/pull`, обязана
/// получить туман в ТОМ ЖЕ сеансе, а сверка — не перебирать библиотеку заново
/// на каждом заходе в приложение.
@MainActor
final class RevealedLayerSyncTests: XCTestCase {
    private var pc: PersistenceController!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: RevealedLayerStore!
    private var sync: RevealedLayerSync!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        suiteName = "reveal-sync-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = RevealedLayerStore(persistence: pc, defaults: defaults)
    }

    /// Каждое поле обнуляется: XCTest держит экземпляры до конца прогона, и
    /// незакрытая `PersistenceController(inMemory:)` тянет свою модель — в логе
    /// это «Multiple NSEntityDescriptions claim TripEntity» в ЧУЖОМ классе.
    override func tearDown() {
        sync = nil
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
        from origin: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753),
        lastModifiedAt: Date = Date()
    ) -> UUID {
        let context = pc.container.viewContext
        let entity = TripEntity(context: context)
        let id = UUID()
        entity.id = id
        entity.startDate = Date().addingTimeInterval(-1_800)
        entity.endDate = Date()
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.lastModifiedAt = lastModifiedAt
        entity.serverCreatedAt = lastModifiedAt
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

    private var stamp: Date? { defaults.object(forKey: RevealedLayerStore.lastIngestKey) as? Date }

    // MARK: - Пул

    /// Проба 3 расследования 15 сен: запуск проходит миграции на пустой
    /// библиотеке, пул приносит поездки — и до этой двери они не получали
    /// тумана весь сеанс (а с прежним безусловным латчем — никогда).
    func testPulledTripReachesTheStoreWithinTheSession() async {
        await store.rebuildIfNeeded()
        XCTAssertEqual(storedTileCount(), 0, "запуск: библиотека ещё не приехала")
        sync = RevealedLayerSync(store: store)

        let opened = expectation(forNotification: .revealedLayerChanged, object: nil)
        makePulledTrip()
        NotificationCenter.default.post(name: .syncPullCompleted, object: nil)
        await fulfillment(of: [opened], timeout: 5)
        await sync.settle()

        let tiles = await store.tiles()
        XCTAssertGreaterThan(tiles.count, 0)
        XCTAssertGreaterThan(tiles.reduce(0) { $0 + $1.cellSet.count }, 30)
    }

    // MARK: - Отметка

    /// Без отметки сверка перебирала бы всю библиотеку на каждом пуле.
    func testReconcileSkipsTripsOlderThanTheStamp() async {
        defaults.set(Date(), forKey: RevealedLayerStore.lastIngestKey)
        makePulledTrip(lastModifiedAt: Date().addingTimeInterval(-86_400 * 10))

        let outcome = await store.reconcile()

        XCTAssertEqual(outcome, .done(trips: 0, cells: 0))
        XCTAssertEqual(storedTileCount(), 0)
    }

    func testReconcileTakesTripsChangedAfterTheStamp() async {
        defaults.set(Date().addingTimeInterval(-86_400 * 10), forKey: RevealedLayerStore.lastIngestKey)
        makePulledTrip(lastModifiedAt: Date())

        let outcome = await store.reconcile()

        guard case let .done(trips, cells) = outcome else { return XCTFail("сверка не прошла") }
        XCTAssertEqual(trips, 1)
        XCTAssertGreaterThan(cells, 30)
        XCTAssertGreaterThan(storedTileCount(), 0)
    }

    /// Первый заход — отметки нет вовсе: библиотека берётся целиком, ради этого
    /// дверь и делалась (69 поездок владельца приехали пулом).
    func testFirstReconcileSweepsTheWholeLibrary() async {
        makePulledTrip(from: CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753))
        makePulledTrip(from: CLLocationCoordinate2D(latitude: 46.5, longitude: 39.5))
        makePulledTrip(from: CLLocationCoordinate2D(latitude: 43.1, longitude: 40.2))

        let outcome = await store.reconcile()

        let cells = await cellCount()
        XCTAssertEqual(outcome, .done(trips: 3, cells: cells))
        XCTAssertGreaterThanOrEqual(storedTileCount(), 3)
    }

    /// Отметка двигается ПОСЛЕ сохранения и только вперёд.
    func testStampAdvancesToTheNewestIngestedTrip() async {
        let older = Date().addingTimeInterval(-7_200)
        let newer = Date().addingTimeInterval(-60)
        makePulledTrip(from: CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753),
                       lastModifiedAt: older)
        makePulledTrip(from: CLLocationCoordinate2D(latitude: 46.5, longitude: 39.5),
                       lastModifiedAt: newer)

        await store.reconcile()

        XCTAssertEqual(stamp?.timeIntervalSince1970 ?? 0, newer.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Финиш своей поездки двигает ту же отметку: иначе пул через секунду после
    /// него разбирал бы её заново.
    func testFinishAdvancesTheSameStamp() async {
        let modified = Date().addingTimeInterval(-30)
        let id = makePulledTrip(lastModifiedAt: modified)

        await store.ingest(tripId: id)

        XCTAssertEqual(stamp?.timeIntervalSince1970 ?? 0, modified.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Повторная сверка не открывает ничего: ячейки идемпотентны.
    func testSecondReconcileOpensNothing() async {
        makePulledTrip()
        await store.reconcile()
        let cells = await cellCount()

        let outcome = await store.reconcile()

        guard case let .done(_, opened) = outcome else { return XCTFail("сверка не прошла") }
        XCTAssertEqual(opened, 0)
        let after = await cellCount()
        XCTAssertEqual(after, cells)
    }

    /// Пул поверх стартовой сверки — обычное дело: второй проход выходит сразу,
    /// а не считает ту же библиотеку вторым потоком.
    func testOverlappingReconcileExits() async {
        for i in 0..<20 {
            makePulledTrip(from: CLLocationCoordinate2D(latitude: 45.0 + Double(i) * 0.2, longitude: 38.9))
        }

        async let first = store.reconcile()
        async let second = store.reconcile()
        let outcomes = await [first, second]

        XCTAssertEqual(outcomes.filter { $0 == .busy }.count, 1, "работает ровно одна сверка")
    }

    private func cellCount() async -> Int {
        await store.tiles().reduce(0) { $0 + $1.cellSet.count }
    }
}
