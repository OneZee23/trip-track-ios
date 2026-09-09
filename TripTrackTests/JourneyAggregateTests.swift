import XCTest
import CoreLocation
@testable import TripTrack

final class JourneyAggregateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)   // 09:00 местного условно
    private let krd = CLLocationCoordinate2D(latitude: 45.03, longitude: 38.98)
    private let vld = CLLocationCoordinate2D(latitude: 43.02, longitude: 44.68)
    private let tbs = CLLocationCoordinate2D(latitude: 41.72, longitude: 44.79)

    private func trip(day: Int, hour: Double, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                      km: Double, hours: Double, region: String? = nil) -> Trip {
        let start = t0.addingTimeInterval(Double(day) * 86_400 + hour * 3_600)
        let pts = [TrackPoint(latitude: from.latitude, longitude: from.longitude, timestamp: start),
                   TrackPoint(latitude: to.latitude, longitude: to.longitude, timestamp: start.addingTimeInterval(hours * 3_600))]
        return Trip(id: UUID(), startDate: start, endDate: start.addingTimeInterval(hours * 3_600),
                    distance: km * 1_000, maxSpeed: 30, averageSpeed: 25, trackPoints: pts, photos: [],
                    title: nil, fuelUsed: 0, elevation: 0, region: region, isPrivate: true, earnedBadgeIds: [], xpEarned: 0)
    }

    private var georgia: [Trip] {[
        trip(day: 0, hour: 9, from: krd, to: vld, km: 480, hours: 5.2, region: "Краснодарский край"),
        trip(day: 1, hour: 9, from: vld, to: tbs, km: 210, hours: 4.8, region: "Северная Осетия"),
        trip(day: 2, hour: 11, from: tbs, to: CLLocationCoordinate2D(latitude: 41.75, longitude: 44.80), km: 8, hours: 0.4),
        trip(day: 3, hour: 12, from: tbs, to: CLLocationCoordinate2D(latitude: 41.84, longitude: 44.72), km: 22, hours: 0.7),
        trip(day: 4, hour: 9, from: tbs, to: vld, km: 210, hours: 4.7),
        trip(day: 5, hour: 9, from: vld, to: krd, km: 480, hours: 5.2),
    ]}

    func testLocalTripsAroundTheStayFoldIntoOneItem() {
        let a = JourneyAggregate.build(trips: georgia)
        XCTAssertEqual(a.legCount, 4, "плечи дороги — без местных")
        XCTAssertEqual(a.calendarDays, 6)
        XCTAssertEqual(Int(a.totalMetres / 1000), 1_410)
        let local = a.days.flatMap(\.items).compactMap { item -> [Trip]? in
            if case .local(let trips, _) = item { return trips } else { return nil }
        }
        XCTAssertEqual(local.count, 1)
        XCTAssertEqual(local[0].count, 2)
    }

    func testDaysAreNumberedFromTheFirstLeg() {
        let a = JourneyAggregate.build(trips: georgia)
        XCTAssertEqual(a.days.map(\.number), [1, 2, 3, 5, 6])   // дни 3–4 сложились в одну «стоянку» под номером первого
        XCTAssertEqual(a.days[0].items.count, 1)
    }

    func testDefaultTitleIsFirstStartToFarthestEnd() {
        let a = JourneyAggregate.build(trips: georgia)
        XCTAssertEqual(a.defaultTitle(startName: "Краснодар", farthestName: "Тбилиси"), "Краснодар — Тбилиси")
        XCTAssertEqual(a.farthestEnd?.latitude ?? 0, tbs.latitude, accuracy: 0.2)
    }

    func testEmptyInputGivesEmptyAggregate() {
        let a = JourneyAggregate.build(trips: [])
        XCTAssertTrue(a.days.isEmpty); XCTAssertEqual(a.legCount, 0)
    }
}
