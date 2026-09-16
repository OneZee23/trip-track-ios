import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Раскрытие находки: что уезжает, что дописывается и что происходит, когда
/// сеть упала.
///
/// Главный тест здесь — первый: без Cloud Sync не уходит НИ ОДНОГО запроса.
/// Заявка «я нашёл это» говорит, где человек был и когда, и правило проекта на
/// такие данные одно. Остальные держат обещание «сервер дополняет, а не
/// подменяет»: дата находки после ответа обязана остаться своей.
@MainActor
final class DiscoveryRevealTests: XCTestCase {

    private final class FakeTransport: SecretsTransport, @unchecked Sendable {
        let lock = NSLock()
        private var bodies: [SecretRevealRequest] = []
        var answer: ((SecretRevealRequest) throws -> SecretRevealResponse)?

        func catalog(version: String?) async throws -> SecretCatalogResponse {
            throw URLError(.unsupportedURL)
        }

        func reveal(_ body: SecretRevealRequest) async throws -> SecretRevealResponse {
            lock.lock()
            bodies.append(body)
            let answer = self.answer
            lock.unlock()
            guard let answer else { throw URLError(.notConnectedToInternet) }
            return try answer(body)
        }

        var sent: [SecretRevealRequest] {
            lock.lock(); defer { lock.unlock() }
            return bodies
        }
    }

