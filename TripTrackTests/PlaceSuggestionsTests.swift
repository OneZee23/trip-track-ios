import XCTest
import CoreLocation
@testable import TripTrack

/// Подсказки «Похоже, вы здесь бываете» — чистый счёт по концам превью.
///
/// Всё, что здесь проверяется, — арифметика и правила отбора: кластеризация
/// по той же ячейке, что у места, исключение живых мест и надгробий, порог
/// 2 (или 1 у новичка), порядок и потолок.
final class PlaceSuggestionsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    /// Краснодар — «дом» в этих фикстурах.
    private let home = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
    private let sea = CLLocationCoordinate2D(latitude: 44.561, longitude: 38.077)
    private let rostov = CLLocationCoordinate2D(latitude: 47.222, longitude: 39.719)

    /// Превью — две точки: старт и финиш. Больше подсказке и не нужно.
    private func preview(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D,
                         daysAgo: Int = 0) -> TripPreviewRef {
        TripPreviewRef(id: UUID(),
                       startDate: t0.addingTimeInterval(-Double(daysAgo) * 86_400),
                       previewPolyline: Trip.encodePolyline([from, to]))
    }

    private func cell(_ c: CLLocationCoordinate2D) -> String {
        Place.cell(latitude: c.latitude, longitude: c.longitude)
    }

    // MARK: - Кластеризация

    func testEndsOfTripsClusterIntoTheSameGeohashCell() {
        // Дом — конец четырёх поездок, море — двух, Ростов — одной.
        let previews = [
            preview(home, sea, daysAgo: 3),
            preview(home, rostov, daysAgo: 2),
            preview(home, sea, daysAgo: 1),
            preview(home, home, daysAgo: 40),
        ]
        let found = PlaceSuggestions.build(previews: previews, taken: [])
        let byCell = Dictionary(uniqueKeysWithValues: found.map { ($0.cell, $0.trips) })
        XCTAssertEqual(byCell[cell(home)], 4, "четыре поездки коснулись дома концом")
        XCTAssertEqual(byCell[cell(sea)], 2)
        XCTAssertEqual(byCell[cell(rostov)], 1)
        XCTAssertEqual(found.first?.cell, cell(home), "самая частая ячейка — первой")
    }

    /// Круг по городу — один голос, а не два: строка говорит «N ПОЕЗДОК
    /// начинались или заканчивались здесь», и двойка там была бы неправдой.
    func testRoundTripVotesOnceForItsOwnCell() {
        let loop = preview(home, home, daysAgo: 1)
        let second = preview(home, sea, daysAgo: 2)
        let found = PlaceSuggestions.build(previews: [loop, second], taken: [])
        XCTAssertEqual(found.first(where: { $0.cell == cell(home) })?.trips, 2)
    }

    /// Центроид — по настоящим концам, а не по центру ячейки: середина
    /// квадрата в 150 м лежит не там, где человек паркуется.
    func testCentroidAveragesTheActualEnds() throws {
        let a = CLLocationCoordinate2D(latitude: 45.0350, longitude: 38.9750)
        let b = CLLocationCoordinate2D(latitude: 45.03505, longitude: 38.97505)
        try XCTSkipIf(cell(a) != cell(b), "фикстура обязана лежать в одной ячейке")
        let found = PlaceSuggestions.build(
            previews: [preview(a, sea), preview(b, rostov)], taken: [])
        let suggestion = try XCTUnwrap(found.first { $0.cell == cell(a) })
        // Допуск — не «примерно середина», а точность ХРАНЕНИЯ: превью
        // кодируется float32 (`Trip.encodePolyline`), то есть около метра
        // на этих широтах. Считать точнее, чем лежит в базе, нечего.
        XCTAssertEqual(suggestion.latitude, (a.latitude + b.latitude) / 2, accuracy: 1e-5)
        XCTAssertEqual(suggestion.longitude, (a.longitude + b.longitude) / 2, accuracy: 1e-5)
    }

    // MARK: - Порог

    func testTwoHitsAreNeededOnceTheLibraryIsBigEnough() {
        // Пять поездок — обычный порог: одиночный конец не предлагается.
        let previews = (0..<5).map { preview(home, sea, daysAgo: $0) }
            + [preview(rostov, CLLocationCoordinate2D(latitude: 43.4, longitude: 39.9), daysAgo: 9)]
        let cells = Set(PlaceSuggestions.build(previews: previews, taken: []).map(\.cell))
        XCTAssertTrue(cells.contains(cell(home)))
        XCTAssertFalse(cells.contains(cell(rostov)), "один конец — ещё не привычка")
    }

    func testASingleHitIsEnoughWhileTheLibraryIsTiny() {
        // Человек с одной поездкой — тот самый, ради кого подсказки и
        // заведены: на пороге 2 экран остался бы пустым.
        let found = PlaceSuggestions.build(previews: [preview(home, sea)], taken: [])
        XCTAssertEqual(Set(found.map(\.cell)), [cell(home), cell(sea)])
    }

    func testThresholdFlipsExactlyAtTheSmallLibraryBoundary() {
        XCTAssertEqual(PlaceSuggestions.smallLibrary, 5)
        let lonely = CLLocationCoordinate2D(latitude: 43.585, longitude: 39.723)
        // Четыре поездки — библиотека ещё «маленькая», одиночный конец проходит.
        let four = (0..<3).map { preview(home, sea, daysAgo: $0) } + [preview(lonely, lonely, daysAgo: 8)]
        XCTAssertTrue(PlaceSuggestions.build(previews: four, taken: []).map(\.cell).contains(cell(lonely)))
        // Пятая поездка — и тот же одиночный конец уже не подсказка.
        let five = four + [preview(home, sea, daysAgo: 9)]
        XCTAssertFalse(PlaceSuggestions.build(previews: five, taken: []).map(\.cell).contains(cell(lonely)))
    }

    // MARK: - Что предлагать нельзя

    func testExistingPlacesAreNeverSuggested() {
        let previews = (0..<4).map { preview(home, sea, daysAgo: $0) }
        let taken: Set<UUID> = [Place.id(forCell: cell(home))]
        let cells = Set(PlaceSuggestions.build(previews: previews, taken: taken).map(\.cell))
        XCTAssertFalse(cells.contains(cell(home)))
        XCTAssertTrue(cells.contains(cell(sea)), "остальные ячейки не задеты")
    }

    /// Надгробие: место удалили, но `placeId` остался у отметок. Подсказка
    /// не имеет права предложить его заново — человек уже отказался.
    func testTombstonedPlacesStayForgotten() {
        let previews = (0..<4).map { preview(home, sea, daysAgo: $0) }
        let tombstone: Set<UUID> = [Place.id(forCell: cell(sea))]
        let cells = Set(PlaceSuggestions.build(previews: previews, taken: tombstone).map(\.cell))
        XCTAssertFalse(cells.contains(cell(sea)))
    }

    func testTripsWithoutAPreviewAreSkipped() {
        let blind = TripPreviewRef(id: UUID(), startDate: t0, previewPolyline: nil)
        XCTAssertTrue(PlaceSuggestions.build(previews: [blind], taken: []).isEmpty)
    }

    // MARK: - Порядок и потолок

    func testSortedByHitsThenRecency() {
        // Дом — три поездки давным-давно, море — две на прошлой неделе.
        // Каждой поездке даётся СВОЙ дальний конец, чтобы он не набрал
        // голосов и не влез между ними.
        func far(_ k: Int) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: 46.0 + Double(k) * 0.2, longitude: 40.0)
        }
        let previews = [
            preview(home, far(0), daysAgo: 30),
            preview(home, far(1), daysAgo: 29),
            preview(home, far(2), daysAgo: 28),
            preview(sea, far(3), daysAgo: 1),
            preview(sea, far(4), daysAgo: 2),
        ]
        let found = PlaceSuggestions.build(previews: previews, taken: [])
        XCTAssertEqual(found.map(\.cell), [cell(home), cell(sea)], "чаще — выше, даже если давно")
        XCTAssertEqual(found.first?.trips, 3)
    }

    func testEqualCountsFallBackToTheFresherOne() {
        let old = CLLocationCoordinate2D(latitude: 45.10, longitude: 38.90)
        let fresh = CLLocationCoordinate2D(latitude: 45.20, longitude: 38.80)
        func far(_ k: Int) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: 46.0 + Double(k) * 0.2, longitude: 40.0)
        }
        let previews = [
            preview(old, far(0), daysAgo: 10), preview(old, far(1), daysAgo: 11),
            preview(fresh, far(2), daysAgo: 1), preview(fresh, far(3), daysAgo: 2),
        ]
        let found = PlaceSuggestions.build(previews: previews, taken: [])
        // Дальние концы тоже попадают (библиотека маленькая, порог 1), но
        // у них по одному голосу — проверяем голову списка.
        XCTAssertEqual(Array(found.prefix(2)).map(\.cell), [cell(fresh), cell(old)])
    }

    func testNeverMoreThanFive() {
        // Десять разных дворов, каждый по два раза.
        var previews: [TripPreviewRef] = []
        for k in 0..<10 {
            let spot = CLLocationCoordinate2D(latitude: 45.0 + Double(k) * 0.05, longitude: 38.5)
            previews.append(preview(spot, spot, daysAgo: k * 3))
            previews.append(preview(spot, rostov, daysAgo: k * 3 + 1))
        }
        let found = PlaceSuggestions.build(previews: previews, taken: [])
        XCTAssertEqual(found.count, PlaceSuggestions.limit)
        XCTAssertEqual(PlaceSuggestions.limit, 5)
    }

    /// Ячейка и id — те же, что у настоящего места: подсказка, ставшая
    /// местом, обязана получить тот же `Place.id(forCell:)` на любом телефоне.
    func testSuggestionIdMatchesThePlaceItWouldBecome() {
        let found = PlaceSuggestions.build(previews: [preview(home, sea)], taken: [])
        for suggestion in found {
            XCTAssertEqual(suggestion.id, Place.id(forCell: suggestion.cell))
        }
    }
}
