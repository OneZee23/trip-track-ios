import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Хранилище находок: пишет только новое, отдаёт свежее сверху, а повтор той
/// же находки — пустой ответ, а не вторая печать.
final class DiscoveryStoreTests: XCTestCase {
    private var pc: PersistenceController!
    private var store: DiscoveryStore!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = DiscoveryStore(persistence: pc)
    }

    /// Каждое поле обнуляется: XCTest держит экземпляры до конца прогона, и
    /// незакрытая `PersistenceController(inMemory:)` тянет свою модель — в логе
    /// это «Multiple NSEntityDescriptions claim TripEntity» в ЧУЖОМ классе.
    override func tearDown() {
        store = nil
        pc = nil
        super.tearDown()
    }

    // MARK: - Фикстуры

    private func make(
        kind: DiscoveryKind = .riddle,
        key: String = "lighthouse-anapa",
        tripId: UUID = UUID(),
        foundAt: Date = Date(timeIntervalSince1970: 1_758_000_000),
        symbol: SealSymbol = .lighthouse,
        title: String? = nil
    ) -> Discovery {
        Discovery(
            kind: kind,
            key: key,
            tripId: tripId,
            coordinate: CLLocationCoordinate2D(latitude: 44.894, longitude: 37.316),
            foundAt: foundAt,
            symbol: symbol,
            title: title
        )
    }

    private func storedCount() -> Int {
        let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
        return (try? pc.container.viewContext.count(for: request)) ?? 0
    }

    // MARK: - Запись

    func testUpsertReturnsOnlyWhatWasNotThere() async throws {
        let first = try await store.upsert([make(key: "a"), make(key: "b")])
        XCTAssertEqual(Set(first.map(\.key)), ["a", "b"])

        let second = try await store.upsert([make(key: "a"), make(key: "c")])
        XCTAssertEqual(second.map(\.key), ["c"])
        XCTAssertEqual(storedCount(), 3)
    }

    /// Повтор той же находки — пустой ответ. Из ответа собирается блок
    /// «Открыто» на экране итогов, и второй проезд мимо маяка не имеет права
    /// показать его снова.
    func testRepeatFindsNothing() async throws {
        _ = try await store.upsert([make()])
        let again = try await store.upsert([make()])
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(storedCount(), 1)
    }

    /// Первая находка побеждает: второй проезд не передатирует печать и не
    /// перевешивает её на новую поездку.
    func testFirstFindKeepsItsTripAndDate() async throws {
        let firstTrip = UUID()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.upsert([make(tripId: firstTrip, foundAt: firstDate)])
        _ = try await store.upsert([make(tripId: UUID(), foundAt: Date())])

        let all = await store.all()
        let stored = try XCTUnwrap(all.first)
        XCTAssertEqual(stored.tripId, firstTrip)
        XCTAssertEqual(stored.foundAt, firstDate)
    }

    /// Один разбор трека может принести одну и ту же находку дважды (два
    /// попадания на «туда и обратно»): в базу она ложится одной строкой, и
    /// ограничение уникальности ничего не роняет.
    func testDuplicateInsideOneBatchLandsOnce() async throws {
        let added = try await store.upsert([make(), make(), make(key: "other")])
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(storedCount(), 2)
    }

    func testEmptyUpsertIsNoop() async throws {
        let nothing = try await store.upsert([])
        XCTAssertTrue(nothing.isEmpty)
        XCTAssertEqual(storedCount(), 0)
    }

    // MARK: - Чтение

    func testAllIsSortedByFoundAtDescending() async throws {
        let old = make(key: "old", foundAt: Date(timeIntervalSince1970: 1_000))
        let mid = make(key: "mid", foundAt: Date(timeIntervalSince1970: 2_000))
        let new = make(key: "new", foundAt: Date(timeIntervalSince1970: 3_000))
        _ = try await store.upsert([old, new, mid])

        let order = await store.all().map(\.key)
        XCTAssertEqual(order, ["new", "mid", "old"])
    }

    func testReadingKeepsEveryField() async throws {
        let found = make(kind: .secret, key: "komsomolsky", symbol: .generic, title: "Комсомольский")
        _ = try await store.upsert([found])

        let all = await store.all()
        let stored = try XCTUnwrap(all.first)
        XCTAssertEqual(stored, found)
        XCTAssertEqual(stored.id, Discovery.id(kind: .secret, key: "komsomolsky"))
        XCTAssertEqual(stored.coordinate.latitude, 44.894, accuracy: 0.000_001)
        XCTAssertEqual(stored.coordinate.longitude, 37.316, accuracy: 0.000_001)
        XCTAssertFalse(stored.verified)
    }

    func testDiscoveriesFilterByKind() async throws {
        _ = try await store.upsert([
            make(kind: .secret, key: "s"),
            make(kind: .riddle, key: "r"),
            make(kind: .milestone, key: "\(Milestone.firstRegion.rawValue):RU-KDA"),
        ])

        let secrets = await store.discoveries(kind: .secret).map(\.key)
        let riddles = await store.discoveries(kind: .riddle).map(\.key)
        let milestones = await store.discoveries(kind: .milestone)
        XCTAssertEqual(secrets, ["s"])
        XCTAssertEqual(riddles, ["r"])
        XCTAssertEqual(milestones.count, 1)
    }

    func testContainsAnswersById() async throws {
        let found = make(key: "a")
        _ = try await store.upsert([found])

        var has = await store.contains(id: found.id)
        XCTAssertTrue(has)
        has = await store.contains(id: Discovery.id(kind: .riddle, key: "never"))
        XCTAssertFalse(has)
    }

    // MARK: - Стирание

    func testWipeEmptiesEverything() async throws {
        _ = try await store.upsert([make(key: "a"), make(key: "b")])
        store.wipe()

        let left = await store.all()
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual(storedCount(), 0)
    }

    /// После стирания та же находка находится ЗАНОВО — id выведен из ключа, и
    /// строка встаёт на то же место.
    func testFindingAgainAfterWipeIsNew() async throws {
        _ = try await store.upsert([make()])
        store.wipe()

        let again = try await store.upsert([make()])
        XCTAssertEqual(again.count, 1)
        XCTAssertEqual(again.first?.id, Discovery.id(kind: .riddle, key: "lighthouse-anapa"))
    }

    // MARK: - Уведомление

    func testNewFindPostsDiscoveriesChanged() async throws {
        let expectation = expectation(forNotification: .discoveriesChanged, object: nil)
        _ = try await store.upsert([make()])
        await fulfillment(of: [expectation], timeout: 2)
    }
}
