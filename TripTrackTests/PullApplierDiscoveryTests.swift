import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Находки, приехавшие пулом со ВТОРОГО телефона того же человека.
///
/// Место берётся в три шага, и все три проверяются здесь: координата самой
/// строки (её сервер шлёт ТОЛЬКО у подтверждённой находки), иначе собственный
/// ключ загадки (`"<type>:<geohash7>"`), иначе никак — секрет без места пул
/// ПРОПУСКАЕТ, печать в нулях встала бы в Гвинейский залив. Уже лежащей
/// находке пул дописывает текст и `verified`, но не двигает ни дату, ни
/// поездку: первая находка побеждает.
@MainActor
final class PullApplierDiscoveryTests: XCTestCase {
    private var pc: PersistenceController!
    private var store: DiscoveryStore!
    private var applier: PullApplier!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let tripId = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = DiscoveryStore(persistence: pc)
        applier = PullApplier(discoveries: store)
    }

    override func tearDown() {
        applier = nil
        store = nil
        pc = nil
        super.tearDown()
    }

    // MARK: - Фикстуры

    private func payload(
        secretId: String, kind: String, foundAt: Date? = nil, verified: Bool? = false,
        tripId: UUID? = nil, title: String? = nil, story: String? = nil,
        symbol: String? = "light.beacon.max",
        latitude: Double? = nil, longitude: Double? = nil,
        keepTripIdNil: Bool = false
    ) -> DiscoverySyncPayload {
        DiscoverySyncPayload(
            secretId: secretId, kind: kind, symbol: symbol,
            foundAt: foundAt ?? t0.addingTimeInterval(86_400), verified: verified,
            tripId: keepTripIdNil ? nil : (tripId ?? self.tripId),
            latitude: latitude, longitude: longitude, title: title, story: story)
    }

    private func response(_ items: [DiscoverySyncPayload]) -> SyncPullResponse {
        SyncPullResponse(
            trips: .init(upserted: [], deleted: []),
            vehicles: .init(upserted: [], deleted: []),
            photos: .init(upserted: [], deleted: []),
            settings: nil, serverTime: "2026-09-16T12:00:00.000Z", ownedCounts: nil,
            journeys: nil, discoveries: .init(upserted: items, deleted: []))
    }

    // MARK: - Место находки

    /// Загадка встаёт туда, где стоит её ячейка: geohash-7 лежит во второй
    /// половине собственного ключа, и это те же ±75 м, что у самой загадки.
    func testRiddleFromTheSecondPhoneIsPlacedFromItsOwnKey() async {
        applier.apply(response([payload(secretId: "lighthouse:ubcr4xk", kind: "riddle",
                                        title: "Анапский маяк")]))

        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        let stored = all[0]
        XCTAssertEqual(stored.key, "lighthouse:ubcr4xk")
        XCTAssertEqual(stored.title, "Анапский маяк")
        XCTAssertEqual(stored.symbol, .lighthouse)
        let expected = GeohashEncoder.centerCoordinate(of: "ubcr4xk")
        XCTAssertEqual(stored.coordinate.latitude, expected.latitude, accuracy: 0.000_001)
        XCTAssertEqual(stored.coordinate.longitude, expected.longitude, accuracy: 0.000_001)
        XCTAssertEqual(stored.id, Discovery.id(kind: .riddle, key: "lighthouse:ubcr4xk"))
    }

    /// Секрет без места не заводится. Иначе печать встала бы в (0, 0) — точку
    /// в океане, а не «неизвестно»: у координат в базе нет пустого значения.
    func testSecretWithoutAPlaceIsSkipped() async {
        applier.apply(response([payload(secretId: "komsomolsky", kind: "secret",
                                        story: "История", symbol: "seal")]))

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    /// Но текст ТОГО ЖЕ секрета, уже найденного здесь, пул дописывает — и не
    /// трогает ни дату, ни поездку.
    func testKnownSecretIsEnrichedWithoutMoving() async throws {
        let mine = Discovery(
            kind: .secret, key: "komsomolsky", tripId: tripId,
            coordinate: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.97),
            foundAt: t0, symbol: .generic)
        _ = try await store.upsert([mine])

        applier.apply(response([payload(
            secretId: "komsomolsky", kind: "secret", foundAt: t0.addingTimeInterval(86_400),
            verified: true, tripId: UUID(), title: "Комсомольский",
            story: "Улица, которой нет на указателях.", symbol: "seal")]))

        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        let stored = all[0]
        XCTAssertEqual(stored.story, "Улица, которой нет на указателях.")
        XCTAssertEqual(stored.title, "Комсомольский")
        XCTAssertTrue(stored.verified)
        XCTAssertEqual(stored.foundAt, t0, "пул передатировал печать")
        XCTAssertEqual(stored.tripId, tripId, "пул перевесил печать на чужую поездку")
        XCTAssertEqual(stored.coordinate.latitude, 45.03, accuracy: 0.000_001)
    }

    // MARK: - Повторы и мусор

    /// Тот же пул дважды (перезапрос после обрыва) — одна строка, а не две.
    func testRepeatedPullDoesNotDuplicate() async {
        let section = response([payload(secretId: "pass:ubcr4xk", kind: "riddle")])
        applier.apply(section)
        applier.apply(section)

        let all = await store.all()
        XCTAssertEqual(all.count, 1)
    }

    /// Незнакомый вид и ключ без ячейки — всё это «не поставить», и ни одно из
    /// них не роняет пул.
    func testUnplaceableRowsAreIgnored() async {
        applier.apply(response([
            payload(secretId: "whatever", kind: "constellation"),
            payload(secretId: "brokenkey", kind: "riddle"),
        ]))

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    /// Строка без `tripId` не ЗАВОДИТСЯ: по ней некуда открыть поездку, а
    /// выдуманный id указывал бы в пустоту. Разбор её при этом переживает —
    /// `tripId` нужен только заведению.
    func testRowWithoutTripIdIsNotPlaced() async {
        let raw = payload(secretId: "pass:ubcr4xk", kind: "riddle", keepTripIdNil: true)
        let made = PullApplier.remote(from: raw)
        XCTAssertNotNil(made)
        XCTAssertNil(made?.tripId)

        applier.apply(response([raw]))
        let all = await store.all()
        XCTAssertTrue(all.isEmpty, "находка без поездки не имеет права завестись")
    }

    /// ...но уже лежащей находке та же строка дописывает текст: `tripId` нужен
    /// заведению, а не обогащению.
    func testRowWithoutTripIdStillEnrichesAKnownFind() async throws {
        _ = try await store.upsert([Discovery(
            kind: .riddle, key: "pass:ubcr4xk", tripId: tripId,
            coordinate: CLLocationCoordinate2D(latitude: 44.8, longitude: 37.3),
            foundAt: t0, symbol: .pass)])

        applier.apply(response([payload(
            secretId: "pass:ubcr4xk", kind: "riddle", verified: true,
            title: "Гумбаши", story: "История", keepTripIdNil: true)]))

        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.story, "История")
        XCTAssertTrue(stored.verified)
        XCTAssertEqual(stored.tripId, tripId)
    }

    /// Секция отсутствует целиком — старый сервер, и это не «находок нет».
    func testMissingSectionChangesNothing() async throws {
        _ = try await store.upsert([Discovery(
            kind: .riddle, key: "pass:ubcr4xk", tripId: tripId,
            coordinate: CLLocationCoordinate2D(latitude: 44.8, longitude: 37.3),
            foundAt: t0, symbol: .pass)])

        applier.apply(SyncPullResponse(
            trips: .init(upserted: [], deleted: []),
            vehicles: .init(upserted: [], deleted: []),
            photos: .init(upserted: [], deleted: []),
            settings: nil, serverTime: "2026-09-16T12:00:00.000Z", ownedCounts: nil,
            journeys: nil, discoveries: nil))

        let all = await store.all()
        XCTAssertEqual(all.count, 1)
    }

    /// Сервер досылает ту же строку с поднятым `verified` (трек доехал позже —
    /// у `secret_find` для этого есть `updated_at`). Флаг обязан подняться на
    /// уже лежащей находке, ничего больше не тронув.
    func testLaterPullFlipsVerifiedOnAnExistingRow() async throws {
        applier.apply(response([payload(secretId: "pass:ubcr4xk", kind: "riddle",
                                        verified: false, title: "Гумбаши")]))
        var first = await store.all()
        XCTAssertEqual(first.count, 1)
        XCTAssertFalse(try XCTUnwrap(first.first).verified)
        let placedAt = try XCTUnwrap(first.first).foundAt

        applier.apply(response([payload(secretId: "pass:ubcr4xk", kind: "riddle",
                                        foundAt: placedAt.addingTimeInterval(3_600),
                                        verified: true, title: "Гумбаши")]))

        first = await store.all()
        XCTAssertEqual(first.count, 1)
        let stored = try XCTUnwrap(first.first)
        XCTAssertTrue(stored.verified)
        XCTAssertEqual(stored.foundAt, placedAt)
    }

    // MARK: - Координата из строки пула

    /// Подтверждённый секрет со второго телефона ВСТАЁТ печатью здесь: центр
    /// первой ячейки заявки сервер прислал сам (фикс-волна волны 3), и
    /// выводить место больше неоткуда — в каталоге лежат одни усечённые хеши.
    func testVerifiedSecretIsPlacedFromTheRowCoordinate() async throws {
        applier.apply(response([payload(
            secretId: "komsomolsky", kind: "secret", verified: true,
            title: "Комсомольский", symbol: "seal",
            latitude: 45.035, longitude: 38.975)]))

        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.key, "komsomolsky")
        XCTAssertEqual(stored.coordinate.latitude, 45.035, accuracy: 0.000_001)
        XCTAssertEqual(stored.coordinate.longitude, 38.975, accuracy: 0.000_001)
        XCTAssertTrue(stored.verified)
    }

    /// Неподтверждённая находка координаты от сервера не получает никогда —
    /// но если она всё же пришла, ставить по ней печать нельзя: контракт на
    /// той стороне изменился, и ручаться за место некому.
    func testUnverifiedRowIsNeverPlacedByItsCoordinate() async {
        applier.apply(response([payload(
            secretId: "komsomolsky", kind: "secret", verified: false, symbol: "seal",
            latitude: 45.035, longitude: 38.975)]))

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    /// Половина пары — это не место. Одна широта без долготы значит ровно
    /// столько же, сколько их полное отсутствие.
    func testHalfACoordinateIsIgnored() async {
        applier.apply(response([payload(
            secretId: "komsomolsky", kind: "secret", verified: true, symbol: "seal",
            latitude: 45.035, longitude: nil)]))

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    /// Ровные нули — не «неизвестно», а точка в Гвинейском заливе.
    func testZeroZeroIsNotAPlace() async {
        applier.apply(response([payload(
            secretId: "komsomolsky", kind: "secret", verified: true, symbol: "seal",
            latitude: 0, longitude: 0)]))

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    /// У загадки координата строки побеждает вывод по ключу: сервер знает
    /// ячейку заявки, а ключ — только ячейку самой загадки.
    func testRowCoordinateWinsOverTheKeyForARiddle() async throws {
        applier.apply(response([payload(
            secretId: "pass:ubcr4xk", kind: "riddle", verified: true,
            latitude: 43.5, longitude: 42.5)]))

        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.coordinate.latitude, 43.5, accuracy: 0.000_001)
        XCTAssertEqual(stored.coordinate.longitude, 42.5, accuracy: 0.000_001)
    }

    // MARK: - `deleted` в секции

    /// Ключ находки — строка (`"pass:ubcr4xk"`), а не UUID. Непустой список
    /// удалённых обязан РАЗБИРАТЬСЯ: `[UUID]` уронил бы не секцию находок, а
    /// весь `/sync/pull`.
    func testNonEmptyDeletedListDoesNotBreakTheWholePull() throws {
        let json = """
        {"trips":{"upserted":[],"deleted":[]},"vehicles":{"upserted":[],"deleted":[]},\
        "photos":{"upserted":[],"deleted":[]},"settings":null,\
        "serverTime":"2026-09-16T12:00:00.000Z","ownedCounts":null,"journeys":null,\
        "discoveries":{"upserted":[],"deleted":["pass:ubcr4xk","komsomolsky"]}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = ISODate.parse(s) else { throw APIError.decoding(s) }
            return date
        }
        let response = try decoder.decode(SyncPullResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.discoveries?.deleted, ["pass:ubcr4xk", "komsomolsky"])
    }

    /// Ключ загадки короче семи символов — это не ячейка geohash-7, и центра
    /// у неё нет: ставить по такой строке печать нельзя.
    func testShortGeohashKeyIsNotAPlace() async {
        applier.apply(response([payload(secretId: "pass:ubcr", kind: "riddle")]))
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    /// Незнакомый символ с сервера — печать `generic`, а не пропущенная строка:
    /// гравюры волны 5 доедут раньше, чем эта сборка о них узнает.
    func testUnknownSymbolFallsBackToGeneric() {
        let made = PullApplier.remote(from: payload(
            secretId: "bridge:ubcr4xk", kind: "riddle", symbol: "engraving.wave5"))
        XCTAssertEqual(made?.symbol, .generic)
    }
}
