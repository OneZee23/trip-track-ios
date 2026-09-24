import XCTest
import CoreData
@testable import TripTrack

/// Одна дверь для километров (спека §2.2, §2.4). С 0.8.1 в трек ложатся грубые
/// точки (хуже 65 м) и достроенные, и ни те, ни другие не двигают одометр,
/// рекорд, высоту и проезды мест. Правило живёт в одном месте: счётчиков пути
/// пять, и шестой однажды забудет.
@MainActor
final class DistanceDoorTests: XCTestCase {
    private var pc: PersistenceController!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        pc = nil
        super.tearDown()
    }

    private func point(_ east: Double, _ north: Double, _ seconds: Double,
                       accuracy: Double = 8, altitude: Double = 0, filled: Bool = false) -> TrackPoint {
        let c = TrackTestKit.coordinate(east: east, north: north)
        return TrackPoint(latitude: c.latitude, longitude: c.longitude, altitude: altitude,
                          speed: filled ? -1 : 10, horizontalAccuracy: filled ? -1 : accuracy,
                          timestamp: TrackTestKit.epoch.addingTimeInterval(seconds), isInterpolated: filled)
    }

    func testDoorTable() {
        XCTAssertTrue(TripDistanceGate.countsForDistance(horizontalAccuracy: 5, isInterpolated: false))
        XCTAssertTrue(TripDistanceGate.countsForDistance(horizontalAccuracy: 65, isInterpolated: false))
        XCTAssertFalse(TripDistanceGate.countsForDistance(horizontalAccuracy: 65.1, isInterpolated: false))
        XCTAssertFalse(TripDistanceGate.countsForDistance(horizontalAccuracy: 5, isInterpolated: true))
        XCTAssertFalse(TripDistanceGate.countsForDistance(horizontalAccuracy: -1, isInterpolated: true))
        // Вписанная рукой поездка кладёт точность 0 — считается, как считалась.
        XCTAssertTrue(TripDistanceGate.countsForDistance(horizontalAccuracy: 0, isInterpolated: false))
    }

    func testDistancePrefixSkipsCoarseAndFilledButStaysIndexAligned() {
        let points = [point(0, 0, 0), point(300, 100, 10, accuracy: 150),
                      point(0, 150, 15, filled: true), point(0, 200, 20)]
        let prefix = TripRouteLocator.distancePrefix(points)
        XCTAssertEqual(prefix.count, points.count)
        XCTAssertEqual(prefix[1], 0, accuracy: 0.001)
        XCTAssertEqual(prefix[2], 0, accuracy: 0.001)
        XCTAssertEqual(prefix[3], 200, accuracy: 1)
    }

    /// Грубая точка стоит В СТОРОНЕ от прямой (60 м), но не выброс: фильтр
    /// выбросов её оставит, и без двери она добавила бы 56 м и рекорд 40 м/с.
    func testPostProcessorCountsOnlyTrustedPoints() async throws {
        let entity = TrackTestKit.insertTrip(into: pc, points: [
            .init(east: 0, north: 0, seconds: 0),
            .init(east: 0, north: 100, seconds: 10),
            .init(east: 60, north: 150, seconds: 15, accuracy: 140, speed: 40),
            .init(east: 0, north: 200, seconds: 20),
            .init(east: 0, north: 300, seconds: 30),
        ])
        await PostTripTrackProcessor(persistenceController: pc).processTrip(try XCTUnwrap(entity.id))
        XCTAssertEqual(entity.distance, 300, accuracy: 1)
        XCTAssertEqual(entity.maxSpeed, 10, accuracy: 0.001)
    }

    /// Старые поездки (все точки ≤ 65 м, спека §2.2) пересчитываются в то же
    /// число. Зигзаг нужен, чтобы выброшенная точка меняла сумму: на прямой
    /// дверь с неверным порогом прошла бы незамеченной.
    func testLegacyTripRecomputesToTheSameNumber() async throws {
        // Явная аннотация замыкания и локальные Double — иначе компилятор не
        // укладывается в разумное время на этом выражении (Swift, известная
        // особенность вывода типов для замыканий с арифметикой внутри
        // мемберуайз-инициализатора); числа и их порядок не меняются.
        let specs = (0...40).map { i -> TrackTestKit.PointSpec in
            let east: Double = Double(i % 7) * 3
            let north: Double = Double(i) * 12
            let seconds: Double = Double(i)
            let accuracy: Double = Double(5 + i % 60)
            return TrackTestKit.PointSpec(east: east, north: north, seconds: seconds, accuracy: accuracy)
        }
        let entity = TrackTestKit.insertTrip(into: pc, points: specs)
        await PostTripTrackProcessor(persistenceController: pc).processTrip(try XCTUnwrap(entity.id))

        let kept = (entity.trackPoints?.array as? [TrackPointEntity] ?? [])
            .filter { !$0.isInterpolated }
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        let legacy = TripDistanceGate.totalDistance(kept.map {
            TripDistanceGate.Sample(latitude: $0.latitude, longitude: $0.longitude, timestamp: $0.timestamp)
        })
        XCTAssertEqual(entity.distance, legacy, accuracy: 0.0001)
    }

    func testMeasuredPointsDropCoarseAndFilled() {
        let trip = Trip(trackPoints: [point(0, 0, 0), point(0, 10, 1, accuracy: 120), point(0, 20, 2, filled: true)])
        XCTAssertEqual(trip.measuredPoints.count, 1)
    }

    /// Проезд мимо места — только по точкам, которым можно верить (§2.4).
    func testPlacePassesIgnoreCoarseAndFilledPoints() {
        let c = TrackTestKit.coordinate(east: 0, north: 1000)
        let place = Place(id: UUID(), cell: "x", latitude: c.latitude, longitude: c.longitude,
                          name: nil, createdAt: TrackTestKit.epoch)
        let points = [point(0, 0, 0), point(0, 400, 40), point(0, 1000, 100, accuracy: 150),
                      point(0, 1010, 101, filled: true), point(0, 1600, 160), point(0, 2000, 200)]
        XCTAssertTrue(PlaceMatcher.passes(through: place, tripId: UUID(), points: points,
                                          startDate: TrackTestKit.epoch).isEmpty)
    }

    /// У достройки скорость −1, и счёт времени в пейлоаде синка записал бы
    /// тоннель в «стоянку» — чужие глаза увидели бы это в ленте.
    func testSyncPayloadDoesNotCountAFilledStretchAsStopped() throws {
        let entity = TripEntity(context: pc.container.viewContext)
        entity.id = UUID()
        entity.startDate = TrackTestKit.epoch
        let trip = Trip(id: try XCTUnwrap(entity.id), startDate: TrackTestKit.epoch, trackPoints: [
            point(0, 0, 0), point(0, 100, 10),
            point(0, 120, 12, filled: true), point(0, 140, 14, filled: true),
            point(0, 160, 16, filled: true), point(0, 180, 18, filled: true),
            point(0, 200, 20),
        ])
        let payload = TripSyncPayload(trip: trip, entity: entity)
        XCTAssertEqual(payload.stoppedTime, 0)
        XCTAssertEqual(payload.drivingTime, 20)
    }

    /// Личное число значка «выше облаков» — по той же двери, что и его
    /// статистика (`BadgeManager`): без неё грубая точка (900 м, accuracy 140)
    /// напечатала бы пик выше того, что реально заработало значок.
    func testBadgeMaxAltitudeIgnoresCoarsePoints() throws {
        let clouds = try XCTUnwrap(Badge.all.first { $0.recordMetric == .tripMaxAltitude })
        let trip = Trip(trackPoints: [
            point(0, 0, 0, altitude: 100),
            point(0, 10, 1, accuracy: 140, altitude: 900),
            point(0, 20, 2, altitude: 100),
        ])
        XCTAssertEqual(clouds.recordValue(for: trip, unit: .km, language: .ru), "100 м")
    }
}
