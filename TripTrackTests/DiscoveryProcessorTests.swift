import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Разбор трека на финише: что нашлось — записывается один раз, повтор молчит,
/// а пока идёт запись, не считается ничего.
@MainActor
final class DiscoveryProcessorTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var store: DiscoveryStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var unlocked: [String] = []

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    /// Прямая на север из-под Краснодара: 200 точек по 5 м — та же плотность,
    /// с какой пишется настоящий трек с 0.6.5.
    private let lat0 = 45.0355, lon0 = 38.9753, stepLat = 0.000045

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        store = DiscoveryStore(persistence: pc)
        suiteName = "discoveries-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        unlocked = []
    }

    /// Каждое поле обнуляется: XCTest держит экземпляры до конца прогона, и
    /// незакрытая `PersistenceController(inMemory:)` тянет свою модель — в логе
    /// это «Multiple NSEntityDescriptions claim TripEntity» в ЧУЖОМ классе.
    override func tearDown() {
        store = nil
        repo = nil
        pc = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        unlocked = []
        super.tearDown()
    }

    // MARK: - Фикстуры

    private struct StubRiddles: RiddleCatalog {
        let riddles: [Riddle]
        func all() -> [Riddle] { riddles }
        /// Предфильтр в тесте не проверяется — его держит `RiddleMatcher`;
        /// здесь важно, что процессор спрашивает каталог и отдаёт ответ матчеру.
        func candidates(near cells: Set<String>) -> [Riddle] { riddles }
    }

    private struct StubSecrets: SecretCatalog {
        let salt: String
        let records: [SecretRecord]
        func all() -> [SecretRecord] { records }
    }

    private func processor(
        riddles: [Riddle] = [],
        secrets: [SecretRecord] = [],
        salt: String = "test-salt",
        isRecording: Bool = false
    ) -> DiscoveryProcessor {
        DiscoveryProcessor(
            store: store,
            repository: repo,
            riddleCatalog: StubRiddles(riddles: riddles),
            secretCatalog: StubSecrets(salt: salt, records: secrets),
            defaults: defaults,
            unlockBadge: { [weak self] id in
                self?.unlocked.append(id)
                return Badge.all.first(where: { $0.id == id })
            },
            isRecording: { isRecording }
        )
    }

    @discardableResult
    private func trip(start: Date, count: Int = 200, altitude: Double = 40) -> UUID {
        let ctx = pc.container.viewContext
        let entity = TripEntity(context: ctx)
        let id = UUID()
        entity.id = id
        entity.startDate = start
        entity.endDate = start.addingTimeInterval(Double(count))
        entity.distance = Double(count) * 5
        entity.isPrivate = true
        for i in 0..<count {
            let point = TrackPointEntity(context: ctx)
            point.id = UUID()
            point.latitude = lat0 + Double(i) * stepLat
            point.longitude = lon0
            point.altitude = altitude
            point.speed = 15
            point.course = 0
            point.horizontalAccuracy = 5
            point.timestamp = start.addingTimeInterval(Double(i))
            point.trip = entity
        }
        try? ctx.save()
        return id
    }

    /// Мост в двадцати метрах от середины трека: `RiddleType.bridge` считает
    /// решением проезд в трёхстах.
    private func bridgeOnTheTrack() -> Riddle {
        Riddle(
            id: "bridge:demo",
            type: .bridge,
            coordinate: CLLocationCoordinate2D(
                latitude: lat0 + 100 * stepLat, longitude: lon0 + 0.00025),
            name: "Мост")
    }

    private func delta(km: Double = 0, regions: [String] = []) -> RevealedLayerStore.IngestDelta {
        RevealedLayerStore.IngestDelta(
            openedCells: Int(km * 13), openedKm: km, newRegionIds: regions)
    }

    private func storedCount() -> Int {
        let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
        return (try? pc.container.viewContext.count(for: request)) ?? 0
    }

    // MARK: - Загадка

    func testTripThroughARiddleStoresItAndUnlocksTheFirstRiddleBadge() async {
        let id = trip(start: t0)
        let changed = expectation(forNotification: .discoveriesChanged, object: nil)

        let found = await processor(riddles: [bridgeOnTheTrack()])
            .process(tripId: id, delta: delta(km: 12.5, regions: ["RU-KDA"]))

        XCTAssertEqual(found.riddles.count, 1)
        XCTAssertEqual(found.riddles.first?.key, "bridge:demo")
        XCTAssertEqual(found.riddles.first?.title, "Мост")
        XCTAssertEqual(found.riddles.first?.symbol, .bridge)
        // Печать стоит в дате поездки, а не в «сейчас».
        XCTAssertEqual(found.riddles.first?.foundAt, t0)
        XCTAssertEqual(found.newKm, 12.5)
        XCTAssertEqual(found.newRegionIds, ["RU-KDA"])
        XCTAssertFalse(found.isEmpty)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(storedCount(), 1)
        XCTAssertTrue(unlocked.contains(DiscoveryProcessor.firstRiddleBadgeId))
        XCTAssertFalse(unlocked.contains(DiscoveryProcessor.tenRiddlesBadgeId),
                       "десятый значок за одну загадку — это уже другая игра")
        await fulfillment(of: [changed], timeout: 2)
    }

    func testSecondRunOfTheSameTripFindsNothing() async {
        let id = trip(start: t0)
        let sut = processor(riddles: [bridgeOnTheTrack()])
        _ = await sut.process(tripId: id, delta: delta(km: 12.5))
        unlocked = []

        let again = await sut.process(tripId: id, delta: delta(km: 0))
        XCTAssertEqual(again.count, 0)
        XCTAssertTrue(again.isEmpty, "повтор — это ноль километров и ноль печатей")
        XCTAssertEqual(storedCount(), 1, "вторая строка на ту же находку не легла")
        XCTAssertTrue(unlocked.isEmpty, "и значок второй раз не выдаётся")
    }

    func testTripWithNothingAroundIsEmpty() async {
        let id = trip(start: t0)
        let found = await processor().process(tripId: id, delta: .none)

        XCTAssertTrue(found.isEmpty)
        XCTAssertEqual(found.count, 0)
        XCTAssertEqual(storedCount(), 0)
        XCTAssertTrue(unlocked.isEmpty)
    }

    /// Километры и регионы — из дельты тумана, даже когда ни одной печати не
    /// нашлось: «открыл 12 км» это самостоятельный ответ экрана итогов.
    func testKilometresComeFromTheFogDeltaEvenWithoutFinds() async {
        let id = trip(start: t0)
        let found = await processor().process(tripId: id, delta: delta(km: 12.5, regions: ["RU-ROS"]))

        XCTAssertEqual(found.newKm, 12.5)
        XCTAssertEqual(found.newRegionIds, ["RU-ROS"])
        XCTAssertFalse(found.isEmpty, "открытые километры — это не пустая сводка")
        XCTAssertEqual(found.count, 0)
    }

    // MARK: - Веха

    /// Высота — единственная веха, которой не нужен атлас: она считается по
    /// самим точкам, и в тесте без бандла геометрии проверяется именно она.
    func testAltitudeMilestoneIsStoredAndUnlocksItsBadge() async {
        let id = trip(start: t0, altitude: 2_150)
        let found = await processor().process(tripId: id, delta: .none)

        // Именно по ключу, а не по единственности: часовой пояс машины, на
        // которой гоняют тест, может добавить сюда ещё и ночной перевал —
        // ловить тестом местное время незачем.
        let altitude = found.milestones.first { $0.key == Milestone.above2000.rawValue }
        XCTAssertNotNil(altitude, "веха высоты не нашлась: \(found.milestones.map(\.key))")
        XCTAssertEqual(altitude?.symbol, .altitude)
        XCTAssertTrue(unlocked.contains(DiscoveryProcessor.altitudeBadgeId))
    }

    // MARK: - Пока идёт запись — ничего

    func testNothingIsComputedWhileRecording() async {
        let id = trip(start: t0)
        let found = await processor(riddles: [bridgeOnTheTrack()], isRecording: true)
            .process(tripId: id, delta: delta(km: 12.5))

        XCTAssertTrue(found.isEmpty)
        XCTAssertEqual(found.newKm, 0, "на ходу не показывается даже дельта тумана")
        XCTAssertEqual(storedCount(), 0)
        XCTAssertTrue(unlocked.isEmpty)
    }

    // MARK: - Значки находок

    /// Значок находки лежит в том же ключе, что и остальные, но выводится не из
    /// статистики: пересчёт значков после следующей поездки не имеет права его
    /// стереть.
    func testDiscoveryBadgeSurvivesARecomputeOfTheStatsBadges() {
        let key = "unlockedBadgeIds"
        let saved = UserDefaults.standard.stringArray(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)

        XCTAssertEqual(BadgeManager.unlock(id: DiscoveryProcessor.firstRiddleBadgeId)?.id,
                       DiscoveryProcessor.firstRiddleBadgeId)
        XCTAssertNil(BadgeManager.unlock(id: DiscoveryProcessor.firstRiddleBadgeId),
                     "второй раз открывать нечего")
        XCTAssertNil(BadgeManager.unlock(id: "no-such-badge"))

        // Пересчёт по пустой статистике: раньше он переписывал ключ целиком.
        _ = BadgeManager.checkNewBadges(stats: BadgeManager.computeStats(from: []))
        XCTAssertTrue(BadgeManager.storedUnlockedIds().contains(DiscoveryProcessor.firstRiddleBadgeId))
        XCTAssertTrue(
            BadgeManager.unlockedBadges(for: BadgeManager.computeStats(from: []))
                .contains { $0.id == DiscoveryProcessor.firstRiddleBadgeId },
            "значок находки обязан оставаться на полке")
    }

    /// Скрытые все четыре: находка перестаёт быть находкой, если показать её
    /// списком заранее.
    func testDiscoveryBadgesAreHiddenExplorationBadges() {
        for id in Badge.externallyUnlockedIds {
            guard let badge = Badge.all.first(where: { $0.id == id }) else {
                return XCTFail("значка \(id) нет в каталоге")
            }
            XCTAssertTrue(badge.isHidden, "\(id) обязан быть скрытым")
            XCTAssertEqual(badge.category, .exploration, "\(id) — про исследование")
            XCTAssertFalse(badge.checkUnlocked(BadgeManager.computeStats(from: [])),
                           "\(id) не имеет права выводиться из статистики поездок")
        }
    }
}
