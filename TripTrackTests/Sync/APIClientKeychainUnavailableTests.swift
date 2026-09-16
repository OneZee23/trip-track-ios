import XCTest
@testable import TripTrack

/// «Keychain не читается» — не «сессии нет», и решают это ДВА места:
/// `refreshIfNeeded` (первый вопрос) и петля восстановления, которую он
/// заводит (вопрос на каждом тике). Второе место ревью поймало на старом
/// двузначном `refreshToken != nil`: петля вставала насмерть ровно в том
/// сценарии, ради которого её и писали — фоновый запуск на телефоне, который
/// перезагрузили и не разблокировали.
///
/// Настоящий keychain симулятора всегда разблокирован, поэтому недоступность
/// подставляется через seam `KeychainHelper.ops`.
@MainActor
final class APIClientKeychainUnavailableTests: XCTestCase {

    private var session: URLSession!
    private var client: APIClient!
    private var savedOps: KeychainOps!
    private var deaths: Counter!
    private var recoveries: Counter!
    private var refreshPosts: Counter!

    override func setUp() async throws {
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        savedOps = KeychainHelper.ops
        TokenStore.shared.set(accessToken: "expired", refreshToken: "valid")
        client = APIClient(session: session, tokenStore: TokenStore.shared)
        deaths = Counter()
        recoveries = Counter()
        refreshPosts = Counter()
        client.sessionDeathHandler = { [deaths] in deaths?.incrementRefresh() }
        client.sessionRecoveryHandler = { [recoveries] in recoveries?.incrementRefresh() }
    }

    override func tearDown() async throws {
        KeychainHelper.ops = savedOps
        client?.sessionBoundaryCrossed()
        session?.invalidateAndCancel()
        MockURLProtocol.reset()
        TokenStore.shared.clear()
        // XCTest держит экземпляры теста до конца прогона — всё, что осталось
        // в полях, живёт до последнего теста набора.
        client = nil
        session = nil
        savedOps = nil
        deaths = nil
        recoveries = nil
        refreshPosts = nil
    }

    // MARK: - Helpers

    /// Keychain «заперт»: любое чтение отвечает `errSecInteractionNotAllowed`,
    /// как до первой разблокировки после перезагрузки.
    private func lockKeychain() {
        var locked = savedOps!
        locked.copy = { _, _ in (errSecInteractionNotAllowed, nil) }
        KeychainHelper.ops = locked
    }

    private func unlockKeychain() { KeychainHelper.ops = savedOps }

    /// Сервер: `/auth/refresh` считает вызовы и отдаёт новую пару, всё
    /// остальное отвечает «токен протух», что и запускает рефреш.
    private func installBackend(refreshThrows: Bool = false) {
        let posts = refreshPosts!
        MockURLProtocol.requestHandler = { req in
            if req.url!.path == "/auth/refresh" {
                posts.incrementRefresh()
                if refreshThrows { throw URLError(.timedOut) }
                let data = Data(#"{"status":"ok","payload":{"accessToken":"recovered","refreshToken":"recoveredRefresh"}}"#.utf8)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            let data = Data(#"{"status":"error","code":"USER_NOT_AUTH","message":"expired"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
    }

    private struct Payload: Codable { let v: Int }
    private struct Req: Codable { let x: Int }

    // MARK: - Тесты

    /// Первый вопрос: рефреш при запертом keychain НЕ объявляет сессию мёртвой
    /// и вообще не ходит на `/auth/refresh` — предъявить нечего.
    func testUnavailableKeychainDuringRefreshNeverKillsTheSession() async throws {
        installBackend()
        client.refreshRecoveryDelays = []
        lockKeychain()

        do {
            let _: Payload = try await client.post("/foo", body: Req(x: 1), requiresAuth: true)
            XCTFail("вызов обязан провалиться: авторизоваться нечем")
        } catch let error as APIError {
            guard case .transport = error else {
                return XCTFail("ожидался транзиент .transport, получено \(error)")
            }
        }

        XCTAssertEqual(deaths.refresh, 0, "недоступный keychain не имеет права убивать сессию")
        XCTAssertEqual(refreshPosts.refresh, 0, "рефреш без токена на сервер не уходит")
        unlockKeychain()
        XCTAssertEqual(TokenStore.shared.refreshToken, "valid", "токен на месте — его никто не трогал")
    }

    /// Вопрос на каждом тике: пока keychain заперт, петля ЖДЁТ, а не встаёт.
    /// Разблокировали — тот же самый заведённый цикл доводит восстановление
    /// до конца и один раз сообщает `sessionRecovered`.
    func testRecoveryLoopWaitsWhileKeychainIsLockedAndRecoversAfterUnlock() async throws {
        installBackend()
        client.refreshRecoveryDelays = [.milliseconds(80), .milliseconds(80), .milliseconds(80)]
        lockKeychain()

        do {
            let _: Payload = try await client.post("/foo", body: Req(x: 1), requiresAuth: true)
            XCTFail("вызов обязан провалиться")
        } catch { /* транзиент, петля заведена */ }

        // Первый тик проходит при запертом keychain — он не должен стать
        // последним.
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(refreshPosts.refresh, 0, "пока keychain заперт, слать нечего")
        XCTAssertEqual(deaths.refresh, 0)

        unlockKeychain()
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertGreaterThanOrEqual(refreshPosts.refresh, 1,
                                    "после разблокировки петля обязана довести рефреш")
        XCTAssertEqual(TokenStore.shared.accessToken, "recovered")
        XCTAssertEqual(recoveries.refresh, 1, "о восстановлении сообщается ровно один раз")
        XCTAssertEqual(deaths.refresh, 0)
    }

    /// А вот `.missing` — это настоящий ответ, и петля на нём заканчивается:
    /// ни одного лишнего похода на сервер и никакой смерти сессии (её объявил
    /// бы сам рефреш, если бы дошёл).
    func testMissingRefreshTokenEndsTheRecoveryLoop() async throws {
        installBackend(refreshThrows: true) // транзиент заводит петлю
        client.refreshRecoveryDelays = [.milliseconds(80), .milliseconds(80)]

        do {
            let _: Payload = try await client.post("/foo", body: Req(x: 1), requiresAuth: true)
            XCTFail("вызов обязан провалиться")
        } catch { /* транзиент, петля заведена */ }
        XCTAssertEqual(refreshPosts.refresh, 1, "сходил только сам рефреш")

        TokenStore.shared.clear() // токенов больше нет — ответ, а не незнание

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(refreshPosts.refresh, 1, "петля обязана встать на пустом keychain")
        XCTAssertEqual(deaths.refresh, 0, "петля выходит ДО рефреша, поэтому смерти не объявляет")
    }
}
