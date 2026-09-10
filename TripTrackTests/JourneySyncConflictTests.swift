import XCTest
import CoreData
@testable import TripTrack

/// Конфликт не имеет права запереть путешествие.
///
/// Дверей две, и до 0.6.6 обе стояли закрытыми одновременно: `uploadJourney`
/// глотал `CONFLICT_DETECTED`, не снимая `pendingUpload`, а `applyRemoteJourney`
/// на `pendingUpload` выходил, ничего не применив. Запись переставала уезжать и
/// переставала обновляться — два телефона расходились молча и навсегда, и
/// человеку это показать негде.
///
/// Здесь проверяется именно выход из угла: после конфликта запись больше не
/// `pendingUpload` И несёт серверные поля. И симметричный угол у удаления:
/// `pendingDelete` с записью, которой на сервере уже (или ещё) нет.
@MainActor
final class JourneySyncConflictTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var transport: APISyncTransport!
    private var session: URLSession!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        let client = APIClient(session: session, tokenStore: TokenStore.shared)
        transport = APISyncTransport(client: client, photos: R2PhotoStorage.shared, repo: repo)
    }

    /// Отпускать здесь ОБЯЗАТЕЛЬНО, и это не вежливость.
    ///
    /// XCTest держит все свои экземпляры до конца прогона, поэтому каждое поле,
    /// оставленное непустым, живёт до последнего теста в наборе. Хранилище в
    /// памяти тянет за собой свою `NSManagedObjectModel` (в логе это «Multiple
    /// NSEntityDescriptions claim TripEntity»), а `URLSession` без
    /// `invalidateAndCancel` не отпускает ни свою очередь, ни `MockURLProtocol`.
    /// Шесть таких хвостов на набор из девятисот тестов роняли раннер целиком —
    /// причём в чужом классе и каждый раз в другом месте, так что по симптому
    /// виновника не найти.
    override func tearDown() async throws {
        MockURLProtocol.reset()
        session?.invalidateAndCancel()
        session = nil
        transport = nil
        repo = nil
        pc = nil
        try await super.tearDown()
    }

    // MARK: Мир на другом конце провода

    private func ok(_ payload: String) -> Data {
        Data(#"{"status":"ok","payload":\#(payload)}"#.utf8)
    }

    private func error(_ code: String, extra: String = "") -> Data {
        Data(#"{"status":"error","code":"\#(code)","message":"x"\#(extra)}"#.utf8)
    }

    private func serverJourney(id: UUID, title: String, version: Int) -> String {
        """
        {"id":"\(id.uuidString)","title":"\(title)",\
        "startDate":"\(ISODate.format(t0))",\
        "endDate":"\(ISODate.format(t0.addingTimeInterval(5 * 86_400)))",\
        "excludedTripIds":[],"coverPhotoId":null,"isPrivate":true,\
        "conflictVersion":\(version),\
        "lastModifiedAt":"\(ISODate.format(t0.addingTimeInterval(86_400)))",\
        "serverCreatedAt":"\(ISODate.format(t0))"}
        """
    }

    /// Отвечает по маршрутам, а не по порядку вызовов: путь в тесте виден так
    /// же, как на проводе, и перестановка запросов его не ломает.
    private func serve(_ routes: [String: Data]) {
        MockURLProtocol.requestHandler = { req in
            let path = req.url?.path ?? ""
            let body = routes.first { path.hasSuffix($0.key) }?.value
                ?? Data(#"{"status":"error","code":"UNKNOWN","message":"\#(path)"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    private func localJourney(title: String) -> Journey {
        repo.saveJourney(Journey(title: title, startDate: t0, endDate: t0.addingTimeInterval(2 * 86_400)))
    }

    private func upload(_ id: UUID) async throws {
        try await transport.execute(SyncOperation(entityType: .journey, entityId: id, action: .update))
    }

    // MARK: Загрузка

    /// Главное: конфликт РАЗРЕШАЕТСЯ, а не откладывается. Побеждает сервер —
    /// имя и окно приезжают с него, локальная правка теряется осознанно.
    func testConflictAdoptsServerVersionAndUnlocksTheRow() async throws {
        let local = localJourney(title: "Местное имя")
        XCTAssertEqual(repo.journeySyncStatus(id: local.id), SyncStatus.pendingUpload.rawValue)

        serve([
            "/journeys/upsert": error("CONFLICT_DETECTED", extra: #","serverVersion":7"#),
            "/journeys/list": ok(#"{"journeys":[\#(serverJourney(id: local.id, title: "Серверное имя", version: 7))]}"#),
        ])

        try await upload(local.id)

        XCTAssertEqual(repo.journeySyncStatus(id: local.id), SyncStatus.synced.rawValue,
                       "после конфликта запись обязана перестать быть pendingUpload")
        let after = try XCTUnwrap(repo.fetchJourney(id: local.id))
        XCTAssertEqual(after.title, "Серверное имя", "побеждает сервер")
        XCTAssertEqual(after.conflictVersion, 7)
        XCTAssertEqual(after.endDate, t0.addingTimeInterval(5 * 86_400), "окно тоже серверное")
    }

    /// Тот же конфликт, но серверной строки в ответе нет: её удалили с другого
    /// телефона. Удаление по молчанию не выдумываем — локальное остаётся как
    /// было, и это решение, а не забытая ветка.
    func testConflictWithoutServerRowLeavesTheLocalOneAlone() async throws {
        let local = localJourney(title: "Местное имя")

        serve([
            "/journeys/upsert": error("CONFLICT_DETECTED"),
            "/journeys/list": ok(#"{"journeys":[]}"#),
        ])

        try await upload(local.id)

        XCTAssertEqual(repo.fetchJourney(id: local.id)?.title, "Местное имя")
        XCTAssertEqual(repo.journeySyncStatus(id: local.id), SyncStatus.pendingUpload.rawValue)
    }

    /// Обычная отправка не изменилась: сервер принял — запись `synced` с его
    /// версией, и никакого второго запроса.
    func testAcceptedUploadStillMarksSynced() async throws {
        let local = localJourney(title: "Местное имя")
        serve(["/journeys/upsert": ok(#"{"id":"\#(local.id.uuidString)","conflictVersion":3}"#)])

        try await upload(local.id)

        XCTAssertEqual(repo.journeySyncStatus(id: local.id), SyncStatus.synced.rawValue)
        XCTAssertEqual(repo.fetchJourney(id: local.id)?.conflictVersion, 3)
        XCTAssertEqual(repo.fetchJourney(id: local.id)?.title, "Местное имя")
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1, "за списком ходить незачем")
    }

    /// Ошибку, которая не конфликт, глотать нельзя: операция должна упасть и
    /// повториться.
    func testOtherServerErrorStillThrows() async {
        let local = localJourney(title: "Местное имя")
        serve(["/journeys/upsert": error("TOO_MANY_REQUESTS")])

        do {
            try await upload(local.id)
            XCTFail("ожидали проброс ошибки")
        } catch {
            XCTAssertEqual(repo.journeySyncStatus(id: local.id), SyncStatus.pendingUpload.rawValue)
        }
    }

    // MARK: Удаление

    /// Симметричный угол: сервер записи не знает (её туда не довезли или уже
    /// удалили с другого телефона). Раньше 404 роняла операцию, строка вечно
    /// висела `pendingDelete` — спрятанная из «Моих», но бессмертная.
    func testDeleteOfAJourneyTheServerDoesNotKnowFinishesLocally() async throws {
        let local = localJourney(title: "В самолёте")
        repo.markJourneyDeleted(id: local.id)
        XCTAssertEqual(repo.journeySyncStatus(id: local.id), SyncStatus.pendingDelete.rawValue)

        serve(["/journeys/delete": error("JOURNEY_NOT_FOUND")])

        try await transport.execute(SyncOperation(entityType: .journey, entityId: local.id, action: .delete))

        XCTAssertNil(repo.fetchJourney(id: local.id), "строка обязана уйти совсем")
        XCTAssertNil(repo.journeySyncStatus(id: local.id))
    }

    func testAcceptedDeleteRemovesTheRow() async throws {
        let local = localJourney(title: "Юг")
        repo.markJourneyDeleted(id: local.id)
        serve(["/journeys/delete": ok("{}")])

        try await transport.execute(SyncOperation(entityType: .journey, entityId: local.id, action: .delete))

        XCTAssertNil(repo.journeySyncStatus(id: local.id))
    }
}
