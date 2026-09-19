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

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var transport: StubTransport!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        suiteName = "plus.attach.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
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
        suiteName = nil
        transport = nil
        MockURLProtocol.reset()
        // Незакрытая `URLSession` держит очередь и `MockURLProtocol` до конца
        // прогона — и роняет ЧУЖОЙ класс (см. «Ловушки» в CLAUDE.md).
        session?.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    private func makeQueue(signedIn: Bool = true) -> PlusAttachQueue {
        PlusAttachQueue(
            transport: transport,
            isAllowed: { signedIn },
            defaults: defaults,
            backoff: { _ in }   // откат мгновенный: предмет проверки — счёт попыток
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
        let second = makeQueue()
        XCTAssertEqual(second.pending.map(\.key), ["A"])
        await second.drain()
        await waitUntil { second.pending.isEmpty }
        XCTAssertEqual(second.sent, ["A"])
    }

    // MARK: - Постоянный отказ

    /// Транзакция чужого аккаунта — ответ навсегда. Повторять её пять раз
    /// значит пять раз получить то же самое.
    func testPermanentRejectionIsDroppedAfterOneAttempt() async {
        transport.fail(times: .max, with: APIError.unknownServer(
            code: "PLUS_BELONGS_TO_ANOTHER", message: ""))
        let queue = makeQueue()
        queue.enqueue(key: "A", jws: "jws-a")
        await queue.drain()

        await waitUntil { queue.pending.isEmpty }
        XCTAssertEqual(transport.attempts.count, 1)
        XCTAssertTrue(queue.pending.isEmpty, "постоянный отказ не копится в очереди")
    }

    func testPermanenceRule() {
        XCTAssertTrue(PlusAttachQueue.isPermanent(APIError.validationFailed("")))
        XCTAssertTrue(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(404)))
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(429)),
                       "троттлинг — это «попробуй позже»")
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(408)))
        XCTAssertFalse(PlusAttachQueue.isPermanent(APIError.invalidHTTPStatus(503)))
        XCTAssertFalse(PlusAttachQueue.isPermanent(URLError(.notConnectedToInternet)))
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
