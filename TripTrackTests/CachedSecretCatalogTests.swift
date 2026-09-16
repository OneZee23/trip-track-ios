import XCTest
@testable import TripTrack

/// Каталог секретов: версия, кэш, офлайн и бандл за спиной.
///
/// Проверяется не «разбирается ли JSON», а четыре решения, каждое из которых
/// ломается молча: спросили ли сервер с прошлой версией, пережил ли список
/// отсутствие сети, не подменил ли пустой ответ рабочий каталог и та ли соль
/// уехала вместе со списком (чужая соль — это «не найдено ничего и никогда»,
/// без единой ошибки).
final class CachedSecretCatalogTests: XCTestCase {

    /// Транспорт-протокол, а не `MockURLProtocol`: предмет проверки здесь —
    /// решение, а не провод. Провод проверяется отдельно, последним тестом.
    private final class FakeTransport: SecretsTransport, @unchecked Sendable {
        let lock = NSLock()
        var replies: [Result<SecretCatalogResponse, Error>] = []
        private(set) var askedVersions: [String?] = []

        func catalog(version: String?) async throws -> SecretCatalogResponse {
            lock.lock()
            askedVersions.append(version)
            let reply = replies.isEmpty ? nil : replies.removeFirst()
            lock.unlock()
            guard let reply else { throw URLError(.notConnectedToInternet) }
            return try reply.get()
        }

        func reveal(_ body: SecretRevealRequest) async throws -> SecretRevealResponse {
            throw URLError(.unsupportedURL)
        }

        var asked: [String?] {
            lock.lock(); defer { lock.unlock() }
            return askedVersions
        }
    }

    /// Бандл за спиной — свой, а не настоящий: в дереве `Secrets.json` пуст, и
    /// «упало на бандл» было бы неотличимо от «каталога нет вовсе».
    private struct StubBundle: SecretCatalog {
        let salt = "bundle-salt"
        func all() -> [SecretRecord] {
            [SecretRecord(id: "bundled", hashes: [1], reach: 250, symbol: .generic, polygon: false)]
        }
    }

