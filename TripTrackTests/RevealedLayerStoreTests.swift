import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Хранилище открытого мира: пишет только новое, читает готовое, а фоновая
/// сборка после обновления взводит флаг ТОЛЬКО сделав работу.
final class RevealedLayerStoreTests: XCTestCase {
    private var pc: PersistenceController!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: RevealedLayerStore!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        suiteName = "reveal-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = RevealedLayerStore(persistence: pc, defaults: defaults)
    }

    /// Каждое поле обнуляется: XCTest держит экземпляры до конца прогона, и
    /// незакрытая `PersistenceController(inMemory:)` тянет свою модель — в логе
    /// это «Multiple NSEntityDescriptions claim TripEntity» в ЧУЖОМ классе.
    override func tearDown() {
        store = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        pc = nil
        super.tearDown()
    }

    // MARK: - Фикстуры

    @discardableResult
    private func makeTrip(
        northMetres: Double,
        from origin: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753),
        endDate: Date = Date(),
        withPreview: Bool = true
    ) -> UUID {
        let context = pc.container.viewContext
        let entity = TripEntity(context: context)
        let id = UUID()
        entity.id = id
        entity.startDate = endDate.addingTimeInterval(-1_800)
        entity.endDate = endDate
        entity.syncStatus = SyncStatus.synced.rawValue
        if withPreview {
            let coords = (0..<3).map { i -> CLLocationCoordinate2D in
                let t = Double(i) / 2
                return CLLocationCoordinate2D(
                    latitude: origin.latitude + (northMetres * t) / 111_320.0,
                    longitude: origin.longitude
                )
            }
            entity.previewPolyline = Trip.encodePolyline(coords)
        }
        try? context.save()
        return id
    }

    private func storedTileCount() -> Int {
        let request: NSFetchRequest<RevealedCellEntity> = RevealedCellEntity.fetchRequest()
        return (try? pc.container.viewContext.count(for: request)) ?? 0
    }

    // MARK: - Финиш поездки

    func testIngestWritesTilesAndReturnsNewCells() {
        let id = makeTrip(northMetres: 3_000)
        let added = store.ingest(tripId: id)

        XCTAssertGreaterThan(added, 30, "три километра — это десятки ячеек по 75 м")
        XCTAssertGreaterThan(store.tiles().count, 0)
        let cells = store.tiles().reduce(0) { $0 + $1.cellSet.count }
        XCTAssertEqual(cells, added)
    }

    func testSecondIngestOfTheSameTripOpensNothing() {
        let id = makeTrip(northMetres: 3_000)
        let first = store.ingest(tripId: id)
        let tilesAfterFirst = storedTileCount()

        XCTAssertEqual(store.ingest(tripId: id), 0)
        XCTAssertEqual(storedTileCount(), tilesAfterFirst)
        let cells = store.tiles().reduce(0) { $0 + $1.cellSet.count }
        XCTAssertEqual(cells, first, "повторный финиш не удваивает открытое")
    }

    func testTripWithoutPreviewIsSkipped() {
        let id = makeTrip(northMetres: 3_000, withPreview: false)
        XCTAssertEqual(store.ingest(tripId: id), 0)
        XCTAssertEqual(storedTileCount(), 0)
    }

    func testTwoTripsInOneTileMerge() {
        let origin = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)
        let east = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9773)
        let a = makeTrip(northMetres: 600, from: origin)
        let b = makeTrip(northMetres: 600, from: east)

        let first = store.ingest(tripId: a)
        let second = store.ingest(tripId: b)
        XCTAssertGreaterThan(second, 0, "соседняя улица — тоже открытие")

        let tiles = store.tiles()
        XCTAssertEqual(tiles.count, 1, "две улицы одного квартала — один тайл")
        XCTAssertEqual(tiles[0].cellSet.count, first + second)
        XCTAssertGreaterThanOrEqual(tiles[0].runs.count, 2)
    }

    // MARK: - Снимок

    func testLayerReadsWhatIngestWrote() {
        let id = makeTrip(northMetres: 3_000)
        store.ingest(tripId: id)

        let layer = store.layer()
        XCTAssertFalse(layer.fine.isEmpty)
        XCTAssertLessThanOrEqual(layer.mid.count, layer.fine.count)
        XCTAssertEqual(layer.openedKm, 3.0, accuracy: 0.4)
        XCTAssertGreaterThan(layer.cellCount, 30)
    }

    /// Временной туман — состояние ОДНОГО экрана. Он считается на лету и в
    /// базу не пишет ничего: иначе открытие старой поездки переписывало бы мир.
    func testLayerBeforeDateDoesNotWrite() {
        let old = Date().addingTimeInterval(-86_400 * 10)
        makeTrip(northMetres: 3_000, endDate: old)
        makeTrip(northMetres: 3_000, from: CLLocationCoordinate2D(latitude: 46.0, longitude: 39.5))

        let layer = store.layer(before: old.addingTimeInterval(60))
        XCTAssertFalse(layer.fine.isEmpty)
        XCTAssertEqual(storedTileCount(), 0, "снимок на дату ничего не сохраняет")

        let now = store.layer(before: Date())
        XCTAssertGreaterThan(now.cellCount, layer.cellCount, "вторая поездка открыла ещё")
    }

    // MARK: - Фоновая сборка

    /// Ловушка `backfillIfNeeded`: «поездок нет» на запуске, потерявшем стор,
    /// означает «данные ещё не вернулись». Залатчить там значит оставить карту
    /// пустой навсегда.
    func testRebuildDoesNotLatchOnAnEmptyLibrary() async {
        await store.rebuildIfNeeded()
        XCTAssertFalse(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey))
        XCTAssertEqual(storedTileCount(), 0)
    }

    func testRebuildLatchesAfterRealWork() async {
        makeTrip(northMetres: 3_000)
        await store.rebuildIfNeeded()

        XCTAssertTrue(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey))
        XCTAssertGreaterThan(storedTileCount(), 0)
    }

    func testRebuildRunsAfterTheLibraryComesBack() async {
        await store.rebuildIfNeeded()
        makeTrip(northMetres: 3_000)
        await store.rebuildIfNeeded()

        XCTAssertTrue(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey))
        XCTAssertGreaterThan(storedTileCount(), 0)
    }

    func testRebuildIsSkippedOnceLatched() async {
        makeTrip(northMetres: 3_000)
        await store.rebuildIfNeeded()
        let cells = store.tiles().reduce(0) { $0 + $1.cellSet.count }

        makeTrip(northMetres: 3_000, from: CLLocationCoordinate2D(latitude: 46.0, longitude: 39.5))
        await store.rebuildIfNeeded()

        XCTAssertEqual(store.tiles().reduce(0) { $0 + $1.cellSet.count }, cells,
                       "сборка после обновления — один раз; новые поездки приносит финиш")
    }

    // MARK: - Стирание

    func testWipeClearsTilesAndTheLatch() async {
        makeTrip(northMetres: 3_000)
        await store.rebuildIfNeeded()
        XCTAssertGreaterThan(storedTileCount(), 0)

        store.wipe()

        XCTAssertEqual(storedTileCount(), 0)
        XCTAssertFalse(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey),
                       "после стирания сборка обязана быть возможна снова")
    }
}
