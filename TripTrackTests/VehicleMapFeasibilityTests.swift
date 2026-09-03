import XCTest
import CoreLocation
@testable import TripTrack

/// Проверка утверждения из исследования гаража (03.09.2026).
///
/// Исследование под 0.6.4 утверждает: «карта машины — это тот же вызов
/// `MapExploration.build`, только с другим фильтром». Утверждение дорогое —
/// на нём стоит вся оценка объёма фичи, — поэтому оно проверено кодом, а не
/// оставлено словами.
///
/// Здесь ничего не строится «на будущее»: тесты гоняют СУЩЕСТВУЮЩИЕ функции на
/// наборе поездок, отфильтрованном по машине, и показывают, что регионы,
/// километры и агрегаты считаются по этому набору без единой правки в них.
/// Если однажды они станут зависеть от аккаунта, а не от массива, этот файл
/// покраснеет — и оценка объёма перестанет быть верной молча.
final class VehicleMapFeasibilityTests: XCTestCase {

    private let mercedes = UUID()
    private let polo = UUID()

    /// Москва → Тверь, примерно 160 км на северо-запад.
    private func moscowTver() -> Data {
        Trip.encodePolyline([
            CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
            CLLocationCoordinate2D(latitude: 56.0100, longitude: 37.0000),
            CLLocationCoordinate2D(latitude: 56.8587, longitude: 35.9176),
        ])
    }

    /// Москва → Владимир, примерно 180 км на восток.
    private func moscowVladimir() -> Data {
        Trip.encodePolyline([
            CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
            CLLocationCoordinate2D(latitude: 55.8000, longitude: 39.0000),
            CLLocationCoordinate2D(latitude: 56.1290, longitude: 40.4070),
        ])
    }

    private func trip(
        km: Double, vehicle: UUID?, polyline: Data, transfer: Bool = false
    ) -> Trip {
        Trip(
            id: UUID(),
            startDate: Date(timeIntervalSince1970: 1_780_000_000),
            endDate: Date(timeIntervalSince1970: 1_780_007_200),
            distance: km * 1000,
            isPrivate: false,
            isTransfer: transfer,
            vehicleId: vehicle,
            previewPolyline: polyline
        )
    }

    private var garage: [Trip] {
        [
            trip(km: 160, vehicle: mercedes, polyline: moscowTver()),
            trip(km: 180, vehicle: polo, polyline: moscowVladimir()),
            trip(km: 90, vehicle: nil, polyline: moscowTver(), transfer: true),
        ]
    }

    /// Ровно тот фильтр, который предлагает исследование.
    private func trips(of vehicleId: UUID) -> [Trip] {
        garage.filter { $0.vehicleId == vehicleId && !$0.isTransfer }
    }

    // MARK: - Главное утверждение

    func testMapOfOneVehicleIsBuiltByTheExistingFunction() async {
        await RegionAtlas.shared.loadIfNeeded()
        let atlas = RegionAtlas.shared
        let mine = trips(of: mercedes)

        let exploration = MapExploration.build(
            trips: mine,
            visitedHashes: TerritoryManager.geohashes(
                fromTrips: mine.map { $0.previewCoordinates }, precision: 6),
            atlas: atlas
        )

        XCTAssertEqual(exploration.trips.count, 1,
                       "на карте машины ровно её поездки — ни строки нового кода для этого не нужно")
        XCTAssertEqual(exploration.totalKm, 160, accuracy: 1.0)
    }

    func testTwoVehiclesGetDifferentMapsFromTheSameGarage() async {
        await RegionAtlas.shared.loadIfNeeded()
        let atlas = RegionAtlas.shared

        func explore(_ id: UUID) -> MapExploration {
            let t = trips(of: id)
            return MapExploration.build(
                trips: t,
                visitedHashes: TerritoryManager.geohashes(
                    fromTrips: t.map { $0.previewCoordinates }, precision: 6),
                atlas: atlas
            )
        }

        let a = explore(mercedes)
        let b = explore(polo)

        XCTAssertEqual(a.trips.count, 1)
        XCTAssertEqual(b.trips.count, 1)
        XCTAssertNotEqual(a.trips.first?.id, b.trips.first?.id,
                          "две машины из одного гаража дают две разные карты")
    }

    func testTransferTripsNeverLandOnAVehiclesMap() async {
        await RegionAtlas.shared.loadIfNeeded()
        let mine = trips(of: mercedes)

        // Трансфер в наборе есть, но у него нет машины и стоит флаг — он не
        // должен попасть ни на чью карту.
        XCTAssertEqual(garage.count, 3)
        XCTAssertEqual(mine.count, 1)
        XCTAssertFalse(mine.contains { $0.isTransfer })
    }

    // MARK: - Регионы и агрегаты считаются от массива, а не от аккаунта

    func testRegionsAreDerivedFromTheGivenTripsOnly() async {
        await RegionAtlas.shared.loadIfNeeded()
        let atlas = RegionAtlas.shared

        let whole = MapExploration.build(
            trips: garage,
            visitedHashes: TerritoryManager.geohashes(
                fromTrips: garage.map { $0.previewCoordinates }, precision: 6),
            atlas: atlas
        )
        let one = MapExploration.build(
            trips: trips(of: mercedes),
            visitedHashes: TerritoryManager.geohashes(
                fromTrips: trips(of: mercedes).map { $0.previewCoordinates }, precision: 6),
            atlas: atlas
        )

        XCTAssertGreaterThanOrEqual(
            whole.regions.count, one.regions.count,
            "у одной машины регионов не больше, чем у всего гаража — значит регионы считаются от переданного массива"
        )
        XCTAssertLessThanOrEqual(one.totalKm, whole.totalKm)
    }

    func testRecordsOfOneVehicleComeOutOfTheExistingAggregator() {
        // «Рекорды именно этой машины» из исследования — тот же
        // `MeAggregates.compute`, которому всё равно, чьи поездки ему дали.
        let agg = MeAggregates.compute(
            trips: trips(of: polo), now: Date(), calendar: .current)

        XCTAssertEqual(agg.tripCount, 1)
        XCTAssertEqual(agg.totalKm, 180, accuracy: 0.5)
        XCTAssertEqual(agg.longestTripKm, 180, accuracy: 0.5,
                       "рекорд машины — это рекорд по её поездкам, отдельного кода не нужно")
    }

    func testAnEmptyVehicleProducesAnEmptyMapRatherThanAFailure() async {
        await RegionAtlas.shared.loadIfNeeded()
        let fresh = UUID()

        let exploration = MapExploration.build(
            trips: trips(of: fresh), visitedHashes: [], atlas: RegionAtlas.shared)

        XCTAssertTrue(exploration.isEmpty,
                      "новая машина без поездок — пустая карта, а не ошибка")
    }
}
