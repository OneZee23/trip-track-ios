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

    /// Атлас грузится ЯВНО, а не «как повезёт с порядком классов».
    ///
    /// `RegionAtlas.shared` — синглтон на весь прогон: соседний класс, который
    /// его поднял, менял здесь результат разбора (пустой атлас не отдаёт ни
    /// одного региона, то есть «первый регион» не случается). Тест, зелёный по
    /// такой причине, зелёный случайно.
    override func setUp() async throws {
        try await super.setUp()
        await RegionAtlas.shared.loadIfNeeded()
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
        isRecording: Bool = false,
        reveal: @escaping @MainActor ([Discovery], UUID) async -> Void = { _, _ in }
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
            isRecording: { isRecording },
            reveal: reveal
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

    /// Поездка по ЗНАКОМЫМ местам: регион уже открыт, все четыре края карты
    /// лежат дальше трека.
    ///
    /// Без этого любая фикстура под Краснодаром даёт «первый регион», и тест
    /// про одну загадку считает две находки. Кэш кладётся прямо в
    /// `UserDefaults` — ровно так же, как его положил бы прошлый финиш.
    private func seedHistory() {
        var cache = DiscoveryProcessor.HistoryCache()
        cache.regionIds = ["RU-KDA"]
        cache.countryCodes = ["RU"]
        cache.north = .init(CLLocationCoordinate2D(latitude: 60, longitude: lon0))
        cache.south = .init(CLLocationCoordinate2D(latitude: 40, longitude: lon0))
        cache.east = .init(CLLocationCoordinate2D(latitude: lat0, longitude: 60))
        cache.west = .init(CLLocationCoordinate2D(latitude: lat0, longitude: 20))
        guard let data = try? JSONEncoder().encode(cache) else { return XCTFail("кэш не собрался") }
        defaults.set(data, forKey: DiscoveryProcessor.historyKey)
    }

    private func storedCount() -> Int {
        let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
        return (try? pc.container.viewContext.count(for: request)) ?? 0
    }

    // MARK: - Загадка

    func testTripThroughARiddleStoresItAndUnlocksTheFirstRiddleBadge() async {
        seedHistory()
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
        seedHistory()
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
        seedHistory()
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
        seedHistory()
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

    // MARK: - История собственной карты

    /// Тысяча превью по двести точек — библиотека зрелого пользователя.
    ///
    /// Точки идут с шагом 5 м, как в настоящем превью после
    /// `PostTripTrackProcessor`; трек уводится на юг, чтобы синтетика не легла
    /// поверх той поездки, по которой считаются вехи.
    private func seedPreviews(count: Int, points: Int = 200) {
        let ctx = pc.container.viewContext
        for n in 0..<count {
            let entity = TripEntity(context: ctx)
            entity.id = UUID()
            entity.startDate = t0.addingTimeInterval(-Double(n + 1) * 86_400)
            entity.endDate = entity.startDate?.addingTimeInterval(600)
            entity.distance = Double(points) * 5
            entity.isPrivate = true
            let base = lat0 - Double(n) * 0.0005
            entity.previewPolyline = Trip.encodePolyline((0..<points).map {
                CLLocationCoordinate2D(latitude: base + Double($0) * stepLat, longitude: lon0)
            })
        }
        try? ctx.save()
    }

    /// Финиш не имеет права перебирать библиотеку на главном актёре.
    ///
    /// Раньше история собиралась по превью ВСЕХ поездок, со `stride` в одну
    /// точку, синхронно — то есть миллион лучей `RegionAtlas.region(containing:)`
    /// ровно в ту секунду, когда человек смотрит на экран итогов. Здесь
    /// проверяются оба конца правки: проход стоит меньше двухсот миллисекунд, и
    /// он ОДИН — следующая поездка складывается в готовый кэш.
    func testHistoryOverAThousandTripsIsWalkedOnceAndCheaply() async {
        seedPreviews(count: 1_000)
        let sut = processor()

        let first = trip(start: t0)
        let started = Date()
        _ = await sut.process(tripId: first, delta: .none)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(sut.historyWalks, 1, "история собрана ровно один раз")
        // Потолок 0.28, и он поднят осознанно в фикс-волне 3. Правило анклава
        // (`RegionAtlas.regionIndex(containing:)`) стоит одного лишнего луча
        // по кольцу на точку там, где регионы вложены друг в друга, — а сид
        // этого теста весь лежит в Краснодаре, то есть внутри рамки Адыгеи,
        // и платит его на КАЖДОЙ точке. Замер: было под 200 мс, стало
        // 223–250. Дороже 0.28 — значит правило стало платить больше, чем
        // одну лишнюю проверку, и это уже не «цена правды», а ошибка.
        XCTAssertLessThan(elapsed, 0.28, """
            разбор финиша с историей по 1000 поездкам занял \(Int(elapsed * 1000)) мс —             это экран итогов, который стоит и ждёт
            """)

        let second = trip(start: t0.addingTimeInterval(3_600))
        _ = await sut.process(tripId: second, delta: .none)
        XCTAssertEqual(sut.historyWalks, 1,
                       "второй финиш обязан взять кэш, а не перечитать библиотеку")
    }

    /// Поездка, приехавшая пулом со второго телефона, в кэше не учтена — и
    /// сторож по числу поездок это видит, не спрашивая никаких уведомлений.
    func testATripThatArrivedAfterTheCacheIsFoldedIn() async {
        let sut = processor()
        _ = await sut.process(tripId: trip(start: t0), delta: .none)
        XCTAssertEqual(sut.historyWalks, 1)

        // Пул: поездка легла в базу мимо финиша.
        seedPreviews(count: 1)
        _ = await sut.process(tripId: trip(start: t0.addingTimeInterval(7_200)), delta: .none)
        XCTAssertEqual(sut.historyWalks, 2, "приехавшую пулом поездку надо досдать в историю")

        // А третий финиш — снова без прохода: досдавать больше нечего.
        _ = await sut.process(tripId: trip(start: t0.addingTimeInterval(10_800)), delta: .none)
        XCTAssertEqual(sut.historyWalks, 2)
    }

    /// Стирание аккаунта забирает и кэш: он выведен из поездок и пережить их
    /// не имеет права.
    func testForgettingTheHistoryDropsTheCache() async {
        let sut = processor()
        _ = await sut.process(tripId: trip(start: t0), delta: .none)
        XCTAssertNotNil(defaults.data(forKey: DiscoveryProcessor.historyKey))
        sut.forgetHistory()
        XCTAssertNil(defaults.data(forKey: DiscoveryProcessor.historyKey))
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

    // MARK: - Сводка на экране итогов

    /// `nil` — «ещё считается», пустая сводка — «ничего не нашлось». Два
    /// состояния обязаны различаться: экран волны 6 вправе крутить ожидание на
    /// `nil`, и на поездке по знакомым улицам он крутил бы его вечно.
    func testEmptySummaryIsAttachedToo() {
        let id = UUID()
        var data: TripCompletionData? = Self.completion()
        XCTAssertNil(data?.discoveries, "до разбора — «ещё считается»")

        MapViewModel.attach(.empty(tripId: id), to: &data, ifTrip: id)
        XCTAssertNotNil(data?.discoveries, "разбор кончился — сводка обязана лечь")
        XCTAssertTrue(data?.discoveries?.isEmpty ?? false)
    }

    /// А чужая поездка сводку не получает: пока шёл разбор, человек мог закрыть
    /// итоги и записать следующую.
    func testSummaryOfAnotherTripIsNotAttached() {
        var data: TripCompletionData? = Self.completion()
        MapViewModel.attach(.empty(tripId: UUID(), newKm: 12.5), to: &data, ifTrip: UUID())
        XCTAssertNil(data?.discoveries)

        // И «поездки нет вовсе» — тоже не повод класть.
        MapViewModel.attach(.empty(tripId: UUID()), to: &data, ifTrip: nil)
        XCTAssertNil(data?.discoveries)
    }

    private static func completion() -> TripCompletionData {
        TripCompletionData(
            xpEarned: 0, xpBreakdown: XPBreakdown(base: 0),
            previousLevel: 1, newLevel: 1, previousXP: 0, newXP: 0,
            previousRank: DriverRank.from(level: 1), newRank: DriverRank.from(level: 1),
            vehicleOdometerBefore: 0, vehicleOdometerAfter: 0,
            vehicleLevelBefore: 1, vehicleLevelAfter: 1,
            newBadges: [], repeatedBadgeCounts: [:], currentStreak: 0, roadCard: nil)
    }

    /// Скрытые все пять: находка перестаёт быть находкой, если показать её
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

    // MARK: - Раскрытие не держит экран итогов

    /// `process` отдаёт сводку, НЕ дожидаясь сетевого круга раскрытия.
    ///
    /// На флапающей сотовой три находки складывались бы в три таймаута
    /// URLSession подряд, и блок «вы нашли» на экране итогов ждал бы их
    /// минуты. Ответ дописывается в базу и доезжает до экрана сам, через
    /// `.discoveriesChanged`.
    func testProcessReturnsBeforeASlowRevealResolves() async throws {
        seedHistory()
        let id = trip(start: t0)
        let started = expectation(description: "раскрытие началось")
        let finished = expectation(description: "раскрытие закончилось")
        let asked = Asked()

        let result = await processor(
            riddles: [bridgeOnTheTrack()],
            reveal: { items, _ in
                asked.keys = items.map(\.key)
                started.fulfill()
                try? await Task.sleep(nanoseconds: 300_000_000)
                asked.done = true
                finished.fulfill()
            }
        ).process(tripId: id, delta: delta())

        XCTAssertEqual(result.riddles.count, 1, "сводка не собралась")
        XCTAssertFalse(asked.done, "сводка дождалась сетевого круга")

        await fulfillment(of: [started, finished], timeout: 5)
        XCTAssertEqual(asked.keys, ["bridge:demo"], "раскрытие спросили не про то")
        XCTAssertTrue(asked.done)
    }

    /// Изменяемая коробка для наблюдения за фоновой задачей: `@MainActor`-тест
    /// и `@MainActor`-замыкание трогают её по очереди, гонки здесь нет.
    @MainActor
    private final class Asked {
        var keys: [String] = []
        var done = false
    }
}
