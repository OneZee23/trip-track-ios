import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

@MainActor
final class PlacesTabViewModelTests: XCTestCase {
    private var pc: PersistenceController!
    private var store: CoreDataPlaceStore!
    private var repo: CoreDataTripRepository!
    private var manager: PlaceManager!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = CoreDataPlaceStore(context: pc.container.viewContext)
        repo = CoreDataTripRepository(persistenceController: pc)
        manager = PlaceManager(repository: repo, store: store)
    }
    override func tearDown() { manager = nil; repo = nil; store = nil; pc = nil; super.tearDown() }

    func testItemsFollowThePlacesAndTheirPasses() {
        let jubga = CLLocationCoordinate2D(latitude: 44.3196, longitude: 38.7089)
        let p = store.upsertPlace(cell: Place.cell(latitude: jubga.latitude, longitude: jubga.longitude), coordinate: jubga, name: "Джубга").place
        store.replacePasses(placeId: p.id, tripId: UUID(), with: [
            PlacePass(placeId: p.id, tripId: UUID(), timestamp: Date(), elapsedFromStart: 8040, distanceFromStart: 1, course: 0)])
        manager.reload()
        let vm = PlacesTabViewModel(manager: manager, repository: repo)
        vm.reload()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].place.name, "Джубга")
        XCTAssertTrue(vm.items[0].isFirstTime)
        manager.delete(placeId: p.id)
        vm.reload()
        XCTAssertTrue(vm.items.isEmpty)
    }

    // MARK: - Подсказки (0.8.0)

    private let home = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
    private let sea = CLLocationCoordinate2D(latitude: 44.561, longitude: 38.077)

    /// Завершённая поездка с превью — ровно то, что читает подсказка.
    @discardableResult
    private func trip(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D,
                      daysAgo: Int = 0) -> UUID {
        let ctx = pc.container.viewContext
        let e = TripEntity(context: ctx)
        let id = UUID()
        let start = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        e.id = id
        e.startDate = start
        e.endDate = start.addingTimeInterval(3600)
        e.distance = 1000
        e.isPrivate = true
        e.previewPolyline = Trip.encodePolyline([from, to])
        try? ctx.save()
        return id
    }

    /// Подсказки считаются отдельной задачей (детач + главный актёр обратно),
    /// поэтому тест ждёт её появления, а не спит фиксированно.
    private func settled(_ vm: PlacesTabViewModel) async -> [PlaceSuggestion] {
        vm.suggestionDebounce = 0
        vm.reload()
        for _ in 0..<200 where vm.knownSuggestions.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return vm.knownSuggestions
    }

    /// `nil` — «ещё считается», пустой массив — «не нашлось» (правило дома).
    /// Скелетон подсказок (состояние 23 спеки) читает ровно эту разницу, и
    /// без неё блок появлялся бы рывком поверх уже прочитанного списка.
    func testSuggestionsStartOutAsStillComputing() async {
        trip(home, sea, daysAgo: 2)
        let vm = PlacesTabViewModel(manager: manager, repository: repo)
        XCTAssertNil(vm.suggestions, "до первого ответа — «считается»")
        XCTAssertTrue(vm.isComputingSuggestions)
        XCTAssertTrue(vm.knownSuggestions.isEmpty, "для карты и булавок это просто «пусто»")

        _ = await settled(vm)
        XCTAssertNotNil(vm.suggestions)
        XCTAssertFalse(vm.isComputingSuggestions, "посчитали — скелетон уходит навсегда")

        // Пересчёт поверх уже показанных подсказок скелетона НЕ заказывает.
        vm.reload()
        XCTAssertFalse(vm.isComputingSuggestions)
    }

    func testSuggestionsComeFromTripEnds() async {
        trip(home, sea, daysAgo: 2)
        let vm = PlacesTabViewModel(manager: manager, repository: repo)
        let found = await settled(vm)
        XCTAssertEqual(Set(found.map(\.cell)),
                       [Place.cell(latitude: home.latitude, longitude: home.longitude),
                        Place.cell(latitude: sea.latitude, longitude: sea.longitude)])
    }

    /// Имя — из кэша геокодера и ниоткуда больше; нет строки — `nil`, и
    /// экран напишет «Точка на карте».
    func testSuggestionNameComesFromTheGeocodeCache() async {
        trip(home, sea, daysAgo: 2)
        let ctx = pc.container.viewContext
        let entity = GeocodeCacheEntity(context: ctx)
        entity.geohash5 = GeohashEncoder.encode(latitude: home.latitude, longitude: home.longitude, precision: 5)
        entity.locality = "Краснодар"
        entity.cachedAt = Date()
        try? ctx.save()

        let vm = PlacesTabViewModel(manager: manager, repository: repo)
        let found = await settled(vm)
        let homeCell = Place.cell(latitude: home.latitude, longitude: home.longitude)
        XCTAssertEqual(found.first(where: { $0.cell == homeCell })?.name, "Краснодар")
        XCTAssertNil(found.first(where: { $0.cell != homeCell })?.name)
    }

    /// «Сохранить как место» заводит место с тем же id и убирает строку из
    /// подсказок сразу — до всякого бэкфилла.
    func testSavingASuggestionCreatesThePlaceAndDropsTheRow() async {
        trip(home, sea, daysAgo: 2)
        let vm = PlacesTabViewModel(manager: manager, repository: repo)
        let found = await settled(vm)
        guard let first = found.first else { return XCTFail("подсказок нет") }
        vm.save(first)
        await manager.settle()
        XCTAssertFalse(vm.knownSuggestions.contains { $0.id == first.id })
        XCTAssertEqual(manager.places.map(\.id), [Place.id(forCell: first.cell)])
        XCTAssertEqual(manager.places.first?.cell, first.cell)
    }

    /// Уже заведённое место второй раз не предлагается.
    func testAnExistingPlaceIsNotSuggested() async {
        trip(home, sea, daysAgo: 2)
        manager.createPlace(cell: Place.cell(latitude: home.latitude, longitude: home.longitude),
                            coordinate: home, name: "Дом")
        await manager.settle()
        let vm = PlacesTabViewModel(manager: manager, repository: repo)
        let found = await settled(vm)
        XCTAssertFalse(found.map(\.cell).contains(Place.cell(latitude: home.latitude, longitude: home.longitude)))
    }

    func testLastTripIsTheFreshestOne() {
        trip(home, sea, daysAgo: 9)
        let newest = trip(sea, home, daysAgo: 1)
        let vm = PlacesTabViewModel(manager: manager, repository: repo)
        XCTAssertEqual(vm.lastTripId, newest)
    }
}
