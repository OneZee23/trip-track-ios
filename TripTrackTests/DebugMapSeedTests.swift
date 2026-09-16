import XCTest
import CoreLocation
@testable import TripTrack

/// Состав `-seed-discoveries` (0.7.0, волна 5).
///
/// Сид — единственный источник карточки секрета на симуляторе и в кадрах
/// `DiscoveryCardShotTests`: каталог секретов закрыт хешами, а настоящий разбор
/// трека без сервера ни имени, ни счётчика нашедших не даст. Поэтому проверять
/// его надо здесь: на экране «поле не заполнилось» выглядит как «карточка так и
/// задумана», и кадр уехал бы в релизный пакет молча.
final class DebugMapSeedTests: XCTestCase {
    private var pc: PersistenceController!
    private var store: DiscoveryStore!

    /// Обнуляется всё: XCTest держит экземпляры до конца прогона, и незакрытая
    /// `PersistenceController(inMemory:)` роняет ЧУЖОЙ класс («Multiple
    /// NSEntityDescriptions claim TripEntity»).
    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = DiscoveryStore(persistence: pc)
    }

    override func tearDown() {
        store = nil
        pc = nil
        super.tearDown()
    }

    private func seeded() -> [Discovery] {
        DebugMapSeed.seededDiscoveries(
            tripId: UUID(),
            riddleAt: CLLocationCoordinate2D(latitude: 44.63, longitude: 39.13),
            milestoneAt: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.97),
            startDate: Date(timeIntervalSince1970: 1_758_000_000))
    }

    func testSeedCarriesTheSecretAlongsideTheRiddleAndTheMilestone() {
        let kinds = seeded().map(\.kind)
        XCTAssertEqual(kinds, [.riddle, .milestone, .secret],
                       "сид кладёт по одной находке каждого вида")
    }

    /// Карточка секрета показывает четыре разные ветки, и каждая живёт на своём
    /// поле: имя, история (её `nil` включает Debug-заглушку), счётчик нашедших,
    /// первооткрыватель. Незаполненное поле гасит свою ветку молча.
    func testSecretRowFillsEveryBranchOfTheCard() throws {
        let secret = try XCTUnwrap(seeded().first { $0.kind == .secret })
        XCTAssertEqual(secret.key, "komsomolsky", "ключ — id записи в Secrets.json")
        XCTAssertEqual(secret.symbol, .komsomolsky)
        XCTAssertEqual(secret.title, "Знак Комсомольского")
        XCTAssertNil(secret.story, "история приходит с сервера; без неё видна Debug-заглушка")
        XCTAssertFalse(secret.verified, "подтверждает находку сервер по треку, а не сид")
        XCTAssertEqual(secret.finders, 7)
        XCTAssertEqual(secret.firstFinderName, "OneZee")
        XCTAssertEqual(secret.firstFinderAt, Date(timeIntervalSince1970: 1_781_784_000))
        XCTAssertEqual(secret.rarity, "few")
    }

    /// Координата секрета — внутри Комсомольского, а не «где-то в Краснодаре»:
    /// печать обязана стоять в районе, ячейки которого лежат в `Secrets.json`.
    func testSecretSitsInsideTheDistrict() throws {
        let centre = DebugMapSeed.komsomolskyCentre
        let catalog = BundleSecretCatalog.shared
        let record = try XCTUnwrap(catalog.all().first { $0.id == "komsomolsky" },
                                   "секрет лежит в бандле")
        let cell = GeohashEncoder.encode(
            latitude: centre.latitude, longitude: centre.longitude, precision: 7)
        let hash = SecretHash.truncated(salt: catalog.salt, geohash7: cell)
        XCTAssertTrue(record.hashes.contains(hash),
                      "центр района попадает в ячейку секрета из бандла")
    }

    /// Перезапуск с тем же аргументом не кладёт вторую печать: `id` выведен из
    /// вида и ключа, и `upsert` отвечает пустым списком.
    func testSeedingTwiceAddsNothingTheSecondTime() async throws {
        let first = try await store.upsert(seeded())
        XCTAssertEqual(first.count, 3)

        let second = try await store.upsert(seeded())
        XCTAssertTrue(second.isEmpty, "повторный запуск сида — ноль новых строк")
    }
}
