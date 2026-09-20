import XCTest
import CoreLocation
@testable import TripTrack

/// Редизайн ручной поездки 20 сен 2026 — чистые функции, которые решение
/// владельца выносит из открытого листа: активное поле для чипа, автослежение
/// длительности за маршрутом, границы дат «Сегодня»/«Вчера», пресет обратной
/// дороги, топ-3 частых места, итоговая строка кнопки.
final class ManualTripDesignTests: XCTestCase {

    // MARK: - ManualTripActiveField

    func testActiveFieldGoesToFromFirst() {
        XCTAssertEqual(ManualTripActiveField.resolve(from: nil, to: nil), .from)
    }

    func testActiveFieldGoesToToOnceFromIsSet() {
        let point = ManualTripPoint(name: "A", coordinate: CLLocationCoordinate2D())
        XCTAssertEqual(ManualTripActiveField.resolve(from: point, to: nil), .to)
    }

    func testActiveFieldKeepsReplacingToOnceBothAreSet() {
        let point = ManualTripPoint(name: "A", coordinate: CLLocationCoordinate2D())
        XCTAssertEqual(ManualTripActiveField.resolve(from: point, to: point), .to)
    }

    // MARK: - ManualTripDurationPolicy

    func testDurationPolicyFollowsSuggestionWhenNotTouched() {
        let resolved = ManualTripDurationPolicy.resolve(
            current: 3600, suggested: 5410, touched: false, step: 900)
        // 5410 с = 90.1 мин → округляется к ближайшим 15 мин (90 мин = 5400 с).
        XCTAssertEqual(resolved, 5400)
    }

    func testDurationPolicyLeavesTouchedValueAlone() {
        let resolved = ManualTripDurationPolicy.resolve(
            current: 3600, suggested: 9999, touched: true, step: 900)
        XCTAssertEqual(resolved, 3600, "тронутую рукой длительность пересчёт маршрута не имеет права переписать")
    }

    func testDurationPolicyIgnoresMissingSuggestion() {
        let resolved = ManualTripDurationPolicy.resolve(
            current: 3600, suggested: nil, touched: false, step: 900)
        XCTAssertEqual(resolved, 3600)
    }

    // MARK: - ManualTripDateDefaults

    func testDefaultStartDateIsNineAM() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let result = ManualTripDateDefaults.defaultStartDate(forDay: day, now: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    func testDefaultStartDateNeverGoesIntoTheFuture() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 7))!
        // «Сегодня» до девяти утра: 09:00 сегодняшнего дня ещё не наступило.
        let result = ManualTripDateDefaults.defaultStartDate(forDay: today, now: today, calendar: calendar)
        XCTAssertEqual(result, today)
    }

    func testBoundsNeverInvert() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Дата в базе БУДУЩАЯ (испорченная запись) — граница обязана
        // остаться валидным диапазоном, а не упасть на построении `a...b`.
        let corrupted = now.addingTimeInterval(999_999)
        let bounds = ManualTripDateDefaults.bounds(for: corrupted, now: now)
        XCTAssertLessThanOrEqual(bounds.lowerBound, bounds.upperBound)
        XCTAssertEqual(bounds.upperBound, corrupted)
    }

    func testBoundsCoverAnOrdinaryPastDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = now.addingTimeInterval(-3600)
        let bounds = ManualTripDateDefaults.bounds(for: past, now: now)
        XCTAssertTrue(bounds.contains(past))
        XCTAssertTrue(bounds.contains(now))
    }

    // MARK: - ManualTripPreset

    func testReturnTripSwapsPointsAndKeepsVehicle() {
        let from = ManualTripPoint(name: "Дом", coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39))
        let to = ManualTripPoint(name: "Море", coordinate: CLLocationCoordinate2D(latitude: 44, longitude: 38))
        let vehicle = UUID()
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let preset = ManualTripPreset.returnTrip(
            from: from, to: to, vehicleId: vehicle, firstTripEnd: end, now: end.addingTimeInterval(86_400))
        XCTAssertEqual(preset.from?.name, "Море")
        XCTAssertEqual(preset.to?.name, "Дом")
        XCTAssertEqual(preset.vehicleId, vehicle)
        XCTAssertEqual(preset.startDate, end.addingTimeInterval(3600))
    }

    func testReturnTripStartNeverGoesIntoTheFuture() {
        let from = ManualTripPoint(name: "A", coordinate: CLLocationCoordinate2D())
        let to = ManualTripPoint(name: "B", coordinate: CLLocationCoordinate2D())
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        // «Сейчас» наступает раньше «конец + час» — типичный случай короткой
        // первой поездки, вписанной почти сразу же после неё.
        let now = end.addingTimeInterval(1800)
        let preset = ManualTripPreset.returnTrip(from: from, to: to, vehicleId: nil, firstTripEnd: end, now: now)
        XCTAssertEqual(preset.startDate, now)
    }

    func testForDaySetsOnlyTheDate() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let preset = ManualTripPreset.forDay(day, now: day.addingTimeInterval(86_400))
        XCTAssertNil(preset.from)
        XCTAssertNil(preset.to)
        XCTAssertNotNil(preset.startDate)
    }

    // MARK: - ManualTripFrequentPlaces

    func testTopPlacesOrdersByPassCountDescending() {
        let places = [
            Place(id: UUID(), cell: "a", latitude: 1, longitude: 1, name: "Раз", createdAt: Date()),
            Place(id: UUID(), cell: "b", latitude: 2, longitude: 2, name: "Два", createdAt: Date()),
            Place(id: UUID(), cell: "c", latitude: 3, longitude: 3, name: "Три", createdAt: Date())
        ]
        let counts: [UUID: Int] = [places[0].id: 2, places[1].id: 9, places[2].id: 5]
        let top = ManualTripFrequentPlaces.top(places, passCount: { counts[$0] ?? 0 })
        XCTAssertEqual(top.map(\.name), ["Два", "Три", "Раз"])
    }

    func testTopPlacesExcludesZeroPasses() {
        let places = [
            Place(id: UUID(), cell: "a", latitude: 1, longitude: 1, name: "Есть проезды", createdAt: Date()),
            Place(id: UUID(), cell: "b", latitude: 2, longitude: 2, name: "Свежее место", createdAt: Date())
        ]
        let counts: [UUID: Int] = [places[0].id: 1, places[1].id: 0]
        let top = ManualTripFrequentPlaces.top(places, passCount: { counts[$0] ?? 0 })
        XCTAssertEqual(top.map(\.name), ["Есть проезды"])
    }

    func testTopPlacesCapsAtLimit() {
        let places = (0..<5).map {
            Place(id: UUID(), cell: "\($0)", latitude: 0, longitude: 0, name: "П\($0)", createdAt: Date())
        }
        let top = ManualTripFrequentPlaces.top(places, passCount: { _ in 3 }, limit: 3)
        XCTAssertEqual(top.count, 3)
    }

    // MARK: - ManualTripSummaryLine

    func testSummaryLineJoinsWithMiddleDot() {
        let line = ManualTripSummaryLine.compose(distance: "420 км", duration: "5 ч 30 мин", when: "вчера 09:00")
        XCTAssertEqual(line, "420 км · 5 ч 30 мин · вчера 09:00")
    }
}
