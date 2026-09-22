import XCTest
import CoreLocation
@testable import TripTrack

/// Выключатель находок (0.8.0): при `DiscoveriesAvailability.isEnabled ==
/// false` печати, подсказки и секция на чужом профиле пропадают, а пул и
/// стирание аккаунта продолжают работать как раньше (это проверяют другие
/// наборы — здесь только сам гейт).
final class DiscoveriesAvailabilityTests: XCTestCase {
    private var pc: PersistenceController!
    private var store: DiscoveryStore!
    private var models: [MyMapViewModel] = []

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = DiscoveryStore(persistence: pc)
    }

    /// Каждое поле обнуляется: XCTest держит экземпляры до конца прогона, и
    /// незакрытая `PersistenceController(inMemory:)` роняет ЧУЖОЙ класс
    /// («Multiple NSEntityDescriptions claim TripEntity»).
    override func tearDown() {
        models.removeAll()
        store = nil
        pc = nil
        DiscoveriesAvailability.isEnabledOverride = nil
        super.tearDown()
    }

    private func discovery(key: String) -> Discovery {
        Discovery(
            kind: .riddle, key: key, tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
            foundAt: Date(timeIntervalSince1970: 1_758_000_000), symbol: .lighthouse)
    }

    private struct EmptyCatalog: RiddleCatalog {
        func all() -> [Riddle] { [] }
        func candidates(near cells: Set<String>) -> [Riddle] { [] }
    }

    @MainActor
    private func makeViewModel() -> MyMapViewModel {
        let vm = MyMapViewModel(discoveryStore: store, riddleCatalog: EmptyCatalog())
        models.append(vm)
        return vm
    }

    // MARK: - Прод-константа

    /// 0.8.0 уезжает выключенным. Тест падает в тот день, когда константу
    /// переключат, — чтобы вместе с ней перечитали, чем находки заменились.
    func testShippedBuildKeepsDiscoveriesHidden() {
        XCTAssertFalse(DiscoveriesAvailability.isEnabled)
    }

    // MARK: - MyMapViewModel.reloadDiscoveries

    @MainActor
    func testReloadDiscoveriesHidesSealsWhenFlagIsOff() async throws {
        _ = try await store.upsert([discovery(key: "a")])
        DiscoveriesAvailability.isEnabledOverride = false
        let vm = makeViewModel()

        await vm.reloadDiscoveries()

        XCTAssertTrue(vm.seals.isEmpty)
        XCTAssertTrue(vm.journal.finds.isEmpty)
    }

    @MainActor
    func testReloadDiscoveriesShowsSealsWhenFlagIsOn() async throws {
        _ = try await store.upsert([discovery(key: "b")])
        DiscoveriesAvailability.isEnabledOverride = true
        let vm = makeViewModel()

        await vm.reloadDiscoveries()

        XCTAssertEqual(vm.seals.map(\.key), ["b"])
        XCTAssertEqual(vm.journal.finds.map(\.key), ["b"])
    }

    // MARK: - Чужой профиль

    func testSocialFindsAreVisibleReturnsFalseWhenDisabledEvenForANonEmptyList() {
        let find = SocialFind(
            secretId: "s1", kind: "secret", symbol: "mountain.2",
            rarity: "few", foundAt: Date(), first: true)
        XCTAssertFalse(socialFindsAreVisible([find], enabled: false))
    }

    func testSocialFindsAreVisibleReturnsTrueWhenEnabledForANonEmptyList() {
        let find = SocialFind(
            secretId: "s1", kind: "secret", symbol: "mountain.2",
            rarity: "few", foundAt: Date(), first: true)
        XCTAssertTrue(socialFindsAreVisible([find], enabled: true))
    }
}
