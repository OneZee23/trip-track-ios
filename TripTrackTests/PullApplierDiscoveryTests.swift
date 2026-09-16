import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Находки, приехавшие пулом со ВТОРОГО телефона того же человека.
///
/// Контракт волны 3 везёт заявку без координаты — сервер её не хранит. Отсюда
/// два правила, и оба проверяются здесь: у загадки место выводится из её же
/// ключа (`"<type>:<geohash7>"`), а секрет, которого на этом телефоне ещё нет,
/// пул ПРОПУСКАЕТ — печать без места встала бы в нули, то есть в Гвинейский
/// залив. Уже лежащей находке пул дописывает текст и `verified`, но не двигает
/// ни дату, ни поездку: первая находка побеждает.
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
        symbol: String? = "light.beacon.max"
    ) -> DiscoverySyncPayload {
        DiscoverySyncPayload(
            secretId: secretId, kind: kind, symbol: symbol,
            foundAt: foundAt ?? t0.addingTimeInterval(86_400), verified: verified,
            tripId: tripId ?? self.tripId, title: title, story: story)
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

    /// Строка без `tripId` не заводится: по ней некуда открыть поездку, а
    /// выдуманный id указывал бы в пустоту.
    func testRowWithoutTripIdIsSkipped() {
        let raw0 = payload(secretId: "pass:ubcr4xk", kind: "riddle")
        var raw = raw0
        raw = DiscoverySyncPayload(
            secretId: raw.secretId, kind: raw.kind, symbol: raw.symbol, foundAt: raw.foundAt,
            verified: raw.verified, tripId: nil, title: raw.title, story: raw.story)
        XCTAssertNil(PullApplier.remote(from: raw))
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

    /// Незнакомый символ с сервера — печать `generic`, а не пропущенная строка:
    /// гравюры волны 5 доедут раньше, чем эта сборка о них узнает.
    func testUnknownSymbolFallsBackToGeneric() {
        let made = PullApplier.remote(from: payload(
            secretId: "bridge:ubcr4xk", kind: "riddle", symbol: "engraving.wave5"))
        XCTAssertEqual(made?.symbol, .generic)
    }
}
