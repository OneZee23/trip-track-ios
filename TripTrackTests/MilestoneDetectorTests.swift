import XCTest
import CoreLocation
@testable import TripTrack

/// Вехи считаются от ПРОШЛЫХ поездок человека, а не от чужих рекордов —
/// поэтому половина тестов здесь про то, что без истории веха не берётся.
final class MilestoneDetectorTests: XCTestCase {

    private var atlas: RegionAtlas!

    private let krasnodar = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
    private let rostov = CLLocationCoordinate2D(latitude: 47.222, longitude: 39.719)
    private let stavropol = CLLocationCoordinate2D(latitude: 45.045, longitude: 41.969)

    override func setUp() async throws {
        try await super.setUp()
        await RegionAtlas.shared.loadIfNeeded()
        atlas = RegionAtlas.shared
        try XCTSkipUnless(atlas.isLoaded, "MapRegions.json missing from the test bundle")
    }

    override func tearDown() {
        atlas = nil
        super.tearDown()
    }

    // MARK: - Помощники

    private func shortLine(
        at coordinate: CLLocationCoordinate2D,
        altitude: Double = 0,
        startingAt origin: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> [TrackPoint] {
        DiscoveryTrackFixtures.line(
            from: coordinate,
            to: DiscoveryTrackFixtures.offset(coordinate, eastMetres: 200),
            startingAt: origin, altitude: altitude)
    }

    private func trip(_ track: [TrackPoint]) -> Trip {
        Trip(startDate: track.first?.timestamp ?? Date(), trackPoints: track)
    }

    private func detect(_ track: [TrackPoint], _ history: MilestoneDetector.History) -> [MilestoneHit] {
        MilestoneDetector.detect(trip: trip(track), track: track, history: history, atlas: atlas)
    }

    // MARK: - Первый регион

    func testFirstTripYieldsOnlyFirstRegion() {
        let hits = detect(shortLine(at: krasnodar), MilestoneDetector.History())

        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.milestone, .firstRegion)
        XCTAssertEqual(hits.first?.key, "firstRegion:RU-KDA")
    }

    func testKnownRegionIsNotAMilestone() {
        let hits = detect(
            shortLine(at: krasnodar),
            MilestoneDetector.History(visitedRegionIds: ["RU-KDA"]))

        XCTAssertTrue(hits.isEmpty)
    }

