import XCTest
import CoreLocation
@testable import TripTrack

/// «Журнал первооткрывателя»: что в нём лежит, в каком порядке и на каком
/// расстоянии.
///
/// Чистой функцией и числами, потому что глазами это не проверить: круг
/// подсказки нарисован в масштабе страны, и «сто двадцать километров до его
/// края или сто пятьдесят до середины» на экране неразличимо. А цена ошибки —
/// прицел: расстояние до СЕРЕДИНЫ выдавало бы смещение, ради которого центр
/// круга и сдвинут (`RiddleHint.offsetCentre`).
///
/// Полей у класса нет намеренно — фикстуры собираются в каждом тесте, и
/// отпускать в `tearDown` нечего (см. `JourneySyncConflictTests`: поле,
/// пережившее тест, роняет чужой класс через полчаса прогона).
final class JournalBuilderTests: XCTestCase {

    // MARK: - Фикстуры

    private func region(_ id: String, km: Double, since: Date? = nil) -> MapRegionStat {
        MapRegionStat(
            id: id, countryCode: "RU", nameRu: id, nameEn: id,
            km: km, tripIds: [], cities: [], totalCities: 0, openedTiles: 0,
            firstVisited: since, openedKm: km,
            center: CLLocationCoordinate2D(latitude: 45, longitude: 39),
            bounds: GeoBounds(minLat: 44, maxLat: 46, minLon: 38, maxLon: 40))
    }

    private func find(
        _ key: String, kind: DiscoveryKind = .riddle, foundAt: Date
    ) -> Discovery {
        Discovery(
            kind: kind, key: key, tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
            foundAt: foundAt, symbol: .lighthouse)
    }

    private func hint(
        _ id: String, lat: Double, lon: Double, radius: Double
    ) -> RiddleHint {
        RiddleHint(id: id, type: .lighthouse,
                   centre: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   radiusMetres: radius)
    }

    /// Слой с одним центроидом: больше сборке журнала от него ничего не нужно.
    private func layer(
        openedKm: Double = 0, centroid: CLLocationCoordinate2D? = nil
    ) -> RevealedLayer {
        var layer = RevealedLayer(
            fine: .init(), mid: .init(), far: .init(),
            cellCount: 0, openedKm: openedKm, regionIds: [])
        if let centroid { layer.regionCentroids = ["RU-KDA": centroid] }
        return layer
    }

    private let day = TimeInterval(86_400)

    // MARK: - Три группы

    func testBuildFillsAllThreeGroupsFromWhatItWasGiven() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let exploration = MapExploration(
            regions: [region("RU-KDA", km: 900, since: now - 30 * day),
                      region("RU-ROS", km: 120)],
            trips: [], totalKm: 1_020)
        let journal = JournalBuilder.build(
            exploration: exploration,
            revealed: layer(openedKm: 1_910,
                            centroid: CLLocationCoordinate2D(latitude: 45, longitude: 39)),
            seals: [find("lighthouse:u0h", foundAt: now)],
            hints: [hint("pass:u0j", lat: 45, lon: 39, radius: 5_000)])

