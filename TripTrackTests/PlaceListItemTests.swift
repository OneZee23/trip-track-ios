import XCTest
@testable import TripTrack

/// Строка списка мест: «обычно» — медиана главного направления, иначе по
/// всем; чипы — подписи по числу проездов; порядок — по последнему проезду.
final class PlaceListItemTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private func place(_ name: String) -> Place {
        let cell = Place.cell(latitude: 44.3196, longitude: 38.7089)
        return Place(id: UUID(), cell: cell, latitude: 44.3196, longitude: 38.7089, name: name, createdAt: now)
    }
    private func pass(_ p: Place, daysAgo: Double, course: Double, elapsed: TimeInterval) -> PlacePass {
        PlacePass(placeId: p.id, tripId: UUID(), timestamp: now.addingTimeInterval(-daysAgo * 86_400),
                  elapsedFromStart: elapsed, distanceFromStart: 1000, course: course)
    }

    func testUsualIsTheTopDirectionMedian() {
        let p = place("Джубга")
        let passes = [pass(p, daysAgo: 1, course: 0, elapsed: 8040), pass(p, daysAgo: 2, course: 3, elapsed: 7680),
                      pass(p, daysAgo: 3, course: 358, elapsed: 9060), pass(p, daysAgo: 4, course: 180, elapsed: 7080)]
        let item = PlaceListItem.build(place: p, passes: passes, now: now)
        XCTAssertEqual(item.usual, 8040)
        XCTAssertEqual(item.lastAt, now.addingTimeInterval(-86_400))
        XCTAssertFalse(item.isFirstTime); XCTAssertFalse(item.isFrequentGuest)
    }

    func testUsualFallsBackToOverallMedianWithoutCourses() {
        let p = place("Пост")
        let passes = [pass(p, daysAgo: 1, course: -1, elapsed: 100), pass(p, daysAgo: 2, course: -1, elapsed: 300)]
        XCTAssertEqual(PlaceListItem.build(place: p, passes: passes, now: now).usual, 200)
        XCTAssertNil(PlaceListItem.build(place: p, passes: [], now: now).usual)
    }

    /// Один проезд — не «обычно» (см. PlaceChip.build): карточка иначе
    /// печатает «обычно …» прямо над чипом «Первый раз здесь».
    func testSinglePassHasNoUsual() {
        let p = place("Гараж")
        let item = PlaceListItem.build(place: p, passes: [pass(p, daysAgo: 1, course: 0, elapsed: 500)], now: now)
        XCTAssertNil(item.usual)
    }

    func testChipsAndSorting() {
        let a = place("А"), b = place("Б"), c = place("В")
        let ia = PlaceListItem.build(place: a, passes: [pass(a, daysAgo: 10, course: 0, elapsed: 1)], now: now)
        let ib = PlaceListItem.build(place: b, passes: (0..<5).map { pass(b, daysAgo: Double($0 + 1), course: 0, elapsed: 1) }, now: now)
        let ic = PlaceListItem.build(place: c, passes: [], now: now)
        XCTAssertTrue(ia.isFirstTime); XCTAssertTrue(ib.isFrequentGuest); XCTAssertNil(ic.lastAt)
        XCTAssertEqual(PlaceListItem.sorted([ia, ic, ib]).map(\.place.name), ["Б", "А", "В"])
    }

    /// Оба места без имени и без проездов — ветка `(nil, nil)` у обоих ключей
    /// сравнения сразу: `"" < ""` не крашит, порядок стабилен (Swift `sorted`
    /// гарантированно стабилен), элементы не теряются.
    func testSortedStableForTwoNamelessEmptyPlaces() {
        let cell = Place.cell(latitude: 44.3196, longitude: 38.7089)
        let a = Place(id: UUID(), cell: cell, latitude: 44.3196, longitude: 38.7089, name: nil, createdAt: now)
        let b = Place(id: UUID(), cell: cell, latitude: 44.3196, longitude: 38.7089, name: nil, createdAt: now)
        let ia = PlaceListItem.build(place: a, passes: [], now: now)
        let ib = PlaceListItem.build(place: b, passes: [], now: now)
        XCTAssertEqual(PlaceListItem.sorted([ia, ib]).map(\.place.id), [a.id, b.id])
    }
}