    private var pc: PersistenceController!
    private var store: DiscoveryStore!
    private var transport: FakeTransport!
    private var queue: SyncQueue!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let tripId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        store = DiscoveryStore(persistence: pc)
        transport = FakeTransport()
        // Своя очередь, а не `SyncQueue.shared`: операция обязана долететь до
        // НАСТОЯЩЕЙ очереди (а не до счётчика в тесте), но общая пережила бы
        // весь прогон вместе с чужими ожиданиями.
        queue = SyncQueue()
    }

    override func tearDown() {
        queue = nil
        transport = nil
        store = nil
        pc = nil
        super.tearDown()
    }

    // MARK: - Фикстуры

    private func reveal(allowed: Bool) -> DiscoveryReveal {
        DiscoveryReveal(transport: transport, store: store,
                        isAllowed: { allowed },
                        enqueue: { [queue] op in queue?.enqueue(op) })
    }

    private func find(kind: DiscoveryKind, key: String, symbol: SealSymbol = .generic) -> Discovery {
        Discovery(kind: kind, key: key, tripId: tripId,
                  coordinate: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.97),
                  foundAt: t0, symbol: symbol)
    }

    /// Ответ строится ИЗ JSON, а не конструктором: `SecretRevealResponse`
    /// только `Decodable`, и проверять надо ровно то, что приедет с провода.
    private func answer(
        id: String, kind: String = "secret", verified: Bool = true,
        finders: Int = 7, first: String? = "Илья", rarity: String = "few",
        story: String? = "Улица, которой нет на указателях."
    ) throws -> SecretRevealResponse {
        let firstJSON = first.map { #"{"displayName":"\#($0)","foundAt":"2025-01-02T10:00:00.000Z"}"# }
            ?? "null"
        let storyJSON = story.map { "\"\($0)\"" } ?? "null"
        let json = """
            {"id":"\(id)","kind":"\(kind)","title":"Комсомольский","story":\(storyJSON),
             "symbol":"compass","verified":\(verified),
             "foundAt":"2026-09-16T12:00:00.000Z","finders":\(finders),
             "first":\(firstJSON),"rarity":"\(rarity)"}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = ISODate.parse(s) else { throw APIError.decoding(s) }
            return date
        }
        return try decoder.decode(SecretRevealResponse.self, from: Data(json.utf8))
    }

    // MARK: - Гейт

    /// Без Cloud Sync — ни одного запроса. Ни на секрет, ни на загадку.
    func testWithoutCloudSyncNothingLeavesThePhone() async throws {
        _ = try await store.upsert([find(kind: .secret, key: "komsomolsky"),
                                    find(kind: .riddle, key: "lighthouse:ubcr4xk")])
        transport.answer = { try self.answer(id: $0.id, kind: $0.kind) }

        await reveal(allowed: false).reveal(
            [find(kind: .secret, key: "komsomolsky")], tripId: tripId)

        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    /// Веха — собственная география: сервер про неё не знает и спрашивать его
    /// не о чем.
    func testMilestonesAreNeverRevealed() async throws {
        let items = [find(kind: .secret, key: "komsomolsky"),
                     find(kind: .riddle, key: "lighthouse:ubcr4xk"),
                     find(kind: .milestone, key: "firstRegion:RU-KDA")]
        _ = try await store.upsert(items)
        transport.answer = { try self.answer(id: $0.id, kind: $0.kind) }

        await reveal(allowed: true).reveal(items, tripId: tripId)

        XCTAssertEqual(transport.sent.map(\.id), ["komsomolsky", "lighthouse:ubcr4xk"])
        XCTAssertEqual(transport.sent.map(\.kind), ["secret", "riddle"])
        XCTAssertEqual(transport.sent.compactMap(\.tripId), [tripId, tripId])
    }

    // MARK: - Ответ

    /// Ответ ДОПИСЫВАЕТСЯ: история, счётчик, первооткрыватель, редкость — и
    /// дата находки при этом остаётся своей, хотя сервер прислал другую.
    func testAnswerIsAppendedAndFoundAtStaysLocal() async throws {
        _ = try await store.upsert([find(kind: .secret, key: "komsomolsky")])
        transport.answer = { try self.answer(id: $0.id) }

        await reveal(allowed: true).reveal(
            [find(kind: .secret, key: "komsomolsky")], tripId: tripId)

        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.story, "Улица, которой нет на указателях.")
        XCTAssertEqual(stored.title, "Комсомольский")
        XCTAssertEqual(stored.finders, 7)
        XCTAssertEqual(stored.firstFinderName, "Илья")
        XCTAssertNotNil(stored.firstFinderAt)
        XCTAssertEqual(stored.rarity, "few")
        XCTAssertTrue(stored.verified)
        XCTAssertEqual(stored.foundAt, t0, "серверная дата передатировала печать")
        XCTAssertEqual(stored.tripId, tripId)
    }

    /// `verified` ходит только false → true. Второй ответ, пришедший без
    /// подтверждения (трек ещё не уехал на сервер), не имеет права его снять.
    func testVerifiedNeverGoesBackToFalse() async throws {
        _ = try await store.upsert([find(kind: .secret, key: "komsomolsky")])
        let service = reveal(allowed: true)
        transport.answer = { try self.answer(id: $0.id, verified: true) }
        await service.reveal([find(kind: .secret, key: "komsomolsky")], tripId: tripId)

        transport.answer = { try self.answer(id: $0.id, verified: false) }
        await service.reveal([find(kind: .secret, key: "komsomolsky")], tripId: tripId)

        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertTrue(stored.verified)
    }

    /// Непубличный первооткрыватель: факт есть, имени нет.
    func testAnonymousFirstFinderKeepsTheDateWithoutTheName() async throws {
        _ = try await store.upsert([find(kind: .secret, key: "komsomolsky")])
        transport.answer = { try self.answer(id: $0.id, first: nil) }

        await reveal(allowed: true).reveal(
            [find(kind: .secret, key: "komsomolsky")], tripId: tripId)

        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertNil(stored.firstFinderName)
        XCTAssertNil(stored.firstFinderAt)
        XCTAssertEqual(stored.finders, 7)
    }

    // MARK: - Сеть упала

    func testNetworkFailureQueuesTheDiscovery() async throws {
        let item = find(kind: .secret, key: "komsomolsky")
        _ = try await store.upsert([item])
        transport.answer = nil  // бросает `notConnectedToInternet`

        await reveal(allowed: true).reveal([item], tripId: tripId)

        XCTAssertEqual(queue.pending.count, 1)
        let op = try XCTUnwrap(queue.pending.first)
        XCTAssertEqual(op.entityType, .discovery)
        XCTAssertEqual(op.action, .upload)
        XCTAssertEqual(op.entityId, item.id)
        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertNil(stored.story, "упавший запрос не имеет права ничего дописать")
    }

    /// Повтор из очереди: по одному только id находится находка, спрашивается
    /// сервер и дописывается ответ.
    func testRetryFromTheQueueFindsTheDiscoveryById() async throws {
        let item = find(kind: .riddle, key: "lighthouse:ubcr4xk")
        _ = try await store.upsert([item])
        transport.answer = { try self.answer(id: $0.id, kind: $0.kind) }

        try await reveal(allowed: true).retry(id: item.id)

        XCTAssertEqual(transport.sent.map(\.id), ["lighthouse:ubcr4xk"])
        XCTAssertEqual(transport.sent.first?.tripId, tripId)
        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.finders, 7)
    }

    /// Повтор бросает — очередь обязана попробовать ещё раз, а не считать
    /// операцию выполненной.
    func testRetryThrowsOnNetworkError() async throws {
        let item = find(kind: .secret, key: "komsomolsky")
        _ = try await store.upsert([item])
        transport.answer = nil

        do {
            try await reveal(allowed: true).retry(id: item.id)
            XCTFail("повтор проглотил сетевую ошибку")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    /// Находки уже нет (стёрли аккаунт) — повторять нечего, и бросать тоже:
    /// операция снимается с очереди, а не висит в ней вечно.
    func testRetryOfAVanishedDiscoveryIsSilent() async throws {
        try await reveal(allowed: true).retry(id: UUID())
        XCTAssertTrue(transport.sent.isEmpty)
    }

    /// Облако выключили между находкой и повтором — запрос не уходит.
    func testRetryRespectsTheGate() async throws {
        let item = find(kind: .secret, key: "komsomolsky")
        _ = try await store.upsert([item])
        transport.answer = { try self.answer(id: $0.id) }

        try await reveal(allowed: false).retry(id: item.id)

        XCTAssertTrue(transport.sent.isEmpty)
    }

    // MARK: - Сервер отказал навсегда

    /// `SECRET_NOT_FOUND` — ответ, который не изменится ни через минуту, ни
    /// через сутки. Повтор вернул бы то же самое пять раз подряд, после чего
    /// строка навсегда краснеет в «Синхронизации», и снять её человек не может
    /// ничем. Поэтому такой отказ роняется, а не встаёт в очередь.
    func testPermanentRejectionIsDroppedInsteadOfQueued() async throws {
        let item = find(kind: .secret, key: "komsomolsky")
        _ = try await store.upsert([item])
        transport.answer = { _ in
            throw APIError.unknownServer(code: "SECRET_NOT_FOUND", message: "no such secret")
        }

        await reveal(allowed: true).reveal([item], tripId: tripId)

        XCTAssertEqual(queue.pendingCount, 0, "постоянный отказ припарковался в очереди")
        XCTAssertEqual(transport.sent.count, 1)
    }

    /// Четыре сотни — тот же класс: наш запрос не годится, и повтор его не
    /// вылечит. Разделение 4xx/5xx здесь то же, что у `APIClient`.
    func testClientSideHTTPStatusIsAlsoDropped() async throws {
        let item = find(kind: .secret, key: "komsomolsky")
        _ = try await store.upsert([item])
        transport.answer = { _ in throw APIError.invalidHTTPStatus(404) }

        await reveal(allowed: true).reveal([item], tripId: tripId)

        XCTAssertEqual(queue.pendingCount, 0)
    }

    /// А пять сотен — икота сервера: её повторяют, и находка обязана лечь в
    /// очередь ровно как при обрыве сети.
    func testServerHiccupStillQueues() async throws {
        let item = find(kind: .secret, key: "komsomolsky")
        _ = try await store.upsert([item])
        transport.answer = { _ in throw APIError.invalidHTTPStatus(503) }

        await reveal(allowed: true).reveal([item], tripId: tripId)

        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.entityType, .discovery)
    }

    /// Троттлинг и таймаут — из четырёхсотых, но про «попробуй позже»: они
    /// остаются в очереди.
    func testThrottlingAndTimeoutStayInTheQueue() async throws {
        for status in [408, 429] {
            let store = DiscoveryStore(persistence: pc)
            let queue = SyncQueue()
            let item = find(kind: .secret, key: "komsomolsky")
            _ = try await store.upsert([item])
            let service = DiscoveryReveal(
                transport: transport, store: store, isAllowed: { true },
                enqueue: { queue.enqueue($0) })
            transport.answer = { _ in throw APIError.invalidHTTPStatus(status) }

            await service.reveal([item], tripId: tripId)

            XCTAssertEqual(queue.pendingCount, 1, "статус \(status) выкинули из очереди")
        }
    }

    /// Повтор из очереди на постоянном отказе НЕ бросает: `SyncQueue` снимает
    /// операцию, вернувшуюся из `execute` молча, — иначе она вечно висела бы в
    /// красных.
    func testRetryDoesNotThrowOnAPermanentRejection() async throws {
        let item = find(kind: .secret, key: "komsomolsky")
        _ = try await store.upsert([item])
        transport.answer = { _ in
            throw APIError.unknownServer(code: "SECRET_NOT_FOUND", message: "no such secret")
        }

        try await reveal(allowed: true).retry(id: item.id)

        XCTAssertEqual(transport.sent.count, 1)
        let rows = await store.all()
        let stored = try XCTUnwrap(rows.first)
        XCTAssertNil(stored.story, "отказ не имеет права ничего дописать")
    }

    /// Чистая функция решения — отдельно от сети: её читает и `reveal`, и
    /// `retry`, и разойтись этим двум ответам нельзя.
    func testPermanenceDecision() {
        XCTAssertTrue(DiscoveryReveal.isPermanent(
            APIError.unknownServer(code: "SECRET_NOT_FOUND", message: "")))
        XCTAssertTrue(DiscoveryReveal.isPermanent(APIError.validationFailed("bad id")))
        XCTAssertTrue(DiscoveryReveal.isPermanent(APIError.invalidHTTPStatus(400)))
        XCTAssertFalse(DiscoveryReveal.isPermanent(APIError.invalidHTTPStatus(500)))
        XCTAssertFalse(DiscoveryReveal.isPermanent(APIError.tooManyRequests))
        XCTAssertFalse(DiscoveryReveal.isPermanent(APIError.network(URLError(.timedOut))))
        XCTAssertFalse(DiscoveryReveal.isPermanent(URLError(.notConnectedToInternet)))
        // Незнакомый код сервера — НЕ постоянный: список кодов закрытый
        // нарочно, иначе новая ошибка бэкенда молча съедала бы находки.
        XCTAssertFalse(DiscoveryReveal.isPermanent(
            APIError.unknownServer(code: "SOMETHING_NEW", message: "")))
    }

    /// В лог уезжает КОД, а не `localizedDescription`: в нём едет сообщение
    /// СЕРВЕРА — тот же класс данных, который чистит `PIIScrubber`.
    func testReasonCarriesTheCodeAndNotTheServerText() {
        let reason = DiscoveryReveal.reason(
            APIError.unknownServer(code: "SECRET_NOT_FOUND", message: "account 42 at 45.03,38.97"))
        XCTAssertEqual(reason, "server SECRET_NOT_FOUND")
        XCTAssertFalse(reason.contains("45.03"))
    }
}
