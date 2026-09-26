import XCTest
import CoreLocation
@testable import TripTrack

/// Поиск, порядок и группы вкладки «Места». Чистой функцией — потому что
/// «что человек увидит в списке» проверяется числом, а открытым экраном
/// проверяется только то, что он не упал.
final class PlacesPresentationTests: XCTestCase {

    private func item(_ name: String?, passes: Int, lastDaysAgo: Int,
                      frequent: Bool = false) -> PlaceListItem {
        let now = Date()
        let last = Calendar.current.date(byAdding: .day, value: -lastDaysAgo, to: now) ?? now
        let stats = PlaceStats(
            passCount: passes, firstAt: last, lastAt: last,
            medianElapsed: 600, isFrequentGuest: frequent, directions: [])
        let place = Place(id: UUID(), cell: "ucfv0j0", latitude: 45, longitude: 39,
                          name: name, createdAt: last)
        return PlaceListItem(place: place, stats: stats, usual: 600)
    }

    // MARK: Поиск

    func testSearchIgnoresCaseAndDiacritics() {
        let items = [item("Дача", passes: 3, lastDaysAgo: 1),
                     item("Работа", passes: 9, lastDaysAgo: 2)]
        XCTAssertEqual(PlacesPresentation.filter(items, query: "дач", language: .ru).count, 1)
        XCTAssertEqual(PlacesPresentation.filter(items, query: "  ", language: .ru).count, 2,
                       "пробелы — это пустой запрос, а не фильтр")
    }

    /// Место без имени ищется только пустым запросом: искать «Место без
    /// имени» по подстроке значило бы искать по подписи, которой в базе нет.
    func testUnnamedPlaceIsNotFoundByText() {
        let items = [item(nil, passes: 2, lastDaysAgo: 1)]
        XCTAssertEqual(PlacesPresentation.filter(items, query: "", language: .ru).count, 1)
        XCTAssertTrue(PlacesPresentation.filter(items, query: "мест", language: .ru).isEmpty)
    }

    // MARK: Порядок

    func testRecentIsTheOldOrderUntouched() {
        let items = [item("A", passes: 1, lastDaysAgo: 9), item("B", passes: 99, lastDaysAgo: 1)]
        XCTAssertEqual(PlacesPresentation.sort(items, by: .recent).map(\.place.name),
                       PlaceListItem.sorted(items).map(\.place.name))
    }

    func testFrequentOrdersByPassCount() {
        let items = [item("A", passes: 3, lastDaysAgo: 1), item("B", passes: 40, lastDaysAgo: 9)]
        XCTAssertEqual(PlacesPresentation.sort(items, by: .frequent).map(\.place.name), ["B", "A"])
    }

    func testNameOrderPutsUnnamedLast() {
        let items = [item(nil, passes: 5, lastDaysAgo: 1), item("Дача", passes: 2, lastDaysAgo: 5)]
        XCTAssertEqual(PlacesPresentation.sort(items, by: .name).map { $0.place.name ?? "—" },
                       ["Дача", "—"])
    }

    /// Ничьи решает прежний порядок, а не случай: иначе одинаковые строки
    /// меняются местами между перерисовками и список «дышит».
    func testTiesKeepTheRecentOrder() {
        let items = [item("A", passes: 5, lastDaysAgo: 1), item("B", passes: 5, lastDaysAgo: 4)]
        XCTAssertEqual(PlacesPresentation.sort(items, by: .frequent).map(\.place.name), ["A", "B"])
    }

    // MARK: Группы

    func testGroupsSplitFrequentGuestsFromTheRest() {
        let items = [item("A", passes: 40, lastDaysAgo: 1, frequent: true),
                     item("B", passes: 2, lastDaysAgo: 2)]
        let groups = PlacesPresentation.group(items, grouped: true)
        XCTAssertEqual(groups.map(\.kind), [.frequent, .others])
    }

    /// Группа, в которую попало ВСЁ, не группирует ничего, а заголовок над
    /// ней обещает остальных, которых нет.
    func testGroupingCollapsesWhenEverythingIsFrequent() {
        let items = [item("A", passes: 40, lastDaysAgo: 1, frequent: true),
                     item("B", passes: 30, lastDaysAgo: 2, frequent: true)]
        XCTAssertEqual(PlacesPresentation.group(items, grouped: true).map(\.kind), [.all])
    }

    // MARK: Всё вместе

    /// Форму списка задаёт РАЗМЕР БИБЛИОТЕКИ, а не размер выдачи: иначе
    /// поиск, сузивший список до трёх строк, менял бы ещё и его форму.
    func testSearchDoesNotChangeTheShapeOfTheList() {
        var items = (0..<PlacesPresentation.manyPlaces).map {
            item("Место \($0)", passes: 40 - $0, lastDaysAgo: $0, frequent: $0 < 2)
        }
        items.append(item("Дача", passes: 1, lastDaysAgo: 30))
        let grouped = PlacesPresentation.build(items, query: "", sort: .recent, language: .ru)
        XCTAssertEqual(grouped.map(\.kind), [.frequent, .others])

        let searched = PlacesPresentation.build(items, query: "Дача", sort: .recent, language: .ru)
        XCTAssertEqual(searched.map(\.kind), [.all], "поиск не группирует")
        XCTAssertEqual(searched.first?.items.count, 1)
    }