        // Открытых километров у журнала НЕТ: их печатает лист прямо из
        // `RevealedLayer.openedKm`, и второе поле с тем же числом было бы
        // вторым источником.
        XCTAssertEqual(journal.regions.map(\.id), ["RU-KDA", "RU-ROS"])
        XCTAssertEqual(journal.regions.first?.firstVisited, now - 30 * day)
        XCTAssertEqual(journal.finds.count, 1)
        XCTAssertEqual(journal.riddles.map(\.id), ["pass:u0j"])
        XCTAssertFalse(journal.isEmpty)
    }

    /// Порядок регионов — тот, что пришёл из `MapExploration`. Второй порядок
    /// для того же списка означал бы, что карточка региона и строка журнала
    /// однажды покажут разное «первым».
    func testRegionOrderIsLeftExactlyAsExplorationGaveIt() {
        let exploration = MapExploration(
            regions: [region("RU-ROS", km: 10), region("RU-KDA", km: 900)],
            trips: [], totalKm: 910)
        let journal = JournalBuilder.build(
            exploration: exploration, revealed: layer(), seals: [], hints: [])
        XCTAssertEqual(journal.regions.map(\.id), ["RU-ROS", "RU-KDA"])
    }

    func testEmptyEverythingIsAnEmptyJournal() {
        let journal = JournalBuilder.build(
            exploration: MapExploration(), revealed: .empty, seals: [], hints: [])
        XCTAssertTrue(journal.isEmpty)
    }

    // MARK: - Порядок находок

    func testFindsAreSortedNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let seals = [
            find("a", foundAt: now - 10 * day),
            find("b", foundAt: now),
            find("c", foundAt: now - 3 * day)
        ]
        let journal = JournalBuilder.build(
            exploration: MapExploration(), revealed: .empty, seals: seals, hints: [])
        XCTAssertEqual(journal.finds.map(\.key), ["b", "c", "a"])
    }

    /// Финиш кладёт секрет, загадку и веху ОДНОЙ датой. Без второго ключа
    /// сетка печатей тасовалась бы от перезагрузки к перезагрузке.
    func testSameSecondFindsKeepAStableOrder() {
        let stamp = Date(timeIntervalSince1970: 1_750_000_000)
        let seals = [
            find("pass:u0h", kind: .riddle, foundAt: stamp),
            find("firstRegion:RU-KDA", kind: .milestone, foundAt: stamp),
            find("komsomolsky", kind: .secret, foundAt: stamp)
        ]
        let once = JournalBuilder.sortedFinds(seals).map(\.id)
        let again = JournalBuilder.sortedFinds(seals.reversed()).map(\.id)
        XCTAssertEqual(once, again)
        XCTAssertEqual(once, once.sorted { $0.uuidString < $1.uuidString })
    }

    // MARK: - Расстояние до круга

    /// Ровно `max(0, d − радиус)`: от ближайшего центроида открытого до КРАЯ
    /// круга, а не до его середины.
    func testDistanceIsMeasuredToTheEdgeOfTheCircle() {
        let home = CLLocationCoordinate2D(latitude: 45, longitude: 39)
        // Один градус широты — 111.2 км; радиус круга 30 км.
        let far = hint("pass:u0j", lat: 46, lon: 39, radius: 30_000)
        let toCentre = RiddleHint.distanceToNearest(of: far.centre, among: [home])

        let journal = JournalBuilder.build(
            exploration: MapExploration(), revealed: layer(centroid: home),
            seals: [], hints: [far])

        XCTAssertEqual(journal.riddles.first?.metresToEdge ?? -1,
                       toCentre - 30_000, accuracy: 1)
        XCTAssertEqual(journal.riddles.first?.metresToEdge ?? -1, 81_000, accuracy: 2_000)
    }

    func testOpenTerritoryInsideTheCircleGivesZero() {
        let home = CLLocationCoordinate2D(latitude: 45, longitude: 39)
        // Середина круга в пяти километрах, радиус — тридцать.
        let over = hint("pass:u0j", lat: 45.045, lon: 39, radius: 30_000)

        let journal = JournalBuilder.build(
            exploration: MapExploration(), revealed: layer(centroid: home),
            seals: [], hints: [over])

        XCTAssertEqual(journal.riddles.first?.metresToEdge, 0,
                       "внутри круга расстояния нет, и отрицательным оно не бывает")
    }

    /// Ближайший центроид, а не первый попавшийся: центроидов у открытого
    /// столько же, сколько регионов.
    func testDistanceTakesTheNearestCentroid() {
        let near = CLLocationCoordinate2D(latitude: 45.5, longitude: 39)
        let far = CLLocationCoordinate2D(latitude: 50, longitude: 39)
        let circle = hint("pass:u0j", lat: 46, lon: 39, radius: 10_000)

        let fromNear = JournalBuilder.nearby(hints: [circle], centroids: [far, near])
        let onlyNear = JournalBuilder.nearby(hints: [circle], centroids: [near])
        XCTAssertEqual(fromNear.first?.metresToEdge ?? -1,
                       onlyNear.first?.metresToEdge ?? -2, accuracy: 0.5)
    }

    /// Подсказок без открытой территории не бывает (`RiddleHint.plan` не
    /// выдаёт их без центроидов), но падать на пустом слое нельзя.
    func testNoCentroidsIsZeroRatherThanACrash() {
        let hints = JournalBuilder.nearby(
            hints: [hint("pass:u0j", lat: 46, lon: 39, radius: 10_000)], centroids: [])
        XCTAssertEqual(hints.first?.metresToEdge, 0)
        XCTAssertEqual(hints.first?.type, .lighthouse)
    }
}
