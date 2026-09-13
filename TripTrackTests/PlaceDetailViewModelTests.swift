import XCTest
import CoreLocation
@testable import TripTrack

/// Экран места: `load()` собирает место, статистику, проезды и нитки за один
/// проход; `focus(forPassOf:)` решает, открывать поездку сверху или на своей
/// отметке. Фикстуры — как в `PlaceManagerTests`: прямая линия по 50 м / 10 с,
/// отметка на 30-й точке.
@MainActor
final class PlaceDetailViewModelTests: XCTestCase {
    private var pc: PersistenceController!
    private var store: CoreDataPlaceStore!
    private var repo: CoreDataTripRepository!
    private var manager: PlaceManager!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private let lat0 = 44.30, lon0 = 38.70, stepLat = 0.00045

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = CoreDataPlaceStore(context: pc.container.viewContext)
        repo = CoreDataTripRepository(persistenceController: pc)
        manager = PlaceManager(repository: repo, store: store)
        manager.pendingHistoryIds = []
    }

    override func tearDown() {
        manager.pendingHistoryIds = []
        manager = nil; repo = nil; store = nil; pc = nil
        super.tearDown()
    }

    /// Прямая линия по 50 м / 10 с, со старта `start`. `withPreview` кладёт те
    /// же точки в `previewPolyline` — экрану места неоткуда взять нитку и
    /// конец маршрута без него, а без превью проверяем ровно то, что нитки у
    /// такой поездки не будет.
    @discardableResult
    private func trip(start: Date, reverse: Bool = false, count: Int = 120, withPreview: Bool = true) -> UUID {
        let ctx = pc.container.viewContext
        let e = TripEntity(context: ctx)
        let id = UUID()
        e.id = id; e.startDate = start; e.endDate = start.addingTimeInterval(Double(count) * 10)
        e.distance = Double(count) * 50; e.isPrivate = true
        var coords: [CLLocationCoordinate2D] = []
        for k in 0..<count {
            let i = reverse ? count - 1 - k : k
            let p = TrackPointEntity(context: ctx)
            p.id = UUID()
            p.latitude = lat0 + Double(i) * stepLat
            p.longitude = lon0
            p.speed = 5; p.course = reverse ? 180 : 0; p.horizontalAccuracy = 5
            p.timestamp = start.addingTimeInterval(Double(k) * 10)
            p.trip = e
            coords.append(CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude))
        }
        if withPreview { e.previewPolyline = Trip.encodePolyline(coords) }
        try? ctx.save()
        return id
    }

    private func checkpoint(on tripId: UUID, atIndex i: Int) -> TripCheckpoint {
        let cp = TripCheckpoint(timestamp: t0.addingTimeInterval(Double(i) * 10),
                                latitude: lat0 + Double(i) * stepLat, longitude: lon0,
                                distanceFromStart: Double(i) * 50, elapsedFromStart: Double(i) * 10)
        _ = repo.addCheckpoint(cp, to: tripId)
        return cp
    }

    /// (а) `load()` даёт место, статистику и проезды свежими сверху; нитка —
    /// только у поездки с превью (у «проезжей» поездки без превью нитки нет).
    func testLoadBuildsStatsPassesFreshFirstAndRoutesFromPreviewedTripsOnly() async {
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30)
        manager.registerCheckpoint(cp, tripId: today)
        await manager.settle()
        let place = manager.places[0]

        let driveBy = trip(start: t0.addingTimeInterval(7_200), reverse: true, withPreview: false)
        await manager.process(tripId: driveBy)

        let vm = PlaceDetailViewModel(placeId: place.id, manager: manager, repository: repo, localityLookup: { _ in nil })
        vm.load()

        XCTAssertEqual(vm.place?.id, place.id)
        XCTAssertEqual(vm.stats.passCount, 2)
        XCTAssertEqual(vm.passes.count, 2)
        XCTAssertEqual(vm.passes.first?.tripId, driveBy, "проезд-двух-часов-позже — свежий, значит сверху")
        XCTAssertEqual(vm.routes.count, 1, "нитка только у поездки с превью")
    }

    /// (б) Подпись направления — `localityLookup` по КОНЦУ превью самой
    /// свежей поездки этого направления; заглушка отвечает одним именем на
    /// любую координату, поэтому у единственного направления ровно оно.
    func testDirectionLabelComesFromLocalityLookupAtLatestTripsEnd() async {
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30)
        manager.registerCheckpoint(cp, tripId: today)
        await manager.settle()
        let place = manager.places[0]

        let vm = PlaceDetailViewModel(placeId: place.id, manager: manager, repository: repo,
                                       localityLookup: { _ in "к морю" })
        vm.load()

        XCTAssertEqual(vm.stats.directions.count, 1)
        let latestTripId = vm.stats.directions[0].latestTripId
        XCTAssertEqual(vm.directionLabels[latestTripId], "к морю")
    }

    /// (в) У поездки со своей отметкой этого места — фокус на неё; у поездки,
    /// которая место просто проехала (нет отметки с этим `placeId`), — сверху.
    func testFocusForPassOfPicksOwnCheckpointElseTop() async {
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30)
        manager.registerCheckpoint(cp, tripId: today)
        await manager.settle()
        let place = manager.places[0]

        let driveBy = trip(start: t0.addingTimeInterval(7_200), reverse: true)
        await manager.process(tripId: driveBy)

        let vm = PlaceDetailViewModel(placeId: place.id, manager: manager, repository: repo, localityLookup: { _ in nil })
        vm.load()

        XCTAssertEqual(vm.focus(forPassOf: today), .checkpoint(cp.id))
        XCTAssertEqual(vm.focus(forPassOf: driveBy), .top)
    }

    /// (г) `rename` доходит до хранилища (что подтверждает повторный `load()`
    /// — на уведомление `.placesChanged`, у которого `.receive(on: .main)`,
    /// тест нарочно не полагается: диспетчеризация асинхронна и не гарантирует
    /// исполнение к следующей строке теста). `delete` обнуляет `place` тем же
    /// вызовом, синхронно.
    func testRenameUpdatesPlaceAndDeleteClearsIt() async {
        let today = trip(start: t0)
        let cp = checkpoint(on: today, atIndex: 30)
        manager.registerCheckpoint(cp, tripId: today)
        await manager.settle()
        let place = manager.places[0]

        let vm = PlaceDetailViewModel(placeId: place.id, manager: manager, repository: repo, localityLookup: { _ in nil })
        vm.load()
        XCTAssertNil(vm.place?.name)

        vm.rename("Джубга")
        vm.load()
        XCTAssertEqual(vm.place?.name, "Джубга")

        vm.delete()
        XCTAssertNil(vm.place)
    }
}
