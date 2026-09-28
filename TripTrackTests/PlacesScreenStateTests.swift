import XCTest
import CoreGraphics
@testable import TripTrack

/// Пустая вкладка и поиск — два вопроса, которые до 0.8.2 решались в `body`
/// одной строкой каждый и оба неверно. Здесь они чистые функции с таблицей.
final class PlacesScreenStateTests: XCTestCase {

    private let fifteen = PlacesSlot(height: 844, safeTop: 48, safeBottom: 34)
    private let se = PlacesSlot(height: 667, safeTop: 20, safeBottom: 0)

    // MARK: Пустая вкладка (13, 14, 15)

    /// Главная правка: ПОДСКАЗКИ НЕ ОТМЕНЯЮТ ПУСТОТУ. До 0.8.2 условие было
    /// «нет мест И нет подсказок», и вкладка с подсказкой, но без мест
    /// вставала на половину (380) вместо пустой (280) — по матрице состояние
    /// 14 стоит там же, где 13.
    func testSuggestionsDoNotCancelTheEmptyTab() {
        XCTAssertEqual(PlacesEmptyState.resolve(places: 0, trips: 3), .noPlaces)
        XCTAssertEqual(PlacesEmptyState.resolve(places: 0, trips: 1), .noPlaces,
                       "одна поездка — уже состояние 13/14, а не 15")
        XCTAssertEqual(PlacesEmptyState.resolve(places: 0, trips: 3).stop(in: fifteen), .empty)
        XCTAssertEqual(fifteen.top(of: .empty), 280)
    }

    func testNoTripsAtAllStandsAtTheDefaultStop() {
        let state = PlacesEmptyState.resolve(places: 0, trips: 0)
        XCTAssertEqual(state, .noTrips)
        // Состояние 15 спеки: «панель, таб-бар − 374», то есть половина.
        XCTAssertEqual(state.stop(in: fifteen), .half)
        XCTAssertEqual(fifteen.top(of: .half), 380)
        // На SE половины нет вовсе — там умолчание это список.
        XCTAssertEqual(state.stop(in: se), .list)
    }

    func testAPlaceEndsEveryEmptyState() {
        for trips in 0...3 {
            XCTAssertEqual(PlacesEmptyState.resolve(places: 1, trips: trips), PlacesEmptyState.notEmpty)
        }
        XCTAssertEqual(PlacesEmptyState.notEmpty.stop(in: fifteen), fifteen.defaultStop)
    }

    /// Пустые состояния держат одно положение и не тянутся (спека §4), а
    /// `.empty` ещё и НЕДОСТИЖИМО ПАЛЬЦЕМ — его нет среди тянущихся.
    func testEmptyStopsArePinnedAndUnreachableByFinger() {
        XCTAssertTrue(PlacesEmptyState.noPlaces.isPinned)
        XCTAssertTrue(PlacesEmptyState.noTrips.isPinned)
        XCTAssertFalse(PlacesEmptyState.notEmpty.isPinned)

        XCTAssertFalse(PlacesPanelStop.empty.isDraggable)
        XCTAssertFalse(fifteen.reachableStops.contains(.empty))
        XCTAssertFalse(se.reachableStops.contains(.empty))
        // И жест в него не приводит ни с какой высоты и ни с какой скоростью.
        for top in stride(from: CGFloat(0), through: 844, by: 20) {
            for velocity in [CGFloat(-900), 0, 900] {
                let landed = fifteen.settle(top: top, velocity: velocity, from: .half)
                XCTAssertNotEqual(landed, .empty)
            }
        }
    }

    // MARK: Поиск (10 и 11)

    func testEmptyQueryIsNotASearch() {
        XCTAssertEqual(PlacesSearchOutcome.resolve(query: "", matches: 0), .idle)
        XCTAssertEqual(PlacesSearchOutcome.resolve(query: "   ", matches: 0), .idle,
                       "поле с одним пробелом — ещё не поиск")
        XCTAssertEqual(PlacesSearchOutcome.resolve(query: "\n\t ", matches: 12), .idle)
    }

    func testMatchesAndNothingFound() {
        XCTAssertEqual(PlacesSearchOutcome.resolve(query: "дач", matches: 2), .matches)
        XCTAssertEqual(PlacesSearchOutcome.resolve(query: "дач", matches: 0), .nothingFound)
        XCTAssertEqual(PlacesSearchOutcome.resolve(query: "  дач  ", matches: 0), .nothingFound,
                       "пробелы по краям не делают запрос пустым")
    }

    /// Совпадения показываются БЕЗ заголовка секции, но и без группировки:
    /// экран зовёт `filter` + `sort`, а не `build`, и на этом пути групп нет
    /// физически — проверяем, что фильтр действительно отвечает списком.
    func testSearchPathNeverGroups() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let items = (0..<10).map { index -> PlaceListItem in
            PlaceListItem(
                place: Place(id: UUID(), cell: "ucfv0j\(index)", latitude: 45, longitude: 39,
                             name: "Дача \(index)", createdAt: day),
                stats: PlaceStats(passCount: index, firstAt: day, lastAt: day,
                                  medianElapsed: 600, isFrequentGuest: false, directions: []),
                usual: 600)
        }
        let found = PlacesPresentation.filter(items, query: "Дача 3", language: .ru)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(PlacesSearchOutcome.resolve(query: "Дача 3", matches: found.count), .matches)

        let none = PlacesPresentation.filter(items, query: "Море", language: .ru)
        XCTAssertEqual(PlacesSearchOutcome.resolve(query: "Море", matches: none.count), .nothingFound)
    }
}
