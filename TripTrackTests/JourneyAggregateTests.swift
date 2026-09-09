import XCTest
import CoreLocation
@testable import TripTrack

final class JourneyAggregateTests: XCTestCase {
    // Полночь по местному, а не сырой epoch: иначе "hour: 9" означает 9 часов
    // от случайного момента суток внутри epoch-времени, а не 9:00 утра, и на
    // машине в другом поясе плечо может уползти за полночь там, где на
    // авторской машине — нет.
    private let t0 = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
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

    /// Город → трасса → город в ОДИН день: две отдельные стоянки в одном дне.
    ///
    /// Экран путешествия держит и имя стоянки, и её раскрытие по ключу, и ключ
    /// этот однажды был номером дня — то есть у обеих стоянок одинаковый.
    /// Раскрывалась бы одна, раскрывались бы обе, а имя второго города
    /// подписывало бы первый.
    func testTwoLocalGroupsCanShareOneDay() {
        let near = CLLocationCoordinate2D(latitude: 45.06, longitude: 39.02)
        let a = JourneyAggregate.build(trips: [
            trip(day: 0, hour: 8, from: krd, to: krd, km: 6, hours: 0.3),
            trip(day: 0, hour: 10, from: krd, to: near, km: 9, hours: 0.4),
            trip(day: 0, hour: 12, from: krd, to: vld, km: 480, hours: 5),
            trip(day: 0, hour: 19, from: vld, to: vld, km: 7, hours: 0.3),
            trip(day: 0, hour: 21, from: vld, to: vld, km: 5, hours: 0.2),
        ])
        XCTAssertEqual(a.days.count, 1)
        let groups = a.days[0].items.compactMap { item -> [Trip]? in
            if case .local(let trips, _) = item { return trips } else { return nil }
        }
        XCTAssertEqual(groups.count, 2, "две стоянки в одном дне — два отдельных пункта")
        XCTAssertEqual(groups[0].count, 2)
        XCTAssertEqual(groups[1].count, 2)
        // Ключ, которым экран различает стоянки: id первой поездки каждой.
        XCTAssertNotEqual(groups[0].first?.id, groups[1].first?.id)
    }

    func testEmptyInputGivesEmptyAggregate() {
        let a = JourneyAggregate.build(trips: [])
        XCTAssertTrue(a.days.isEmpty); XCTAssertEqual(a.legCount, 0)
    }

    func testOvernightLegCountsTheDayItFinishesOn() {
        let night = trip(day: 0, hour: 22, from: krd, to: vld, km: 480, hours: 4)
        let a = JourneyAggregate.build(trips: [night])
        XCTAssertEqual(a.calendarDays, 2, "старт в 22:00 + 4 часа — финиш уже на следующий день")
        XCTAssertEqual(a.days.map(\.number), [1])
    }
}
