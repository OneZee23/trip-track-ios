import XCTest
import CoreLocation
import MapKit
@testable import TripTrack

/// «Атлас» и находки: печати читаются готовыми, подсказок не больше трёх, а
/// новая находка НЕ стоит пересборки тумана.
///
/// Последнее — не микрооптимизация: пересборка идёт по всей библиотеке превью
/// (0.5–2 с) и на это время рисует «всё закрыто». Печать, легшая на финише,
/// обязана стоить одной выборки строк.
final class MyMapViewModelSealsTests: XCTestCase {
    private var pc: PersistenceController!
    private var store: DiscoveryStore!
    /// Вью-модели держатся здесь, а не локальными переменными: каждая из них
    /// держит стор, стор — контекст, контекст — модель. Отпустить их надо в
    /// `tearDown`, иначе модель переживёт класс и в ЧУЖОМ тесте появится
    /// «Multiple NSEntityDescriptions claim TripEntity».
    private var models: [MyMapViewModel] = []

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = DiscoveryStore(persistence: pc)
        // Подсказки загадок скрыты владельцем 17 сентября
        // (`RiddleHints.isEnabled == false`); этот класс проверяет сам план
        // подсказок, а не то, включён ли флаг видимости.
        RiddleHints.isEnabledOverride = true
        // Находки отложены владельцем 22 сен 2026 до после 1.0.0
        // (`DiscoveriesAvailability.isEnabled == false`); этот класс проверяет
        // сами печати и подсказки, а не то, скрыта ли фича целиком.
        DiscoveriesAvailability.isEnabledOverride = true
    }

    /// Каждое поле обнуляется: XCTest держит экземпляры до конца прогона, и
    /// незакрытая `PersistenceController(inMemory:)` роняет ЧУЖОЙ класс
    /// («Multiple NSEntityDescriptions claim TripEntity»).
    override func tearDown() {
        models.removeAll()
        store = nil
        pc = nil
        RiddleHints.isEnabledOverride = nil
        DiscoveriesAvailability.isEnabledOverride = nil
        super.tearDown()
    }

    // MARK: - Фикстуры

    private struct StubCatalog: RiddleCatalog {
        let riddles: [Riddle]
        func all() -> [Riddle] { riddles }
        func candidates(near cells: Set<String>) -> [Riddle] { riddles }
    }

    private func riddle(_ id: String, lat: Double, lon: Double) -> Riddle {
        Riddle(id: id, type: .lighthouse,
               coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), name: id)
    }

    private func discovery(
        kind: DiscoveryKind = .riddle, key: String, lat: Double = 45, lon: Double = 39
    ) -> Discovery {
        Discovery(
            kind: kind, key: key, tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            foundAt: Date(timeIntervalSince1970: 1_758_000_000), symbol: .lighthouse)
    }

    /// Открытый слой с одним центроидом. Собран руками, а не `build(tiles:)`:
    /// центроиды приходят от атласа, а поднимать бандл регионов ради одной
    /// точки незачем.
    private func openedAround(lat: Double, lon: Double) -> RevealedLayer {
        var layer = RevealedLayer(
            fine: MKMultiPolyline(), mid: MKMultiPolyline(), far: MKMultiPolyline(),
            cellCount: 1, openedKm: 10, regionIds: ["RU-KDA"])
        layer.regionCentroids = ["RU-KDA": CLLocationCoordinate2D(latitude: lat, longitude: lon)]
        return layer
    }

    @MainActor
    private func makeViewModel(_ riddles: [Riddle]) -> MyMapViewModel {
        let vm = MyMapViewModel(discoveryStore: store, riddleCatalog: StubCatalog(riddles: riddles))
        models.append(vm)
        return vm
    }

    private var fiveRiddles: [Riddle] {
        [riddle("a", lat: 45.1, lon: 39.0),
         riddle("b", lat: 45.3, lon: 39.0),
         riddle("c", lat: 45.5, lon: 39.0),
         riddle("d", lat: 46.5, lon: 39.0),
         riddle("e", lat: 50.0, lon: 39.0)]
    }

    // MARK: - Печати

    @MainActor
    func testSealsComeFromTheStoreAsTheyAre() async throws {
        _ = try await store.upsert([
            discovery(key: "lighthouse:one"),
            discovery(kind: .milestone, key: "firstRegion:RU-KDA"),
        ])
        let vm = makeViewModel([])

        await vm.reloadDiscoveries()

        XCTAssertEqual(Set(vm.seals.map(\.key)), ["lighthouse:one", "firstRegion:RU-KDA"])
    }

    /// Владелец 22 сен 2026: отложить находки до после 1.0.0.
    /// `DiscoveriesAvailability.isEnabled` (прод-константа, а не тестовый шов
    /// из `setUp`) обязана опустошить и печати, и журнал.
    @MainActor
    func testSealsAreHiddenWhenTheFlagIsOff() async throws {
        _ = try await store.upsert([discovery(key: "lighthouse:six")])
        DiscoveriesAvailability.isEnabledOverride = nil
        let vm = makeViewModel([])

        await vm.reloadDiscoveries()

        XCTAssertTrue(vm.seals.isEmpty, "печатей на журнале быть не должно")
        XCTAssertTrue(vm.journal.finds.isEmpty, "секции «Находки» в журнале быть не должно")
    }

    // MARK: - Подсказки

    @MainActor
    func testAtMostThreeNearestRiddlesBecomeHints() async {
        let vm = makeViewModel(fiveRiddles)

        await vm.reloadDiscoveries(layer: openedAround(lat: 45.0, lon: 39.0))

        XCTAssertEqual(vm.riddleHints.map(\.id), ["a", "b", "c"])
    }

    /// Владелец 17 сентября: убрать загадки из видимости. `RiddleHints
    /// .isEnabled` (прод-константа, а не тестовый шов из `setUp`) обязана
    /// опустошить и карту, и журнал — теми же данными, на которых выше три
    /// подсказки встают на карту, когда флаг включён тестом.
    @MainActor
    func testHintsAreHiddenWhenTheFlagIsOff() async {
        RiddleHints.isEnabledOverride = nil
        let vm = makeViewModel(fiveRiddles)

        await vm.reloadDiscoveries(layer: openedAround(lat: 45.0, lon: 39.0))

        XCTAssertTrue(vm.riddleHints.isEmpty, "аннотаций подсказок на карте быть не должно")
        XCTAssertTrue(vm.journal.riddles.isEmpty, "секции «Загадки рядом» в журнале быть не должно")
    }

    @MainActor
    func testSolvedRiddleFreesASlot() async throws {
        // Решённая загадка — это запись находки с ключом самой загадки.
        _ = try await store.upsert([discovery(key: "b")])
        let vm = makeViewModel(fiveRiddles)

        await vm.reloadDiscoveries(layer: openedAround(lat: 45.0, lon: 39.0))

        XCTAssertEqual(vm.riddleHints.map(\.id), ["a", "c", "d"],
                       "решённая уступает место следующей по близости")
        XCTAssertEqual(vm.seals.count, 1, "а сама становится печатью")
    }

    @MainActor
    func testNoHintsWithoutOpenTerritory() async {
        let vm = makeViewModel(fiveRiddles)

        await vm.reloadDiscoveries()

        XCTAssertTrue(vm.riddleHints.isEmpty,
                      "на карте, где ничего не открыто, круг указывал бы в никуда")
    }

    // MARK: - Уведомление

    @MainActor
    func testDiscoveriesChangedReloadsSealsWithoutRebuildingTheFog() async throws {
        let vm = makeViewModel([])
        await vm.reloadDiscoveries()
        XCTAssertTrue(vm.seals.isEmpty)
        let rebuildsBefore = vm.fogRebuilds

        // `upsert` сам постит `.discoveriesChanged`, когда строка легла.
        _ = try await store.upsert([discovery(key: "lighthouse:two")])

        var waited = 0
        while vm.seals.isEmpty && waited < 100 {
            try await Task.sleep(nanoseconds: 20_000_000)
            waited += 1
        }
        XCTAssertEqual(vm.seals.map(\.key), ["lighthouse:two"])
        XCTAssertEqual(vm.fogRebuilds, rebuildsBefore,
                       "печать не имеет права стоить пересборки тумана")
    }

    // MARK: - Выбор

    @MainActor
    func testSelectingASealResolvesToTheDiscovery() async throws {
        let found = discovery(key: "lighthouse:three")
        _ = try await store.upsert([found])
        let vm = makeViewModel([])
        await vm.reloadDiscoveries()

        vm.select(.discovery(found.id), zoom: false)

        XCTAssertEqual(vm.selectedDiscovery?.key, "lighthouse:three")
        XCTAssertNil(vm.cameraCommand, "палец уже стоит на печати — камера не двигается")
    }

    /// Выбор печати, которой больше нет (стёрли аккаунт), снимается сам:
    /// карточка показывала бы призрак.
    @MainActor
    func testSelectionOfAVanishedSealIsDropped() async throws {
        let found = discovery(key: "lighthouse:four")
        _ = try await store.upsert([found])
        let vm = makeViewModel([])
        await vm.reloadDiscoveries()
        vm.select(.discovery(found.id), zoom: false)

        // Ждём СОБСТВЕННОГО перечитывания по `.discoveriesChanged`, а не зовём
        // его руками: стирание постит уведомление, и два перечитывания внахлёст
        // разошлись бы поколениями — обогнанное молча выходит, как и задумано.
        store.wipe()
        var waited = 0
        while vm.selectedDiscovery != nil && waited < 100 {
            try await Task.sleep(nanoseconds: 20_000_000)
            waited += 1
        }

        XCTAssertNil(vm.selectedDiscovery)
        XCTAssertNil(vm.selection)
        XCTAssertTrue(vm.seals.isEmpty)
    }

    // MARK: - Чужая карта

    @MainActor
    func testStrangerMapShowsNoSeals() async throws {
        _ = try await store.upsert([discovery(key: "lighthouse:five")])
        let vm = MyMapViewModel(source: StubTripSource())
        models.append(vm)

        await vm.reloadDiscoveries(layer: openedAround(lat: 45.0, lon: 39.0))

        XCTAssertTrue(vm.seals.isEmpty, "находки живут только на телефоне владельца")
        XCTAssertTrue(vm.riddleHints.isEmpty)
    }
}

private struct StubTripSource: TripSource {
    func load() async -> TripSourceResult { TripSourceResult(trips: [], failed: false) }
}