    func testThreeRegionsInOneTrip() {
        let track = shortLine(at: rostov) + shortLine(at: krasnodar) + shortLine(at: stavropol)
        let hits = detect(track, MilestoneDetector.History(
            visitedRegionIds: ["RU-ROS", "RU-KDA", "RU-STA"]))

        XCTAssertEqual(hits.map(\.milestone), [.threeRegionsDay])
        XCTAssertTrue(hits[0].key.hasPrefix("threeRegionsDay:"))
        XCTAssertNotNil(hits[0].key.range(of: #"^threeRegionsDay:\d{4}-\d{2}-\d{2}$"#, options: .regularExpression))
    }

    func testTwoRegionsAreNotADay() {
        let track = shortLine(at: rostov) + shortLine(at: krasnodar)
        let hits = detect(track, MilestoneDetector.History(visitedRegionIds: ["RU-ROS", "RU-KDA"]))

        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - Экстремумы

    func testGoingEastOfThePreviousRecord() {
        let history = MilestoneDetector.History(
            visitedRegionIds: ["RU-STA"],
            extremes: MilestoneDetector.Extremes(
                north: rostov, south: krasnodar, east: krasnodar, west: krasnodar))

        let hits = detect(shortLine(at: stavropol), history)

        XCTAssertEqual(hits.map(\.milestone), [.easternmost])
        XCTAssertNotNil(hits[0].key.range(of: #"^easternmost:\d{4}-\d{2}-\d{2}$"#, options: .regularExpression))
        XCTAssertEqual(hits[0].coordinate.longitude, stavropol.longitude, accuracy: 0.01)
    }

    func testFirstTripSetsExtremesWithoutAMilestone() {
        let hits = detect(shortLine(at: stavropol), MilestoneDetector.History(visitedRegionIds: ["RU-STA"]))

        XCTAssertTrue(hits.isEmpty, "сравнивать не с чем — молчим")
    }

    func testStayingInsideThePreviousRecordIsNoMilestone() {
        let history = MilestoneDetector.History(
            visitedRegionIds: ["RU-KDA"],
            extremes: MilestoneDetector.Extremes(
                north: rostov, south: CLLocationCoordinate2D(latitude: 41.0, longitude: 38.0),
                east: stavropol, west: CLLocationCoordinate2D(latitude: 45.0, longitude: 30.0)))

        XCTAssertTrue(detect(shortLine(at: krasnodar), history).isEmpty)
    }

    // MARK: - Высота

    func testAltitudeAboveTwoThousand() {
        let history = MilestoneDetector.History(visitedRegionIds: ["RU-KDA"])
        let hits = detect(shortLine(at: krasnodar, altitude: 2100), history)

        XCTAssertEqual(hits.map(\.milestone), [.above2000])
        // Ключа-суффикса нет нарочно: два километра берутся раз в жизни.
        XCTAssertEqual(hits[0].key, "above2000")

        XCTAssertTrue(detect(shortLine(at: krasnodar, altitude: 1900), history).isEmpty)
    }

    func testBelowSeaLevel() {
        let history = MilestoneDetector.History(visitedRegionIds: ["RU-KDA"])
        let hits = detect(shortLine(at: krasnodar, altitude: -20), history)

        XCTAssertEqual(hits.map(\.milestone), [.belowSea])
        XCTAssertEqual(hits[0].key, "belowSea")

        // Ноль — это любой морской берег плюс шум GPS, а не веха.
        XCTAssertTrue(detect(shortLine(at: krasnodar, altitude: 0), history).isEmpty)
    }

    // MARK: - Ночь

    func testNightPassNeedsBothHeightAndHour() {
        let history = MilestoneDetector.History(visitedRegionIds: ["RU-KDA"])
        let night = at(hour: 23)
        let noon = at(hour: 12)

        let hits = detect(shortLine(at: krasnodar, altitude: 1600, startingAt: night), history)
        XCTAssertEqual(hits.map(\.milestone), [.nightPass])
        XCTAssertNotNil(hits[0].key.range(of: #"^nightPass:\d{4}-\d{2}-\d{2}$"#, options: .regularExpression))

        XCTAssertTrue(detect(shortLine(at: krasnodar, altitude: 1600, startingAt: noon), history).isEmpty,
                      "полдень — не ночь")
        XCTAssertTrue(detect(shortLine(at: krasnodar, altitude: 900, startingAt: night), history).isEmpty,
                      "девятьсот метров — не перевал")
    }

    private func at(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 18
        components.hour = hour
        components.minute = 10
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Граница

    /// Военно-Грузинская дорога: Верхний Ларс — Степанцминда. Коды в ключе
    /// отсортированы, поэтому «туда» и «обратно» дают одну и ту же веху.
    func testCrossingIntoGeorgia() {
        let track = DiscoveryTrackFixtures.line(
            from: CLLocationCoordinate2D(latitude: 42.80, longitude: 44.64),
            to: CLLocationCoordinate2D(latitude: 42.70, longitude: 44.64))
        let regions = Set(track.compactMap { atlas.region(containing: $0.coordinate)?.id })
        let hits = detect(track, MilestoneDetector.History(visitedRegionIds: regions))

        XCTAssertEqual(hits.map(\.milestone), [.countryBorder])
        XCTAssertEqual(hits[0].key, "countryBorder:GE-RU")

        let backwards = detect(
            Array(track.reversed()), MilestoneDetector.History(visitedRegionIds: regions))
        XCTAssertEqual(backwards.map(\.key), ["countryBorder:GE-RU"])
    }

    func testStayingInOneCountryIsNoBorder() {
        let track = shortLine(at: rostov) + shortLine(at: krasnodar)
        let hits = detect(track, MilestoneDetector.History(visitedRegionIds: ["RU-ROS", "RU-KDA"]))

        XCTAssertFalse(hits.contains { $0.milestone == .countryBorder })
    }

    // MARK: - Вырожденное

    func testEmptyTrackIsSilent() {
        XCTAssertTrue(detect([], MilestoneDetector.History()).isEmpty)
    }
}
