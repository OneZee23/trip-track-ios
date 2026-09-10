import XCTest
import CoreData
@testable import TripTrack

/// Конфликт не имеет права запереть машину.
///
/// Тот же угол, что у путешествия, и обе двери стояли закрытыми одновременно:
/// `uploadVehicle` глотал `CONFLICT_DETECTED`, оставляя `pendingUpload`, а
/// `applyRemoteVehicle` при местной правке не применял серверную видимость.
/// Машина переставала уезжать и переставала обновляться — два телефона
/// расходились молча и навсегда, и человеку это показать негде.
///
/// Здесь проверяется именно выход из угла: после конфликта запись больше не
/// `pendingUpload` И несёт серверные поля, включая ту самую видимость — она
/// применится только если флаг сняли ДО применения. И симметричный угол у
/// удаления: машина, которой на сервере уже (или ещё) нет.
///
/// Хранилище тут ОБЩЕЕ, а не своё: `uploadVehicle` берёт машину из
/// `SettingsManager.shared`, а тот сидит на `PersistenceController.shared` —
/// подменить его нечем, как и в `CompanionsCacheSignOutTests`. Поэтому строка
/// заводится руками и руками же убирается в `tearDown`.
@MainActor
final class VehicleSyncConflictTests: XCTestCase {
    private var repo: CoreDataTripRepository!
    private var transport: APISyncTransport!
    private var session: URLSession!
    private var insertedVehicleIds: [UUID] = []
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        repo = CoreDataTripRepository()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        let client = APIClient(session: session, tokenStore: TokenStore.shared)
        transport = APISyncTransport(client: client, photos: R2PhotoStorage.shared, repo: repo)
    }

    /// Отпускать здесь ОБЯЗАТЕЛЬНО, и это не вежливость.
    ///
    /// XCTest держит все свои экземпляры до конца прогона, поэтому каждое поле,
    /// оставленное непустым, живёт до последнего теста в наборе, а `URLSession`
    /// без `invalidateAndCancel` не отпускает ни свою очередь, ни
    /// `MockURLProtocol`. Такие хвосты роняли раннер целиком — причём в чужом
    /// классе и каждый раз в другом месте, так что по симптому виновника не
    /// найти. Плюс здесь же уходят строки из ОБЩЕГО хранилища: оно на диске и
    /// переживает не только тест, но и весь прогон.
    override func tearDown() async throws {
        let ctx = PersistenceController.shared.container.viewContext
        for id in insertedVehicleIds {
            let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? ctx.fetch(req).first {
                ctx.delete(entity)
            }
        }
        try? ctx.save()
        insertedVehicleIds = []
        SettingsManager.shared.reloadVehiclesForTesting()
        MockURLProtocol.reset()
        session?.invalidateAndCancel()
        session = nil
        transport = nil
        repo = nil
        try await super.tearDown()
    }

    // MARK: Мир на другом конце провода

    private func ok(_ payload: String) -> Data {
        Data(#"{"status":"ok","payload":\#(payload)}"#.utf8)
    }

    private func error(_ code: String, extra: String = "") -> Data {
        Data(#"{"status":"error","code":"\#(code)","message":"x"\#(extra)}"#.utf8)
    }

    private func serverVehicle(id: UUID, name: String, version: Int,
                               visibleToOthers: Bool) -> String {
        """
        {"id":"\(id.uuidString)","name":"\(name)","avatarEmoji":"🚙",\
        "odometerKm":12345,"manualOdometerKm":null,"level":3,"stickersJson":null,\
        "cityConsumption":9.1,"highwayConsumption":6.4,"fuelPrice":58,\
        "visibleToOthers":\(visibleToOthers),"avatarStyle":"pixel_car_silver",\
        "vehicleType":"car","plate":"A001AA","plateVisible":false,\
        "about":"","make":"","model":"","year":0,"bodyType":"",\
        "mapVisible":true,"photosVisible":true,"isArchived":false,"soldAt":null,\
        "conflictVersion":\(version),\
        "lastModifiedAt":"\(ISODate.format(t0.addingTimeInterval(86_400)))"}
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

    /// `NSEntityDescription.insertNewObject(forEntityName:into:)`, а не
    /// `VehicleEntity(context:)`: хранилище тут общее и дисковое, а другие
    /// наборы к этому моменту уже подняли и уронили свои `NSManagedObjectModel`,
    /// из-за чего процессный кэш `+entity` показывает на чужую модель — и
    /// сохранение падает с `NSPersistentStoreIncompatibleVersionHashError`.
    @discardableResult
    private func localVehicle(name: String, visibleToOthers: Bool = true,
                              conflictVersion: Int32 = 3,
                              syncStatus: SyncStatus = .pendingUpload) -> UUID {
        let ctx = PersistenceController.shared.container.viewContext
        let entity = NSEntityDescription.insertNewObject(
            forEntityName: "VehicleEntity", into: ctx) as! VehicleEntity
        let id = UUID()
        entity.id = id
        entity.name = name
        entity.avatarEmoji = "🚗"
        entity.avatarStyle = VehicleAvatar.defaultStyle
        entity.vehicleType = VehicleType.car.rawValue
        entity.odometerKm = 1_000
        entity.vehicleLevel = 1
        entity.visibleToOthers = visibleToOthers
        entity.plateVisible = false
        entity.mapVisible = true
        entity.photosVisible = true
        entity.isArchived = false
        entity.createdAt = t0
        entity.lastModifiedAt = t0
        entity.conflictVersion = conflictVersion
        entity.syncStatus = syncStatus.rawValue
        try? ctx.save()
        insertedVehicleIds.append(id)
        // Без этого `uploadVehicle` не найдёт машину в гараже и выйдет на
        // первом же `guard`, не сходив никуда.
        SettingsManager.shared.reloadVehiclesForTesting()
        return id
    }

    private func entity(_ id: UUID) -> VehicleEntity? {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? PersistenceController.shared.container.viewContext.fetch(req).first
    }

    private func upload(_ id: UUID) async throws {
        try await transport.execute(SyncOperation(entityType: .vehicle, entityId: id, action: .update))
    }

    // MARK: Загрузка

    /// Главное: конфликт РАЗРЕШАЕТСЯ, а не откладывается. Побеждает сервер —
    /// имя и видимость приезжают с него, локальная правка теряется осознанно.
    ///
    /// Видимость здесь — проверка ПОРЯДКА, а не ещё одно поле: её
    /// `applyRemoteVehicle` применяет только когда местной правки уже нет,
    /// то есть только если `pendingUpload` сняли ДО применения.
    func testConflictAdoptsServerVersionAndUnlocksTheRow() async throws {
        let id = localVehicle(name: "Местное имя", visibleToOthers: true)
        XCTAssertEqual(entity(id)?.syncStatus, SyncStatus.pendingUpload.rawValue)

        serve([
            "/vehicles/upsert": error("CONFLICT_DETECTED", extra: #","serverVersion":7"#),
            "/vehicles/list": ok(#"{"vehicles":[\#(serverVehicle(id: id, name: "Серверное имя", version: 7, visibleToOthers: false))]}"#),
        ])

        try await upload(id)

        let after = try XCTUnwrap(entity(id))
        XCTAssertEqual(after.syncStatus, SyncStatus.synced.rawValue,
                       "после конфликта запись обязана перестать быть pendingUpload")
        XCTAssertEqual(after.name, "Серверное имя", "побеждает сервер")
        XCTAssertEqual(after.conflictVersion, 7)
        XCTAssertEqual(after.odometerKm, 12_345, "пробег тоже серверный")
        XCTAssertFalse(after.visibleToOthers,
                       "видимость применяется, только если флаг сняли ДО применения")
    }

    /// Тот же конфликт, но серверной строки в ответе нет: её удалили с другого
    /// телефона. Удаление по молчанию не выдумываем — локальное остаётся как
    /// было, и это решение, а не забытая ветка.
    func testConflictWithoutServerRowLeavesTheLocalOneAlone() async throws {
        let id = localVehicle(name: "Местное имя")

        serve([
            "/vehicles/upsert": error("CONFLICT_DETECTED"),
            "/vehicles/list": ok(#"{"vehicles":[]}"#),
        ])

        try await upload(id)

        XCTAssertEqual(entity(id)?.name, "Местное имя")
        XCTAssertEqual(entity(id)?.syncStatus, SyncStatus.pendingUpload.rawValue)
    }

    /// Обычная отправка не изменилась: сервер принял — запись `synced` с его
    /// версией, и никакого второго запроса.
    func testAcceptedUploadStillMarksSynced() async throws {
        let id = localVehicle(name: "Местное имя")
        serve(["/vehicles/upsert": ok(#"{"id":"\#(id.uuidString)","conflictVersion":4}"#)])

        try await upload(id)

        XCTAssertEqual(entity(id)?.syncStatus, SyncStatus.synced.rawValue)
        XCTAssertEqual(entity(id)?.conflictVersion, 4)
        XCTAssertEqual(entity(id)?.name, "Местное имя")
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1, "за гаражом ходить незачем")
    }

    /// Ошибку, которая не конфликт, глотать нельзя: операция должна упасть и
    /// повториться.
    func testOtherServerErrorStillThrows() async {
        let id = localVehicle(name: "Местное имя")
        serve(["/vehicles/upsert": error("TOO_MANY_REQUESTS")])

        do {
            try await upload(id)
            XCTFail("ожидали проброс ошибки")
        } catch {
            XCTAssertEqual(entity(id)?.syncStatus, SyncStatus.pendingUpload.rawValue)
        }
    }

    // MARK: Удаление

    /// Симметричный угол: сервер машины не знает (её туда не довезли или уже
    /// удалили с другого телефона). Раньше 404 роняла операцию, и она вечно
    /// возвращалась в очередь на каждом запуске.
    func testDeleteOfAVehicleTheServerDoesNotKnowFinishesLocally() async throws {
        let id = localVehicle(name: "В самолёте", syncStatus: .pendingDelete)

        serve(["/vehicles/delete": error("VEHICLE_NOT_FOUND")])

        try await transport.execute(SyncOperation(entityType: .vehicle, entityId: id, action: .delete))

        XCTAssertNil(entity(id), "строка обязана уйти совсем")
    }

    func testAcceptedDeleteRemovesTheRow() async throws {
        let id = localVehicle(name: "Проданная", syncStatus: .pendingDelete)
        serve(["/vehicles/delete": ok("{}")])

        try await transport.execute(SyncOperation(entityType: .vehicle, entityId: id, action: .delete))

        XCTAssertNil(entity(id))
    }
}
