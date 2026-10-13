import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Sentry AppHang задачи H, часть 2: `PlaceManager.reconcile()` — ЕДИНСТВЕННЫЙ
/// шаг миграции 0.6.8 (v14, `placesMatchedAt`), совпадающий с окном хэнга
/// APPLE-IOS-7 (release 0.6.8+60). Чанк здесь — ОДНА поездка × её места-
/// кандидаты: `Task.yield()` между поездками в цикле `reconcile()` не спасает
/// то, что происходит ВНУТРИ чанка, а на зрелой библиотеке с десятками мест
/// один такой чанк — подъём полного трека (до 2000 точек) плюс
/// `PlaceMatcher.passes` (ещё один проход по треку) на КАЖДОЕ место-кандидат.
///
/// `@MainActor`: тест `async` и трогает `viewContext` — см. CLAUDE.md
/// «async-тест, читающий viewContext, обязан быть @MainActor».
@MainActor
final class PlaceReconcileMainThreadTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var store: CoreDataPlaceStore!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        store = CoreDataPlaceStore(context: pc.container.viewContext)
    }

    override func tearDown() {
        store = nil
        repo = nil
        pc = nil
        super.tearDown()
    }

    // MARK: - Стресс-библиотека

    /// 400 поездок по 2000 точек — масштаб брифа H. Из них `hubTrips` идут
    /// тесным пучком (соседние линии в 50–100 м друг от друга — внутри ОДНОЙ
    /// ячейки geohash-5, ~4.9 км), и все 60 мест сидят прямо на этом пучке:
    /// `PlaceMatcher.isCandidate` совпадает для КАЖДОЙ хабовой поездки и
    /// КАЖДОГО места — именно сценарий «дорога с десятками мест рядом», а не
    /// пустой предфильтр. Остальные поездки — далеко в стороне (>100 км):
    /// дешёвый отказ предфильтра, для реализма всей библиотеки.
    private func seedAdversarialLibrary(
        hubTrips: Int = 40, otherTrips: Int = 360, pointsPerTrip: Int = 2000, placeCount: Int = 60
    ) {
        let ctx = pc.container.viewContext
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let hubLat = 45.000, hubLon = 38.900

        for t in 0..<hubTrips {
            autoreleasepool {
                let trip = TripEntity(context: ctx)
                trip.id = UUID()
                let start = base.addingTimeInterval(-Double(t + 1) * 3600)
                trip.startDate = start
                trip.endDate = start.addingTimeInterval(Double(pointsPerTrip) * 5)
                trip.isPrivate = true
                trip.title = "Hub \(t)"
                // Соседи в 60 м друг от друга — весь пучок из 40 линий
                // укладывается в ~2.4 км, внутри одной ячейки geohash-5.
                let lat0 = hubLat + Double(t) * 0.0005
                var coords: [CLLocationCoordinate2D] = []
                coords.reserveCapacity(pointsPerTrip)
                for p in 0..<pointsPerTrip {
                    let lon = hubLon + Double(p) * 0.00005
                    let point = TrackPointEntity(context: ctx)
                    point.id = UUID()
                    point.latitude = lat0
                    point.longitude = lon
                    point.altitude = 40
                    point.speed = 14
                    point.timestamp = start.addingTimeInterval(Double(p) * 5)
                    point.trip = trip
                    coords.append(CLLocationCoordinate2D(latitude: lat0, longitude: lon))
                }
                trip.previewPolyline = Trip.encodePolyline(coords)
                trip.distance = 9000
                trip.maxSpeed = 20
                trip.averageSpeed = 14
            }
            if t % 10 == 0 { try? ctx.save() }
        }
        try? ctx.save()

        for t in 0..<otherTrips {
            autoreleasepool {
                let trip = TripEntity(context: ctx)
                trip.id = UUID()
                let start = base.addingTimeInterval(-Double(hubTrips + t + 1) * 3600)
                trip.startDate = start
                trip.endDate = start.addingTimeInterval(Double(pointsPerTrip) * 5)
                trip.isPrivate = true
                trip.title = "Far \(t)"
                let lat0 = hubLat + 2.0 + Double(t) * 0.01
                let lon0 = hubLon + 2.0
                var coords: [CLLocationCoordinate2D] = []
                coords.reserveCapacity(pointsPerTrip)
                for p in 0..<pointsPerTrip {
                    let lat = lat0 + Double(p) * 0.00003
                    let lon = lon0 + Double(p) * 0.00002
                    let point = TrackPointEntity(context: ctx)
                    point.id = UUID()
                    point.latitude = lat
                    point.longitude = lon
                    point.altitude = 40
                    point.speed = 14
                    point.timestamp = start.addingTimeInterval(Double(p) * 5)
                    point.trip = trip
                    coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
                trip.previewPolyline = Trip.encodePolyline(coords)
                trip.distance = 9000
                trip.maxSpeed = 20
                trip.averageSpeed = 14
            }
            if t % 40 == 0 { try? ctx.save() }
        }
        try? ctx.save()

        // 60 мест прямо на пучке хабовых поездок, растянуты по его длине —
        // предфильтр совпадает у всех, а точечные попадания `passes(near:)`
        // распределены, как на настоящей дороге с десятками мест.
        let midLat = hubLat + Double(hubTrips / 2) * 0.0005
        for i in 0..<placeCount {
            let lon = hubLon + Double(i) * (Double(pointsPerTrip) * 0.00005 / Double(placeCount))
            let cell = Place.cell(latitude: midLat, longitude: lon)
            let e = PlaceEntity(context: ctx)
            e.id = Place.id(forCell: cell)
            e.cell = cell
            e.latitude = midLat
            e.longitude = lon
            e.createdAt = Date()
        }
        try? ctx.save()
    }

    // MARK: - «Было»

    /// Тот же алгоритм, что раньше жил в `PlaceManager.process(_:places:)` —
    /// инлайнен ТОЛЬКО ради замера «было»: подъём трека (`fetchTripDetail`,
    /// синхронно) и `PlaceMatcher.passes` по каждому кандидату — на главном
    /// потоке, без единой уступки внутри чанка. `git log` на `fix/hang`
    /// держит исходную версию продакшен-кода, копировать её сюда не нужно.
    private func measureOldSynchronousReconcileElapsedMs(pending: [TripPreviewRef], places: [Place]) -> Double {
        let runOnMain: (() -> Void) -> Void = Thread.isMainThread
            ? { body in body() }
            : { body in DispatchQueue.main.sync(execute: body) }

        let started = Date()
        runOnMain {
            for ref in pending {
                let cells = PlaceMatcher.cells(of: ref.previewCoordinates)
                let candidates = places.filter { PlaceMatcher.isCandidate(place: $0, tripCells: cells) }
                guard !candidates.isEmpty,
                      let trip = self.repo.fetchTripDetail(id: ref.id), trip.trackPoints.count > 1 else { continue }
                for place in candidates {
                    _ = PlaceMatcher.passes(through: place, tripId: trip.id,
                                            points: trip.trackPoints, startDate: trip.startDate)
                }
            }
        }
        return Date().timeIntervalSince(started) * 1000
    }

    func testOldSynchronousReconcileBlockedMainForAdversarialLibrary() {
        seedAdversarialLibrary()
        let pending = repo.tripPreviews(needingPlaceMatch: true)
        let places = store.fetchPlaces()
        XCTAssertEqual(pending.count, 400)
        XCTAssertEqual(places.count, 60)

        let elapsedMs = measureOldSynchronousReconcileElapsedMs(pending: pending, places: places)
        print(String(format: "[places reconcile] БЫЛО: главный поток стоял %.0f мс без единой уступки", elapsedMs))
        XCTAssertGreaterThan(elapsedMs, 500,
            "адверсариальная библиотека должна была хоть раз держать главный поток дольше полсекунды")
    }

    // MARK: - «Стало»

    /// Продакшен-фикс, тот же стресс: `reconcile()` через реальный
    /// `PlaceManager`, сторож меряет максимальный разрыв ответа главной
    /// диспетчерской очереди. Бюджет 200 мс — по образцу
    /// `TerritoryBackfillMainThreadTests`/`DiscoveryProcessorTests`.
    func testReconcileKeepsMainResponsiveUnderAdversarialStress() async {
        seedAdversarialLibrary()
        let manager = PlaceManager(repository: repo, store: store)
        manager.pendingHistoryIds = []

        let watchdog = MainThreadWatchdog()
        watchdog.start()
        let started = Date()
        await manager.reconcile()
        let elapsed = Date().timeIntervalSince(started)
        // Сна перед остановкой здесь БОЛЬШЕ НЕТ. Он стоял, чтобы «дать
        // последней пробе доехать», но тело теста идёт на главном потоке
        // (`@MainActor` обязателен у теста с CoreData и `async`), то есть сам
        // держал main пятьдесят миллисекунд — и проба честно записывала их как
        // простой. Приём портил ровно то число, которое сторожит тест. Теперь
        // пограничную пробу отбрасывает `stop()`, и он же отдаёт результат.
        let maxGapMs = watchdog.stop()

        print(String(format: "[places reconcile] СТАЛО: главный поток стоял максимум %.0f мс, весь проход %.0f мс",
                     maxGapMs, elapsed * 1000))
        XCTAssertTrue(repo.tripPreviews(needingPlaceMatch: true).isEmpty, "все поездки обязаны сверится")
        XCTAssertLessThan(maxGapMs, 200,
            "reconcile() держал главный поток дольше 200 мс на адверсариальной библиотеке — геометрия снова на главном")
    }
}