    private var transport: FakeTransport!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var fileURL: URL!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() {
        super.setUp()
        transport = FakeTransport()
        suiteName = "CachedSecretCatalogTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-tests-\(UUID().uuidString)")
            .appendingPathComponent("catalog.json")
    }

    /// Каждое поле обнуляется, файл и своя сюита стираются: XCTest держит
    /// экземпляры до конца прогона, и оставленный `UserDefaults` пережил бы
    /// весь набор.
    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        transport = nil
        fileURL = nil
        super.tearDown()
    }

    // MARK: - Фикстуры

    private func make() -> CachedSecretCatalog {
        CachedSecretCatalog(transport: transport, fallback: StubBundle(),
                            defaults: defaults, fileURL: fileURL)
    }

    private func full(_ version: String, salt: String, ids: [String]) throws -> SecretCatalogResponse {
        let secrets = ids.map {
            #"{"id":"\#($0)","hashes":[2566105652],"reach":250,"symbol":"compass","polygon":false}"#
        }.joined(separator: ",")
        return try decode(
            #"{"version":"\#(version)","salt":"\#(salt)","secrets":[\#(secrets)]}"#)
    }

    private func decode(_ json: String) throws -> SecretCatalogResponse {
        try JSONDecoder().decode(SecretCatalogResponse.self, from: Data(json.utf8))
    }

    // MARK: - Версия и кэш

    func testFirstRefreshAsksWithoutVersionAndServesTheServerList() async throws {
        transport.replies = [.success(try full("v1", salt: "server-salt", ids: ["a", "b"]))]
        let catalog = make()

        let asked = await catalog.refreshIfNeeded(now: t0)

        XCTAssertTrue(asked)
        XCTAssertEqual(transport.asked, [nil])
        XCTAssertEqual(catalog.all().map(\.id), ["a", "b"])
        XCTAssertEqual(catalog.salt, "server-salt")
        XCTAssertEqual(catalog.version, "v1")
    }

    /// Вторая сборка того же телефона читает файл — и спрашивает сервер уже
    /// СО СВОЕЙ версией. Без этого каждый запуск качал бы список целиком.
    func testKnownVersionTravelsWithTheNextRequest() async throws {
        transport.replies = [.success(try full("v1", salt: "server-salt", ids: ["a"]))]
        await make().refreshIfNeeded(now: t0)

        transport.replies = [.success(try decode(#"{"version":"v1","unchanged":true}"#))]
        let second = make()
        XCTAssertEqual(second.version, "v1", "кэш не прочитался с диска")
        await second.refresh(now: t0.addingTimeInterval(86_401))

        XCTAssertEqual(transport.asked, [nil, "v1"])
        XCTAssertEqual(second.all().map(\.id), ["a"], "«unchanged» не имеет права стереть список")
        XCTAssertEqual(second.salt, "server-salt")
    }

    /// Раз в сутки — это про ЗАПРОС, а не про изменение списка.
    func testSecondLaunchWithinADayAsksNothing() async throws {
        transport.replies = [.success(try full("v1", salt: "s", ids: ["a"]))]
        let catalog = make()
        await catalog.refreshIfNeeded(now: t0)

        let again = await catalog.refreshIfNeeded(now: t0.addingTimeInterval(3_600))
        XCTAssertFalse(again)
        XCTAssertEqual(transport.asked.count, 1)

        let tomorrow = await catalog.refreshIfNeeded(now: t0.addingTimeInterval(86_401))
        XCTAssertTrue(tomorrow)
        XCTAssertEqual(transport.asked.count, 2)
    }

    // MARK: - Офлайн

    /// Сети нет — остаётся список с прошлого раза, и дата обращения НЕ
    /// двигается: следующий запуск обязан попробовать снова, а не ждать сутки
    /// после ошибки.
    func testOfflineKeepsTheCacheAndRetriesNextLaunch() async throws {
        transport.replies = [.success(try full("v1", salt: "server-salt", ids: ["a"]))]
        let catalog = make()
        await catalog.refreshIfNeeded(now: t0)

        transport.replies = [.failure(URLError(.notConnectedToInternet))]
        await catalog.refresh(now: t0.addingTimeInterval(86_401))

        XCTAssertEqual(catalog.all().map(\.id), ["a"])
        XCTAssertEqual(catalog.salt, "server-salt")
        let stamp = try XCTUnwrap(defaults.object(forKey: CachedSecretCatalog.refreshedAtKey) as? Date)
        XCTAssertEqual(stamp, t0, "неудачная попытка сдвинула дату — сутки молчания после ошибки")
    }

    /// Первый запуск в самолёте: кэша нет, сети нет — работает бандл, а не
    /// пустота. Пустой каталог означал бы «ни одного секрета не найти».
    func testEmptyCacheFallsBackToTheBundle() async {
        let catalog = make()
        await catalog.refreshIfNeeded(now: t0)

        XCTAssertEqual(catalog.all().map(\.id), ["bundled"])
        XCTAssertEqual(catalog.salt, "bundle-salt")
        XCTAssertNil(catalog.version)
    }

    /// Пустой список с сервера — это «волна секретов ещё не наполнена», и он
    /// не имеет права вытеснить бандл: соль с ним при этом тоже бандловая.
    func testEmptyServerListDoesNotDisplaceTheBundle() async throws {
        transport.replies = [.success(try full("v1", salt: "server-salt", ids: []))]
        let catalog = make()
        await catalog.refreshIfNeeded(now: t0)

        XCTAssertEqual(catalog.all().map(\.id), ["bundled"])
        XCTAssertEqual(catalog.salt, "bundle-salt")
        XCTAssertEqual(catalog.version, "v1", "версия запомнена — качать тот же пустой список незачем")
    }

    // MARK: - Стирание

    func testWipeForgetsFileAndStamp() async throws {
        transport.replies = [.success(try full("v1", salt: "server-salt", ids: ["a"]))]
        let catalog = make()
        await catalog.refreshIfNeeded(now: t0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        catalog.wipe()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(defaults.object(forKey: CachedSecretCatalog.refreshedAtKey))
        XCTAssertNil(catalog.version)
        XCTAssertEqual(catalog.all().map(\.id), ["bundled"])
    }

    // MARK: - Провод

    /// Тот же путь, каким каталог поедет в проде: настоящий `APIClient`,
    /// настоящий конверт `{status, payload}` и ответ, списанный с отчёта
    /// бэкенда волны 3. Заодно — символ, которого эта сборка не знает: он
    /// обязан стать `generic`, а не уронить весь каталог.
    @MainActor
    func testWireAnswerParsesThroughTheRealClient() async throws {
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        defer {
            MockURLProtocol.reset()
            session.invalidateAndCancel()
        }
        MockURLProtocol.requestHandler = { req in
            let body = """
                {"status":"ok","payload":{
                  "version":"5f2c9f8a","salt":"tt-secrets-v1",
                  "secrets":[
                    {"id":"komsomolsky","hashes":[2566105652],"reach":250,
                     "symbol":"compass","polygon":false},
                    {"id":"engraved","hashes":[1,2],"reach":0,
                     "symbol":"engraving.wave5","polygon":true}
                  ]}}
                """
            let response = HTTPURLResponse(
                url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        let catalog = CachedSecretCatalog(
            transport: SecretsAPI(client: APIClient(session: session, tokenStore: .shared)),
            fallback: StubBundle(), defaults: defaults, fileURL: fileURL)
        await catalog.refresh(now: t0)

        XCTAssertEqual(catalog.version, "5f2c9f8a")
        XCTAssertEqual(catalog.salt, "tt-secrets-v1")
        XCTAssertEqual(catalog.all().map(\.id), ["komsomolsky", "engraved"])
        XCTAssertEqual(catalog.all().first?.hashes, [2_566_105_652])
        XCTAssertEqual(catalog.all().last?.symbol, .generic, "незнакомый символ уронил каталог")
        XCTAssertEqual(catalog.all().last?.polygon, true)
        let path = MockURLProtocol.recordedRequests.last?.url?.path
        XCTAssertEqual(path, "/secrets/catalog")
    }
}
