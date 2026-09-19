import XCTest
@testable import TripTrack

/// Привязка покупки к аккаунту: одна транзакция уезжает ровно один раз, сеть
/// повторяется, и человеку про это не говорят ничего.
@MainActor
final class PlusAttachTests: XCTestCase {

    /// Транспорт-заглушка. Считает ПОПЫТКИ, а не доставки: «повторили» и
    /// «отправили дважды» — разные вещи, и различить их можно только так.
    private final class StubTransport: PlusTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var _attempts: [String] = []
        private var _failuresLeft = 0
        private var _error: Error = URLError(.notConnectedToInternet)

        var attempts: [String] { lock.lock(); defer { lock.unlock() }; return _attempts }

        func fail(times: Int, with error: Error = URLError(.notConnectedToInternet)) {
            lock.lock(); defer { lock.unlock() }
            _failuresLeft = times
            _error = error
        }

        func attach(signedTransaction: String) async throws -> PlusStatusResponse {
            lock.lock()
            _attempts.append(signedTransaction)
            let shouldFail = _failuresLeft > 0
            if shouldFail { _failuresLeft -= 1 }
            let error = _error
            lock.unlock()
            if shouldFail { throw error }
            return PlusStatusResponse(
                active: true, until: nil, productId: PlusStore.yearlyID, isTrial: true)
        }

