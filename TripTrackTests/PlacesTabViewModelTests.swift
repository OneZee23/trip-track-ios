import XCTest
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
        let vm = PlacesTabViewModel(manager: manager)
        vm.reload()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].place.name, "Джубга")
        XCTAssertTrue(vm.items[0].isFirstTime)
        manager.delete(placeId: p.id)
        vm.reload()
        XCTAssertTrue(vm.items.isEmpty)
    }
}