    func testEmptySearchResultProducesNoGroups() {
        let items = [item("Дача", passes: 2, lastDaysAgo: 1)]
        XCTAssertTrue(PlacesPresentation.build(items, query: "zzz", sort: .recent, language: .ru).isEmpty)
    }

    // MARK: Хранение порядка

    func testSortSurvivesRelaunchAndRejectsGarbage() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "places.sort.test"))
        defaults.removePersistentDomain(forName: "places.sort.test")
        XCTAssertEqual(PlacesSort.load(defaults: defaults), .recent, "умолчание — прежний порядок")
        PlacesSort.frequent.save(defaults: defaults)
        XCTAssertEqual(PlacesSort.load(defaults: defaults), .frequent)
        defaults.set("nonsense", forKey: "places.sort")
        XCTAssertEqual(PlacesSort.load(defaults: defaults), .recent,
                       "чужое значение из будущей версии не должно ронять список")
        defaults.removePersistentDomain(forName: "places.sort.test")
    }
}

/// Экран места: плитки дней и подпись «откуда → куда». Чистой функцией —
/// открытый экран отвечает только на «не упал ли он».
final class PlaceScreenTests: XCTestCase {

    private func pass(_ iso: String) -> PlacePass {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "Europe/Moscow")
        return PlacePass(id: UUID(), placeId: UUID(), tripId: UUID(),
                         timestamp: f.date(from: iso) ?? Date(),
                         elapsedFromStart: 600, distanceFromStart: 1000,
                         course: 90)
    }

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return c
    }()

    /// «Туда и обратно» в одно воскресенье — ОДНА плитка с числом, а не две
    /// одинаковые даты подряд.
    func testTwoPassesInOneDayCollapseIntoOneTile() {
        let tiles = PlaceScreen.tiles(from: [pass("2026-09-13T10:00:00+03:00"),
                                             pass("2026-09-13T19:00:00+03:00"),
                                             pass("2026-09-20T10:00:00+03:00")],
                                      calendar: calendar)
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(tiles.first?.count, 1, "свежий день первый")
        XCTAssertEqual(tiles.last?.count, 2)
    }

    func testTilesAreCappedAndOrderedNewestFirst() {
        let passes = (1...9).map { pass(String(format: "2026-09-%02dT10:00:00+03:00", $0)) }
        let tiles = PlaceScreen.tiles(from: passes, calendar: calendar)
        XCTAssertEqual(tiles.count, PlaceScreen.dateTiles)
        XCTAssertEqual(tiles, tiles.sorted { $0.day > $1.day })
    }

    func testEmptyPassesGiveNoTiles() {
        XCTAssertTrue(PlaceScreen.tiles(from: [], calendar: calendar).isEmpty)
    }

    // MARK: «Откуда → куда»

    func testRouteJoinsTwoDifferentNames() {
        XCTAssertEqual(PlaceScreen.route(from: "Краснодар", to: "Горячий Ключ"),
                       "Краснодар → Горячий Ключ")
    }

    /// Круг по городу с возвратом во двор — не дорога из Краснодара в
    /// Краснодар: стрелка между двумя одинаковыми словами обещает путь,
    /// которого нет.
    func testRouteCollapsesWhenBothEndsAreTheSameCity() {
        XCTAssertEqual(PlaceScreen.route(from: "Краснодар", to: "Краснодар"), "Краснодар")
    }

    func testRouteFallsBackToTheKnownEnd() {
        XCTAssertEqual(PlaceScreen.route(from: nil, to: "Сочи"), "Сочи")
        XCTAssertEqual(PlaceScreen.route(from: "Сочи", to: "  "), "Сочи")
    }

    /// Ни одного имени — строка падает на дату, а не печатает координату:
    /// число из семи знаков ничего не объясняет (правило 0.8.0).
    func testRouteIsNilWithoutAnyName() {
        XCTAssertNil(PlaceScreen.route(from: nil, to: nil))
        XCTAssertNil(PlaceScreen.route(from: "", to: "   "))
    }

    func testEndpointsNeedTwoPoints() {
        XCTAssertNil(PlaceScreen.endpoints(of: []))
        XCTAssertNil(PlaceScreen.endpoints(of: [CLLocationCoordinate2D(latitude: 45, longitude: 39)]))
        let ends = PlaceScreen.endpoints(of: [CLLocationCoordinate2D(latitude: 45, longitude: 39),
                                              CLLocationCoordinate2D(latitude: 44, longitude: 38)])
        XCTAssertEqual(ends?.start.latitude, 45)
        XCTAssertEqual(ends?.end.latitude, 44)
    }
}