        func status() async throws -> PlusStatusResponse {
            PlusStatusResponse(active: false, until: nil, productId: nil, isTrial: false)
        }
    }

    /// Подписи в прогоне — в памяти, а не в Keychain: боевое хранилище одно
    /// на приложение, и тест, писавший в него, оставлял бы подпись следующему
    /// (и, хуже, следующему ПРОГОНУ).
    private final class MemoryVault: PlusJWSVault {
        private var rows: [String: String] = [:]
        func read() -> [String: String] { rows }
        func write(_ rows: [String: String]) { self.rows = rows }
    }

    private var vault: MemoryVault!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var transport: StubTransport!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        suiteName = "plus.attach.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        vault = MemoryVault()
        transport = StubTransport()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    /// Поля обнуляются руками: XCTest держит каждый экземпляр до конца
    /// прогона, и не отпущенный сюит `UserDefaults` пережил бы весь набор.
    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        vault = nil
        suiteName = nil
        transport = nil
        MockURLProtocol.reset()
        // Незакрытая `URLSession` держит очередь и `MockURLProtocol` до конца
        // прогона — и роняет ЧУЖОЙ класс (см. «Ловушки» в CLAUDE.md).
        session?.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    private func makeQueue(
        signedIn: Bool = true, build: String = "62", after: TimeInterval = 0
    ) -> PlusAttachQueue {
        let clock = Date().addingTimeInterval(after)
        return PlusAttachQueue(
            transport: transport,
            isAllowed: { signedIn },
            defaults: defaults,
            vault: vault,
            build: build,
            backoff: { _ in },  // откат мгновенный: предмет проверки — счёт попыток
            now: { clock }
        )
    }

    private func waitUntil(
        _ timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Один раз

    func testATransactionIsPostedOnceHoweverOftenItArrives() async {
        let queue = makeQueue()
        // Три двери к одной покупке: `purchase`, `Transaction.updates` и
        // `currentEntitlements` на старте. Все три несут один `originalID`.
        queue.enqueue(key: "2000000123", jws: "jws-a")
        queue.enqueue(key: "2000000123", jws: "jws-a")
        await queue.drain()
        queue.enqueue(key: "2000000123", jws: "jws-a")
        await queue.drain()

        await waitUntil { queue.pending.isEmpty }
        XCTAssertEqual(transport.attempts, ["jws-a"])
        XCTAssertEqual(queue.sent, ["2000000123"])
    }

    func testTwoDifferentTransactionsBothGoOut() async {
        let queue = makeQueue()
        queue.enqueue(key: "A", jws: "jws-a")
        queue.enqueue(key: "B", jws: "jws-b")
        await queue.drain()
        await waitUntil { queue.pending.isEmpty }
        XCTAssertEqual(transport.attempts.sorted(), ["jws-a", "jws-b"])
    }

    // MARK: - Повтор

    func testTransientFailureIsRetriedUntilItLands() async {
        transport.fail(times: 2)
        let queue = makeQueue()
        queue.enqueue(key: "A", jws: "jws-a")
        await queue.drain()

        await waitUntil { queue.pending.isEmpty }
        XCTAssertEqual(transport.attempts.count, 3, "две неудачи и доставка")
        XCTAssertEqual(queue.sent, ["A"])
    }

    /// Самолёт: пять попыток и тишина. Ни броска, ни падения, ни строки на
    /// экране — заявка ждёт следующего запуска.
    func testOfflineLeavesItQueuedAndSaysNothing() async {
        transport.fail(times: .max)
        let queue = makeQueue()
        queue.enqueue(key: "A", jws: "jws-a")
        await queue.drain()

        await waitUntil { transport.attempts.count >= PlusAttachQueue.maxAttempts }
        XCTAssertEqual(transport.attempts.count, PlusAttachQueue.maxAttempts)
        XCTAssertEqual(queue.pending.map(\.key), ["A"], "заявка осталась в очереди")
        XCTAssertTrue(queue.sent.isEmpty)
    }

    /// Пережила убийство приложения на парковке: очередь лежит на диске, а не
    /// в памяти.
    func testPendingSurvivesARelaunch() async {
        transport.fail(times: .max)
        let first = makeQueue()
        first.enqueue(key: "A", jws: "jws-a")
        await first.drain()
        await waitUntil { transport.attempts.count >= PlusAttachQueue.maxAttempts }

        transport.fail(times: 0)
        // Заявка после пяти неудач спит минуту — человек вернулся позже.
        let second = makeQueue(after: 2 * 3600)
        XCTAssertEqual(second.pending.map(\.key), ["A"])
        await second.drain()
        await waitUntil { second.pending.isEmpty }
        XCTAssertEqual(second.sent, ["A"])
    }

    // MARK: - Постоянный отказ

    /// Транзакция чужого аккаунта — ответ навсегда. Повторять её пять раз
    /// значит пять раз получить то же самое.
    func testPermanentRejectionIsTriedOnceAndThenSleeps() async {
        transport.fail(times: .max, with: APIError.unknownServer(
            code: "PLUS_BELONGS_TO_ANOTHER", message: ""))
        let queue = makeQueue()
        queue.enqueue(key: "A", jws: "jws-a")
        await queue.drain()

        await waitUntil { !queue.pending.isEmpty && transport.attempts.count == 1 }
        XCTAssertEqual(transport.attempts.count, 1)
        await queue.drain()
        XCTAssertEqual(transport.attempts.count, 1, "той же сборкой — ни одной новой попытки")
    }

    /// **Находка аудита H2.** 404 значит «маршрута ещё нет» (он катится
    /// отдельной задачей), 401 — «токен ещё не обновился». Раньше любой из
    /// них снимал заявку И клал её ключ в `sent`, откуда `enqueue` больше не
    /// выпускал: деньги списаны, сервер о подписке не знает НИКОГДА, и
    /// лечится это только переустановкой приложения.
    func testARouteThatIsNotDeployedYetDoesNotOrphanTheSubscriptionForever() async {
        transport.fail(times: .max, with: APIError.invalidHTTPStatus(404))
        let queue = makeQueue()
        queue.enqueue(key: "2000000123456789", jws: "JWS-REAL")

        await waitUntil { transport.attempts.count >= PlusAttachQueue.maxAttempts }
        XCTAssertEqual(queue.pending.map(\.key), ["2000000123456789"],
                       "заявка осталась в очереди")
        XCTAssertTrue(queue.sent.isEmpty, "и НЕ записана как доставленная")

        // Сервер починили, человек вернулся в приложение позже отката.
        transport.fail(times: 0)
        let later = makeQueue(after: 2 * 3600)
        XCTAssertEqual(later.pending.map(\.key), ["2000000123456789"])
        await later.drain()
        await waitUntil { later.pending.isEmpty }
        XCTAssertEqual(later.sent, ["2000000123456789"], "и доехала")
    }

    /// Отказ ПО СМЫСЛУ спит до следующей сборки — но не дольше: новая сборка
    /// шлёт другой запрос, и хоронить оплаченную подписку из-за вчерашней
    /// ошибки клиента нельзя.
    func testASemanticRejectionIsRetriedOnceAfterTheNextAppUpdate() async {
        transport.fail(times: .max, with: APIError.invalidHTTPStatus(422))
        let queue = makeQueue(build: "62")
        queue.enqueue(key: "A", jws: "jws-a")
        await waitUntil { transport.attempts.count == 1 }
        await queue.drain()
        XCTAssertEqual(transport.attempts.count, 1)

        transport.fail(times: 0)
        let updated = makeQueue(build: "63")
        await updated.drain()
        await waitUntil { updated.pending.isEmpty }
        XCTAssertEqual(transport.attempts.count, 2, "обновление будит заявку ровно один раз")
        XCTAssertEqual(updated.sent, ["A"])
    }

    /// Чужая подписка (`PLUS_BELONGS_TO_ANOTHER`) не повторяется вечно:
    /// «после каждого обновления» без счётчика означало, что её подписанный
    /// чек лежит у нас в Keychain до переустановки, а запрос уходит на сервер
    /// после каждого релиза. Три разные сборки — и заявка выброшена вместе с
    /// подписью.
    func testAForeignSubscriptionIsGivenUpAfterThreeBuilds() async {
        transport.fail(times: .max, with: APIError.unknownServer(
            code: "PLUS_BELONGS_TO_ANOTHER", message: ""))

        for (index, build) in ["62", "63", "64"].enumerated() {
            let queue = makeQueue(build: build)
            if index == 0 { queue.enqueue(key: "A", jws: "jws-a") } else { await queue.drain() }
            // Ждём СОСТОЯНИЕ очереди, а не счётчик попыток: `enqueue` пускает
            // дренаж отдельной задачей, и попытка успевает случиться раньше,
            // чем отказ ляжет на диск.
            await waitUntil { queue.pending.first?.rejectedBuilds.contains(build) ?? true }
            XCTAssertEqual(transport.attempts.count, index + 1,
                           "по одной попытке на сборку, не больше")
            if index < 2 {
                XCTAssertEqual(queue.pending.map(\.key), ["A"])
            } else {
                XCTAssertTrue(queue.pending.isEmpty, "на третьей сборке заявка выброшена")
                XCTAssertNil(vault.read()["A"], "и подпись ушла из Keychain вместе с ней")
            }
        }

        // Четвёртая сборка не находит уже ничего.
        let after = makeQueue(build: "65")
        await after.drain()
        XCTAssertEqual(transport.attempts.count, 3)
    }

    /// Очередь не растёт без предела: полсотни подписанных чеков — это уже не
    /// очередь, а накопитель. Выбрасывается самая старая.
    func testTheQueueIsCappedAndDropsTheOldest() async {
        transport.fail(times: .max)
        let queue = makeQueue()
        for i in 0...PlusAttachQueue.maxPending {
            queue.enqueue(key: "K\(i)", jws: "jws-\(i)")
        }
        XCTAssertEqual(queue.pending.count, PlusAttachQueue.maxPending)
        XCTAssertNil(queue.pending.first { $0.key == "K0" }, "самая старая выброшена")
        XCTAssertNotNil(queue.pending.first { $0.key == "K\(PlusAttachQueue.maxPending)" })
        XCTAssertNil(vault.read()["K0"], "и её подпись тоже")
    }

    /// Бухгалтерия лежит в общих `UserDefaults`, а подпись — в Keychain, имя
    /// сервиса которого собрано из bundle id и ХОСТА API. Переезд между
    /// локальным бэкендом и продом внутри одной сборки оставляет строки без
    /// подписей: чистим их и говорим об этом одной строкой, без единого
    /// идентификатора.
    func testBookkeepingWithoutSignaturesIsClearedWhenTheHostChanges() {
        defaults.set([["k": "A", "a": 2], ["k": "B", "a": 0]], forKey: "plus.attach.pending.v2")
        // Keychain отвечает по другому имени сервиса — подписей к этим ключам нет.
        vault.write([:])

        let queue = makeQueue()

        XCTAssertTrue(queue.pending.isEmpty, "заявка без подписи — не заявка")
        let rows = defaults.array(forKey: "plus.attach.pending.v2") as? [[String: Any]]
        XCTAssertEqual(rows?.count, 0, "бухгалтерия осиротевших строк вычищена")
    }

    func testPermanenceRule() {
        XCTAssertTrue(PlusAttachQueue.isPermanent(APIError.validationFailed("")))
        XCTAssertTrue(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(400)))
        XCTAssertTrue(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(409)))
        XCTAssertTrue(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(422)))
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(404)),
                       "маршрут ещё не выкачен — это «попробуй позже», а не «никогда»")
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(410)))
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(401)),
                       "токен ещё не обновился")
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(403)))
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(429)),
                       "троттлинг — это «попробуй позже»")
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(408)))
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(503)))
        XCTAssertFalse(PlusAttachQueue.isPermanent(URLError(.notConnectedToInternet)))
    }

    /// Откат растёт вдвое и упирается в сутки — дальше растить бессмысленно:
    /// очередь всё равно разбирается на каждом запуске и входе.
    func testRetryBackoffGrowsAndStopsAtADay() {
        XCTAssertEqual(PlusAttachQueue.retryDelay(attempt: 1), 60, accuracy: 0.001)
        XCTAssertEqual(PlusAttachQueue.retryDelay(attempt: 2), 120, accuracy: 0.001)
        XCTAssertEqual(PlusAttachQueue.retryDelay(attempt: 5), 960, accuracy: 0.001)
        XCTAssertEqual(PlusAttachQueue.retryDelay(attempt: 40),
                       PlusAttachQueue.maxRetryDelay, accuracy: 0.001)
    }

    /// Сама подпись Apple в `UserDefaults` не лежит: она платёжный документ,
    /// а plist уезжает в незашифрованную резервную копию.
    func testTheSignatureItselfNeverTouchesUserDefaults() async {
        transport.fail(times: .max)
        let queue = makeQueue()
        queue.enqueue(key: "A", jws: "eyJhbGciOiJFUzI1NiJ9.PAYLOAD.SIG")
        await waitUntil { !self.transport.attempts.isEmpty }

        let plist = defaults.dictionaryRepresentation()
        let dumped = plist.values.map { "\($0)" }.joined(separator: " ")
        XCTAssertFalse(dumped.contains("eyJhbGciOiJFUzI1NiJ9.PAYLOAD.SIG"),
                       "подпись обязана лежать в Keychain, а не в plist")
        XCTAssertEqual(vault.read()["A"], "eyJhbGciOiJFUzI1NiJ9.PAYLOAD.SIG")
        _ = queue
    }

    // MARK: - Без аккаунта

    /// Без сессии привязывать покупку не к чему: сервер ведёт подписку по
    /// аккаунту. Заявка копится и уезжает на первом входе.
    func testWithoutASessionNothingIsSentAndNothingIsLost() async {
        let queue = makeQueue(signedIn: false)
        queue.enqueue(key: "A", jws: "jws-a")
        await queue.drain()
        await waitUntil(0.3) { false }

        XCTAssertTrue(transport.attempts.isEmpty)
        XCTAssertEqual(queue.pending.map(\.key), ["A"])
    }

    // MARK: - Провод

    /// Подпись уезжает на `/plus/attach` полем `signedTransaction` — так же,
    /// как её называет App Store Server API, по которой сервер её и проверяет.
    func testAttachPostsTheJWSToItsOwnRoute() async throws {
        MockURLProtocol.requestHandler = { req in
            let response = HTTPURLResponse(
                url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"status":"ok","payload":{"active":true,"until":"2027-10-12T00:00:00.000Z",\
            "productId":"\(PlusStore.yearlyID)","isTrial":true}}
            """
            return (response, Data(body.utf8))
        }
        let api = PlusAPI(client: APIClient(session: session, tokenStore: .shared))

        let answer = try await api.attach(signedTransaction: "eyJhbGciOi.PAYLOAD.SIG")

        XCTAssertTrue(answer.active)
        XCTAssertTrue(answer.isTrial)
        XCTAssertEqual(answer.productId, PlusStore.yearlyID)
        let sent = MockURLProtocol.recordedRequests
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.url?.path, "/plus/attach")
        XCTAssertEqual(sent.first?.httpMethod, "POST")
    }

    /// Старый сервер (Задача 1 ещё катится) поля `isTrial` не пришлёт — и это
    /// «не сказано», а не повод уронить привязку покупки.
    func testAShortAnswerStillDecodes() throws {
        let json = Data(#"{"active":true}"#.utf8)
        let answer = try JSONDecoder().decode(PlusStatusResponse.self, from: json)
        XCTAssertTrue(answer.active)
        XCTAssertFalse(answer.isTrial)
        XCTAssertNil(answer.until)
        XCTAssertNil(answer.productId)
    }
}
