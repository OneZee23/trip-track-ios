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

    /// Прямая под 45° к сетке ячеек, длиной `metres` по земле. Широта и
    /// долгота растут вместе, с поправкой на косинус — иначе «диагональ» на
    /// широте Краснодара легла бы под 35°.
    private func makeDiagonalTrip(
        metres: Double,
        from origin: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)
    ) -> UUID {
        let context = pc.container.viewContext
        let entity = TripEntity(context: context)
        let id = UUID()
        entity.id = id
        entity.startDate = Date().addingTimeInterval(-3_600)
        entity.endDate = Date()
        entity.syncStatus = SyncStatus.synced.rawValue
        let leg = metres / 2.0.squareRoot()
        let lonScale = cos(origin.latitude * .pi / 180)
        // Точки через 200 м: превью настоящей поездки упрощено примерно так же,
        // а `RevealGrid.walkCells` всё равно проходит отрезок шагом в треть ячейки.
        let steps = max(2, Int(metres / 200))
        let coords = (0...steps).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / Double(steps)
            return CLLocationCoordinate2D(
                latitude: origin.latitude + leg * t / 111_320.0,
                longitude: origin.longitude + leg * t / (111_320.0 * lonScale)
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

    // MARK: - Финиш поездки

    func testIngestWritesTilesAndReturnsNewCells() async {
        let id = makeTrip(northMetres: 3_000)
        let added = await store.ingest(tripId: id).openedCells

        XCTAssertGreaterThan(added, 30, "три километра — это десятки ячеек по 75 м")
        let tiles = await store.tiles()
        XCTAssertGreaterThan(tiles.count, 0)
        let cells = tiles.reduce(0) { $0 + $1.cellSet.count }
        XCTAssertEqual(cells, added)
    }

    func testSecondIngestOfTheSameTripOpensNothing() async {
        let id = makeTrip(northMetres: 3_000)
        let first = await store.ingest(tripId: id).openedCells
        let tilesAfterFirst = storedTileCount()

        let again = await store.ingest(tripId: id).openedCells
        XCTAssertEqual(again, 0)
        XCTAssertEqual(storedTileCount(), tilesAfterFirst)
        let cells = await store.tiles().reduce(0) { $0 + $1.cellSet.count }
        XCTAssertEqual(cells, first, "повторный финиш не удваивает открытое")
    }

    func testTripWithoutPreviewIsSkipped() async {
        let id = makeTrip(northMetres: 3_000, withPreview: false)
        let added = await store.ingest(tripId: id).openedCells
        XCTAssertEqual(added, 0)
        XCTAssertEqual(storedTileCount(), 0)
    }

    func testTwoTripsInOneTileMerge() async {
        let origin = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)
        let east = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9773)
        let a = makeTrip(northMetres: 600, from: origin)
        let b = makeTrip(northMetres: 600, from: east)

        let first = await store.ingest(tripId: a).openedCells
        let second = await store.ingest(tripId: b).openedCells
        XCTAssertGreaterThan(second, 0, "соседняя улица — тоже открытие")

        let tiles = await store.tiles()
        XCTAssertEqual(tiles.count, 1, "две улицы одного квартала — один тайл")
        XCTAssertEqual(tiles[0].cellSet.count, first + second)
        XCTAssertGreaterThanOrEqual(tiles[0].runs.count, 2)
    }

    // MARK: - Дельта финиша

    /// Километры дельты — это длина ДОРИСОВАННЫХ прогонов, а не число ячеек на
    /// их сторону. Трёхкилометровая прямая по нетронутому месту даёт три
    /// километра; второй такой же финиш — ноль, а не ещё три.
    func testDeltaCountsKilometresAlongTheRunsItPainted() async {
        let id = makeTrip(northMetres: 3_000)
        let delta = await store.ingest(tripId: id)

        XCTAssertGreaterThan(delta.openedCells, 30)
        XCTAssertEqual(delta.openedKm, 3.0, accuracy: 0.09, "3 км прямой — это 3 км нового пути")

        let again = await store.ingest(tripId: id)
        XCTAssertEqual(again, .none, "поездка по уже открытому не открывает ничего")
    }

    /// Дорога ПОД УГЛОМ к сетке ячеек — тот случай, на котором счёт по ячейкам
    /// врал в полтора раза: ячеек под 45° набирается ≈√2 на километр пути.
    ///
    /// И второе, ради чего этот тест написан: на сколько подрастает шапка
    /// «Атласа», ровно столько же и говорит дельта. Два числа человек видит на
    /// одном экране и вычитает глазами.
    func testDiagonalStreetAgreesWithTheAtlasHeader() async {
        let before = await store.layer().openedKm
        let id = makeDiagonalTrip(metres: 10_000)

        let delta = await store.ingest(tripId: id)
        let after = await store.layer().openedKm

        XCTAssertEqual(delta.openedKm, 10.0, accuracy: 0.3, "десять километров по диагонали")
        XCTAssertEqual(after - before, delta.openedKm, accuracy: 0.3,
                       "шапка «Атласа» и дельта финиша считают одно и то же")
    }

    /// Регион считается новым по ячейкам, которые ЛЕГЛИ, а не по треку: второй
    /// проезд по тому же краю новым его не объявляет.
    func testNewRegionIsReportedOnceAndOnlyForFreshCells() async {
        let counted = RevealedLayerStore(
            persistence: pc, defaults: defaults, regionId: { _ in "RU-KDA" })
        let first = await counted.ingest(tripId: makeTrip(northMetres: 3_000))
        XCTAssertEqual(first.newRegionIds, ["RU-KDA"])

        let second = await counted.ingest(tripId: makeTrip(
            northMetres: 600,
            from: CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9773)))
        XCTAssertGreaterThan(second.openedCells, 0, "соседняя улица открылась")
        XCTAssertTrue(second.newRegionIds.isEmpty, "а край уже был не новым")
    }

    /// Край, открытый поездкой со второго телефона (пул → `reconcile`), на
    /// «Атласе» уже светится — и свой проезд по нему новым его не объявляет.
    func testARegionOpenedByAPulledTripIsNotNewLater() async {
        let counted = RevealedLayerStore(
            persistence: pc, defaults: defaults, regionId: { _ in "RU-KDA" })
        // Поездка приехала пулом: строки легли в базу мимо финиша.
        makeTrip(northMetres: 3_000)
        let outcome = await counted.reconcile(.full)
        guard case let .done(_, cells) = outcome else { return XCTFail("сверка не прошла") }
        XCTAssertGreaterThan(cells, 0, "пул что-то открыл")

        // А теперь своя поездка по тому же краю, соседней улицей.
        let mine = makeTrip(
            northMetres: 600,
            from: CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9773))
        let delta = await counted.ingest(tripId: mine)
        XCTAssertGreaterThan(delta.openedCells, 0, "соседняя улица открылась")
        XCTAssertTrue(delta.newRegionIds.isEmpty,
                      "край уже был открыт пулом — поздравлять человека нечем")
    }

    /// Стирание аккаунта забирает и регионы: иначе вернувшиеся синком поездки
    /// не дали бы ни одного нового края.
    func testWipeForgetsTheRegionsToo() async {
        let counted = RevealedLayerStore(
            persistence: pc, defaults: defaults, regionId: { _ in "RU-KDA" })
        _ = await counted.ingest(tripId: makeTrip(northMetres: 3_000))
        XCTAssertNotNil(defaults.stringArray(forKey: RevealedLayerStore.regionsKey))

        counted.wipe()
        XCTAssertNil(defaults.stringArray(forKey: RevealedLayerStore.regionsKey))
    }

    // MARK: - Снимок

    func testLayerReadsWhatIngestWrote() async {
        let id = makeTrip(northMetres: 3_000)
        await store.ingest(tripId: id)

        let layer = await store.layer()
        XCTAssertFalse(layer.fine.polylines.isEmpty)
        XCTAssertEqual(layer.mid.polylines.count, layer.fine.polylines.count)
        XCTAssertEqual(layer.openedKm, 3.0, accuracy: 0.4)
        XCTAssertGreaterThan(layer.cellCount, 30)
    }

    /// Временной туман — состояние ОДНОГО экрана. Он считается на лету и в
    /// базу не пишет ничего: иначе открытие старой поездки переписывало бы мир.
    func testLayerBeforeDateDoesNotWrite() async {
        let old = Date().addingTimeInterval(-86_400 * 10)
        makeTrip(northMetres: 3_000, endDate: old)
        makeTrip(northMetres: 3_000, from: CLLocationCoordinate2D(latitude: 46.0, longitude: 39.5))

        let layer = await store.layer(before: old.addingTimeInterval(60))
        XCTAssertFalse(layer.fine.polylines.isEmpty)
        XCTAssertEqual(storedTileCount(), 0, "снимок на дату ничего не сохраняет")

        let now = await store.layer(before: Date())
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

    /// Взведённый латч над ПУСТЫМ хранилищем открывается обратно.
    ///
    /// Само по себе это состояние не заводится: латч пишется только после
    /// `total > 0`, а стирание идёт ДО него, так что смерть процесса посреди
    /// сборки оставляет латч открытым. Но ячейки живут в CoreData, а латч — в
    /// `UserDefaults`, и разъехаться этим двум хранилищам есть чем
    /// (пересоздание стора, ручная чистка, будущая миграция). Поймано на
    /// симуляторе 17 сентября: поездки на месте, «0 км открыто», латч взведён,
    /// и лечилось это только переустановкой приложения.
    func testArmedLatchOverAnEmptyStoreReopensItself() async {
        makeTrip(northMetres: 3_000)
        await store.rebuildIfNeeded()
        XCTAssertGreaterThan(storedTileCount(), 0)

        // Ячейки ушли мимо латча — ровно то состояние, которое было на
        // телефоне.
        store.wipe()
        defaults.set(true, forKey: RevealedLayerStore.rebuildFlagKey)
        XCTAssertEqual(storedTileCount(), 0)

        await store.rebuildIfNeeded()
        XCTAssertGreaterThan(storedTileCount(), 0,
                             "пустое хранилище при взведённом латче обязано пересобраться")
        XCTAssertTrue(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey))
    }

    /// И НЕ пересобирается, когда работать не с чем: пустая библиотека при
    /// взведённом латче оставляет всё как есть, а не крутит сборку на каждом
    /// запуске.
    func testArmedLatchOverAnEmptyStoreWithNoTripsStaysQuiet() async {
        defaults.set(true, forKey: RevealedLayerStore.rebuildFlagKey)
        await store.rebuildIfNeeded()
        XCTAssertEqual(storedTileCount(), 0)
        XCTAssertTrue(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey))
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
        let cells = await store.tiles().reduce(0) { $0 + $1.cellSet.count }

        makeTrip(northMetres: 3_000, from: CLLocationCoordinate2D(latitude: 46.0, longitude: 39.5))
        await store.rebuildIfNeeded()

        let after = await store.tiles().reduce(0) { $0 + $1.cellSet.count }
        XCTAssertEqual(after, cells,
                       "сборка после обновления — один раз; новые поездки приносит финиш")
    }

    /// Проба 1 расследования 15 сен: библиотека ЕСТЬ, превью ещё нет —
    /// строки пула приезжают раньше разобранного превью. Прежняя проверка
    /// «выборка не пуста» их считала за работу: латч вставал, стор оставался
    /// пуст, и второго шанса у сборки не было никогда.
    func testRebuildDoesNotLatchWhenPreviewsAreMissing() async {
        makeTrip(northMetres: 3_000, withPreview: false)
        makeTrip(northMetres: 3_000, withPreview: false)

        await store.rebuildIfNeeded()

        XCTAssertFalse(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey))
        XCTAssertEqual(storedTileCount(), 0)
    }

    /// Проба 2: стирание не имеет права идти раньше, чем стало известно, что
    /// есть из чего собирать. Иначе запуск с ещё не разобранными превью сносит
    /// накопленный слой и пишет взамен ноль — ровно то, что случилось на
    /// телефоне владельца.
    func testRebuildKeepsOldFogWhenPreviewsAreMissing() async {
        let id = makeTrip(northMetres: 3_000)
        await store.ingest(tripId: id)
        let before = storedTileCount()
        XCTAssertGreaterThan(before, 0)

        let context = pc.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        for entity in (try? context.fetch(request)) ?? [] { entity.previewPolyline = nil }
        try? context.save()

        await store.rebuildIfNeeded()

        XCTAssertEqual(storedTileCount(), before, "сборке нечего собрать — сносить тоже нечего")
        XCTAssertFalse(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey))
    }

    /// Ноль открытого — не «сборка прошла», и стирать под неё тоже нечего.
    /// Превью из двух одинаковых точек проходит проверку на пригодность по
    /// длине, но `RevealBuilder` на нём молчит — а накопленный слой обязан
    /// пережить такую сборку целым.
    func testRebuildKeepsOldFogWhenNothingWouldOpen() async {
        let id = makeTrip(northMetres: 3_000)
        await store.ingest(tripId: id)
        let before = storedTileCount()
        XCTAssertGreaterThan(before, 0)

        let context = pc.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        let point = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)
        for entity in (try? context.fetch(request)) ?? [] {
            entity.previewPolyline = Trip.encodePolyline([point, point])
        }
        try? context.save()

        await store.rebuildIfNeeded()

        XCTAssertEqual(storedTileCount(), before, "открывать нечем — сносить нечего")
        XCTAssertFalse(defaults.bool(forKey: RevealedLayerStore.rebuildFlagKey))
    }

    /// Ключ формы поднят до `v18` нарочно: телефоны, залатченные на пустой
    /// сборке `v17`, обязаны собрать ещё раз.
    func testRebuildLatchKeyIsV18() {
        XCTAssertEqual(RevealedLayerStore.rebuildFlagKey, "reveal_rebuild_v18_done")
    }

    /// `fetchBatchSize` на выборке-словаре без `objectID` CoreData не исполняет,
    /// зато печатает «Returning unbatched results» на каждый вызов — и этот шум
    /// прятал настоящие ошибки стора.
    func testPreviewRequestIsNotBatched() {
        let request = RevealedLayerStore.previewRequest(endedBefore: nil)

        XCTAssertEqual(request.fetchBatchSize, 0)
        XCTAssertEqual(request.resultType, .dictionaryResultType)
        XCTAssertEqual(request.propertiesToFetch as? [String], ["id", "previewPolyline"])
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
