import XCTest
import CoreLocation
@testable import TripTrack

/// Чужая карта рисуется ТЕМ ЖЕ `MyMapView`, что и своя — меняется только
/// источник поездок (0.6.3). Отсюда два инварианта, каждый из которых при
/// нарушении портит данные владельца, а не чужие:
///
///  1. Геохеши чужого человека считаются в памяти и НИКОГДА не попадают в
///     `VisitedGeohashEntity`. Своя таблица — единственное хранилище своего
///     тумана, а `TerritoryManager.rebuildFromTrips()` стирает её и штампует
///     заново; чужие тайлы, попавшие туда, закрасят свой туман необратимо.
///  2. Чужая карта не трогает `MyMapViewModel.shared`. Тот синглтон переживает
///     переключение табов и держит состояние карты ВЛАДЕЛЬЦА.
final class RemoteMapTests: XCTestCase {

    private func polyline(_ coords: [(Double, Double)]) -> Data {
        Trip.encodePolyline(coords.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) })
    }

    private func strangerTrip() -> Trip {
        Trip(
            id: UUID(),
            startDate: Date(timeIntervalSince1970: 1_780_000_000),
            endDate: Date(timeIntervalSince1970: 1_780_017_880),
            distance: 412_000,
            region: "Нижегородская обл.",
            isPrivate: false,
            previewPolyline: polyline([(55.7558, 37.6173), (56.0, 40.0), (56.3269, 44.0059)])
        )
    }

    // MARK: - Геохеши

    func testGeohashesAreDerivedFromCoordinatesWithoutTouchingStorage() {
        let before = TerritoryManager().visitedGeohashes

        let hashes = TerritoryManager.geohashes(
            from: strangerTrip().previewCoordinates,
            precision: 6
        )

        XCTAssertFalse(hashes.isEmpty, "туман чужой карты строится из тех же координат, что маршруты")
        XCTAssertEqual(
            TerritoryManager().visitedGeohashes, before,
            "чужие геохеши в своей базе закрасят свой туман, и откатить это будет нечем"
        )
    }

    func testGeohashDerivationIsPure() {
        let coords = strangerTrip().previewCoordinates

        let first = TerritoryManager.geohashes(from: coords, precision: 6)
        let second = TerritoryManager.geohashes(from: coords, precision: 6)

        XCTAssertEqual(first, second)
    }

    func testEmptyCoordinatesProduceNoHashes() {
        XCTAssertTrue(TerritoryManager.geohashes(from: [], precision: 6).isEmpty)
    }

    // MARK: - Изоляция от своей карты

    @MainActor
    func testStrangerMapDoesNotDisturbTheOwnersSharedViewModel() async {
        let ownerTripCount = MyMapViewModel.shared.exploration.trips.count
        let ownerIsLoading = MyMapViewModel.shared.isLoading

        let vm = MyMapViewModel(source: StubSource(trips: [strangerTrip()]))
        await vm.loadRemote()

        XCTAssertEqual(MyMapViewModel.shared.exploration.trips.count, ownerTripCount)
        XCTAssertEqual(MyMapViewModel.shared.isLoading, ownerIsLoading)
    }

    @MainActor
    func testStrangerMapBuildsRoutesFromTheSuppliedTrips() async {
        let vm = MyMapViewModel(source: StubSource(trips: [strangerTrip()]))

        await vm.loadRemote()

        XCTAssertEqual(vm.exploration.trips.count, 1)
        XCTAssertFalse(vm.isLoading)
    }

    @MainActor
    func testStrangerMapWithNoPublicTripsIsEmptyNotBroken() async {
        let vm = MyMapViewModel(source: StubSource(trips: []))

        await vm.loadRemote()

        XCTAssertTrue(vm.isEmpty, "ноль публичных поездок — это пустое состояние, а не ошибка загрузки")
        XCTAssertFalse(vm.isLoading)
    }

    @MainActor
    func testStrangerMapNeverWritesVisitedGeohashes() async {
        let before = TerritoryManager().visitedGeohashes

        let vm = MyMapViewModel(source: StubSource(trips: [strangerTrip()]))
        await vm.loadRemote()

        XCTAssertEqual(TerritoryManager().visitedGeohashes, before)
    }
}

private struct StubSource: TripSource {
    let stubbed: [Trip]
    init(trips: [Trip]) { self.stubbed = trips }
    func load() async -> TripSourceResult { TripSourceResult(trips: stubbed, failed: false) }
}
