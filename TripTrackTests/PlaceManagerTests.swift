import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Оркестровка: отметка рождает место и досчитывает историю по библиотеке;
/// финиш поездки записывает проезды; удаление поездки забирает их; сверка
/// при запуске делает то же для всего, что ещё не сверено.
@MainActor
final class PlaceManagerTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var store: CoreDataPlaceStore!
    private var manager: PlaceManager!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private let lat0 = 44.30, lon0 = 38.70, stepLat = 0.00045

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        store = CoreDataPlaceStore(context: pc.container.viewContext)
        manager = PlaceManager(repository: repo, store: store)
        // Отложенная история живёт в `UserDefaults` (переживает убийство
        // приложения) — значит переживает и чужой тест.
        manager.pendingHistoryIds = []
    }

    override func tearDown() {
        manager.pendingHistoryIds = []
        manager = nil; store = nil; repo = nil; pc = nil
        super.tearDown()
    }

    /// Прямая на север (`reverse` — обратно, курс 180), 120 точек по 50 м / 10 с,
    /// со старта `start`. Превью не пишем: пустое превью — кандидат.
    @discardableResult
    private func trip(start: Date, reverse: Bool = false, offsetLon: Double = 0, count: Int = 120) -> UUID {
        let ctx = pc.container.viewContext
        let e = TripEntity(context: ctx)
        let id = UUID()
        e.id = id; e.startDate = start; e.endDate = start.addingTimeInterval(Double(count) * 10)
        e.distance = Double(count) * 50; e.isPrivate = true
        for k in 0..<count {
            let i = reverse ? count - 1 - k : k
            let p = TrackPointEntity(context: ctx)
            p.id = UUID()
            p.latitude = lat0 + Double(i) * stepLat
            p.longitude = lon0 + offsetLon
            p.speed = 5; p.course = reverse ? 180 : 0; p.horizontalAccuracy = 5
            p.timestamp = start.addingTimeInterval(Double(k) * 10)
            p.trip = e
        }
        try? ctx.save()
        return id
    }

    private func checkpoint(on tripId: UUID, atIndex i: Int, name: String? = nil) -> TripCheckpoint {
        let cp = TripCheckpoint(timestamp: t0.addingTimeInterval(Double(i) * 10),
                                latitude: lat0 + Double(i) * stepLat, longitude: lon0,
                                distanceFromStart: Double(i) * 50, elapsedFromStart: Double(i) * 10, name: name)
        _ = repo.addCheckpoint(cp, to: tripId)
        return cp
    }

    func testCheckpointBirthsAPlaceAndBackfillsHistory() async {
        let earlier = trip(start: t0.addingTimeInterval(-86_400))          // вчера, мимо того же места
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30, name: "Джубга")
        manager.registerCheckpoint(cp, tripId: today)
        await manager.settle()
        XCTAssertEqual(manager.places.count, 1)
        let place = manager.places[0]
        XCTAssertEqual(place.id, Place.id(forCell: Place.cell(latitude: cp.latitude, longitude: cp.longitude)))
        XCTAssertEqual(place.name, "Джубга")
        XCTAssertEqual(repo.fetchTripDetail(id: today)?.checkpoints.first?.placeId, place.id)
        // История досчитана по библиотеке: вчерашняя поездка тоже проезжала.
        XCTAssertEqual(Set(store.passes(placeId: place.id).map(\.tripId)), [earlier, today])
        XCTAssertEqual(manager.stats(for: place.id).passCount, 2)
    }

    func testFinishedTripAddsPassesAndIsMarkedMatched() async {
        let today = trip(start: t0)
        manager.registerCheckpoint(checkpoint(on: today, atIndex: 30), tripId: today)
        await manager.settle()
        let back = trip(start: t0.addingTimeInterval(7_200), reverse: true)
        await manager.process(tripId: back)
        let place = manager.places[0]
        XCTAssertEqual(store.passes(tripId: back).count, 1)
        XCTAssertEqual(store.passes(tripId: back)[0].course, 180, accuracy: 0.5)
        XCTAssertEqual(manager.stats(for: place.id).directions.count, 2)
        // `process` помечает свою поездку сверенной; досчёт истории после
        // отметки (`matchAllTrips`) сверял только ОДНО место и метку не ставит —
        // `today` досверит `reconcile()`.
        XCTAssertFalse(repo.tripPreviews(needingPlaceMatch: true).contains { $0.id == back })
    }

    func testFarTripGetsNoPassesButIsStillMarked() async {
        let today = trip(start: t0)
        manager.registerCheckpoint(checkpoint(on: today, atIndex: 30), tripId: today)
        await manager.settle()
        let far = trip(start: t0.addingTimeInterval(7_200), offsetLon: 1.0)     // ~80 км восточнее
        await manager.process(tripId: far)
        XCTAssertTrue(store.passes(tripId: far).isEmpty)
        XCTAssertFalse(repo.tripPreviews(needingPlaceMatch: true).contains { $0.id == far })
    }

    func testForgettingATripDropsItsPasses() async {
        let today = trip(start: t0)
        manager.registerCheckpoint(checkpoint(on: today, atIndex: 30), tripId: today)
        await manager.settle()
        let back = trip(start: t0.addingTimeInterval(7_200), reverse: true)
        await manager.process(tripId: back)
        manager.forget(tripId: back)
        XCTAssertEqual(manager.stats(for: manager.places[0].id).passCount, 1)
    }

    /// Сверка при запуске: отметки без места получают место, несверенные
    /// поездки — проезды; второй вызов ничего не делает.
    func testReconcileRegistersOrphanCheckpointsAndMatchesTrips() async {
        let a = trip(start: t0)
        _ = checkpoint(on: a, atIndex: 30)                 // без registerCheckpoint — как после пула
        let b = trip(start: t0.addingTimeInterval(7_200), reverse: true)
        await manager.reconcile()
        XCTAssertEqual(manager.places.count, 1)
        XCTAssertEqual(store.passes(placeId: manager.places[0].id).count, 2)
        XCTAssertTrue(repo.tripPreviews(needingPlaceMatch: true).isEmpty)
        let before = store.passes(placeId: manager.places[0].id).map(\.id)
        await manager.reconcile()
        XCTAssertEqual(store.passes(placeId: manager.places[0].id).map(\.id), before, "повторная сверка не трогает проезды")
        _ = b
    }

    /// Первый запуск после обновления у человека без отметок: мест нет вовсе,
    /// сверять не с чем. Поездки обязаны пометиться одной пачкой — иначе
    /// сверка поднимала бы точки всей библиотеки, чтобы каждый раз выяснить,
    /// что мест ноль.
    func testReconcileWithoutPlacesMarksEverythingWithoutLoadingPoints() async {
        trip(start: t0)
        trip(start: t0.addingTimeInterval(7_200))
        trip(start: t0.addingTimeInterval(14_400))
        XCTAssertEqual(repo.tripPreviews(needingPlaceMatch: true).count, 3)
        await manager.reconcile()
        XCTAssertTrue(repo.tripPreviews(needingPlaceMatch: true).isEmpty)
        XCTAssertTrue(store.fetchPlaces().isEmpty)
        XCTAssertTrue(manager.places.isEmpty)
    }

    func testAdoptNameNamesAnUnnamedPlaceOnce() async {
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30)
        manager.registerCheckpoint(cp, tripId: today)
        await manager.settle()
        manager.adoptName("Джубга", forCheckpoint: cp.id, tripId: today)
        XCTAssertEqual(manager.places[0].name, "Джубга")
        manager.adoptName("Поворот", forCheckpoint: cp.id, tripId: today)
        XCTAssertEqual(manager.places[0].name, "Джубга")
    }

    /// Тёплый кэш геокодера отвечает синхронно, и имя приходит РАНЬШЕ, чем
    /// отметка получит `placeId`: у дома и знакомых регионов место оставалось
    /// безымянным навсегда. Имя должно найти место по ячейке, а регистрация —
    /// досчитать историю такому месту, хотя вставила его не она.
    func testGeocoderNameArrivesBeforeRegistration() async {
        let earlier = trip(start: t0.addingTimeInterval(-86_400))
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30)
        manager.adoptName("Джубга", forCheckpoint: cp.id, tripId: today)
        manager.registerCheckpoint(cp, tripId: today)
        await manager.settle()
        XCTAssertEqual(manager.places.count, 1)
        let place = manager.places[0]
        XCTAssertEqual(place.id, Place.id(forCell: Place.cell(latitude: cp.latitude, longitude: cp.longitude)))
        XCTAssertEqual(place.name, "Джубга")
        XCTAssertEqual(Set(store.passes(placeId: place.id).map(\.tripId)), [earlier, today],
                       "место, заведённое геокодером, историю всё равно получает")
    }

    /// Кнопку отметки жмут на ходу: перебор всей библиотеки на главном актёре
    /// там — заминка в машине. История нового места ждёт финиша, но НЕ
    /// теряется: очередь лежит в `UserDefaults` и переживает убийство
    /// приложения на парковке.
    func testHistoryBackfillIsDeferredWhileRecording() async {
        let earlier = trip(start: t0.addingTimeInterval(-86_400))
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30)
        manager.registerCheckpoint(cp, tripId: today, recording: true)
        await manager.settle()
        let place = manager.places[0]
        XCTAssertTrue(store.passes(placeId: place.id).isEmpty, "за рулём библиотеку не перебираем")
        XCTAssertEqual(manager.pendingHistoryIds, [place.id])
        await manager.process(tripId: today)
        XCTAssertEqual(Set(store.passes(placeId: place.id).map(\.tripId)), [earlier, today],
                       "на финише история досчитана")
        XCTAssertTrue(manager.pendingHistoryIds.isEmpty)
    }

    func testDeletingAPlaceKeepsCheckpointTombstoneSoItIsNotReborn() async {
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30)
        manager.registerCheckpoint(cp, tripId: today)
        await manager.settle()
        let id = manager.places[0].id
        manager.delete(placeId: id)
        XCTAssertTrue(manager.places.isEmpty)
        await manager.reconcile()
        XCTAssertTrue(manager.places.isEmpty, "удалённое место не воскресает из старой отметки")
        XCTAssertEqual(repo.fetchTripDetail(id: today)?.checkpoints.first?.placeId, id)
    }
}
