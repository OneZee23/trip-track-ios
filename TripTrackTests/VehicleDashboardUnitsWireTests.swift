import XCTest
import CoreData
@testable import TripTrack

/// Единица приборки машины — от выбора до второго телефона, по НАСТОЯЩЕМУ пути.
///
/// Почему этот тест написан целиком, а не проверкой по коду. Прецедент живой и
/// пролежал семь версий: `fuelCurrency` клиент кодировал в каждом апсерте
/// машины с 0.6.0, а на сервере не было ни колонки, ни ключа в DTO, ни поля в
/// сериализации — и `ValidationPipe` без `whitelist` выбрасывал лишний ключ
/// МОЛЧА, без ошибки и без строки в логе. Сборка зелёная, лог пустой, помашинная
/// валюта не переживает переустановку, и об этом никто не знает.
///
/// С единицей приборки та же потеря стоит не символа валюты, а ОДОМЕТРА:
/// приложение в милях разберёт введённые с километровой панели 142 000 как
/// 228 527 км, покажет при открытии те же 142 000 обратно — и ни разу себе не
/// противоречит. Наружу это вылезет через месяц как 86 тысяч фантомных
/// «недотреканных» километров.
///
/// Поэтому здесь пройден весь путь: выбрал → сохранилось → уехало в ПЕЙЛОАДЕ
/// (через настоящий `APISyncTransport` и настоящий `APIClient`, тело читается
/// с провода) → приехало пулом (через настоящий `PullApplier`) → показалось.
/// Ответ сервера в `pullJSON` — не выдумка. Тело, снятое здесь с провода,
/// было прогнано через НАСТОЯЩИЙ бэкенд — `plainToInstance` → `validate` →
/// `VehiclesService.mapDtoToEntity` → `VehiclesService.serializeVehicle`, — и
/// фикстура повторяет то, что вернула сериализация: ключ в ключ и в том же
/// порядке.
///
/// Хранилище ОБЩЕЕ, а не своё, и это вынужденно: `uploadVehicle` берёт машину
/// из `SettingsManager.shared`, а тот сидит на `PersistenceController.shared`
/// — подменить его нечем. Поэтому строки заводятся руками и руками убираются в
/// `tearDown`, как в `VehicleSyncConflictTests`.
@MainActor
final class VehicleDashboardUnitsWireTests: XCTestCase {

    private var repo: CoreDataTripRepository!
    private var transport: APISyncTransport!
    private var session: URLSession!
    private var insertedVehicleIds: [UUID] = []
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    /// Тело POST'а, снятое С ПРОВОДА. `nonisolated(unsafe)`, потому что
    /// обработчик `MockURLProtocol` зовётся с очереди сессии — ровно как сам
    /// `MockURLProtocol.requestHandler`.
    private nonisolated(unsafe) static var upsertBody: [String: Any]?

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        Self.upsertBody = nil
        repo = CoreDataTripRepository()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        let client = APIClient(session: session, tokenStore: TokenStore.shared)
        transport = APISyncTransport(client: client, photos: R2PhotoStorage.shared, repo: repo)
    }

    override func tearDown() async throws {
        let ctx = PersistenceController.shared.container.viewContext
        for id in insertedVehicleIds {
            let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? ctx.fetch(req).first { ctx.delete(entity) }
        }
        try? ctx.save()
        insertedVehicleIds = []
        SettingsManager.shared.reloadVehiclesForTesting()
        MockURLProtocol.reset()
        Self.upsertBody = nil
        session?.invalidateAndCancel()
        session = nil
        transport = nil
        repo = nil
        try await super.tearDown()
    }

    // MARK: - Мир на другом конце провода

    private func ok(_ payload: String) -> Data {
        Data(#"{"status":"ok","payload":\#(payload)}"#.utf8)
    }

    /// Отвечает по маршрутам и ЗАПОМИНАЕТ тело запроса. Тело у `URLProtocol`
    /// приезжает потоком, а не `httpBody`, — читается оба способа, потому что
    /// какой из них сработает, решает не наш код.
    private func serve(_ routes: [String: Data]) {
        MockURLProtocol.requestHandler = { req in
            let path = req.url?.path ?? ""
            if let data = Self.bodyData(of: req),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.upsertBody = json
            }
            let body = routes.first { path.hasSuffix($0.key) }?.value
                ?? Data(#"{"status":"error","code":"UNKNOWN","message":"\#(path)"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, body)
        }
    }

    private nonisolated static func bodyData(of req: URLRequest) -> Data? {
        if let body = req.httpBody { return body }
        guard let stream = req.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 16_384
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    // MARK: - Машина в общем хранилище

    @discardableResult
    private func localVehicle(name: String, odometerKm: Double = 100_000) -> UUID {
        let ctx = PersistenceController.shared.container.viewContext
        // `NSEntityDescription.insertNewObject`, а не `VehicleEntity(context:)`:
        // хранилище общее и дисковое, а соседние наборы к этому моменту уже
        // подняли и уронили свои модели — процессный кэш `+entity` показывает
        // на чужую, и сохранение падает несовместимостью версий.
        let entity = NSEntityDescription.insertNewObject(
            forEntityName: "VehicleEntity", into: ctx) as! VehicleEntity
        let id = UUID()
        entity.id = id
        entity.name = name
        entity.avatarEmoji = "🚗"
        entity.avatarStyle = VehicleAvatar.defaultStyle
        entity.vehicleType = VehicleType.car.rawValue
        entity.odometerKm = odometerKm
        entity.vehicleLevel = 1
        entity.visibleToOthers = true
        entity.plateVisible = false
        entity.mapVisible = true
        entity.photosVisible = true
        entity.isArchived = false
        entity.createdAt = t0
        entity.lastModifiedAt = t0
        entity.conflictVersion = 1
        entity.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
        insertedVehicleIds.append(id)
        SettingsManager.shared.reloadVehiclesForTesting()
        return id
    }

    /// «Правка уже уехала». Нужен тестам про пул: пока строка
    /// `pendingUpload`, приехавшая единица к ней не применяется — и это
    /// нарочно (см. `applyRemoteVehicle`), поэтому проверять на ней ответ
    /// сервера значило бы проверять не то.
    private func markSynced(_ id: UUID) {
        guard let e = entity(id) else { return }
        e.syncStatus = SyncStatus.synced.rawValue
        try? PersistenceController.shared.container.viewContext.save()
    }

    private func entity(_ id: UUID) -> VehicleEntity? {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? PersistenceController.shared.container.viewContext.fetch(req).first
    }

    private func vehicle(_ id: UUID) -> Vehicle? {
        SettingsManager.shared.vehicles.first { $0.id == id }
    }

    // MARK: - Пул

    /// Ответ `/sync/pull` целиком, с одной машиной внутри.
    ///
    /// `units` подставляется КАК ЕСТЬ, вместе с кавычками или без них: тесты
    /// ниже подставляют сюда и настоящее значение, и пропуск ключа (старый
    /// сервер), и мусор.
    private func pullJSON(id: UUID, unitsKey: String) -> String {
        """
        {"trips":{"upserted":[],"deleted":[]},
         "vehicles":{"upserted":[
           {"id":"\(id.uuidString)","name":"Тойота","avatarEmoji":"🚗",
            "odometerKm":100000,"manualOdometerKm":142000,"level":1,"stickersJson":null,
            "cityConsumption":9.1,"highwayConsumption":6.4,"fuelPrice":58,
            "fuelCurrency":"₽",\(unitsKey)
            "visibleToOthers":true,"avatarStyle":"pixel_car_silver",
            "vehicleType":"car","plate":"","plateVisible":false,
            "about":"","make":"","model":"","year":0,"bodyType":"",
            "mapVisible":true,"photosVisible":true,"isArchived":false,"soldAt":null,
            "conflictVersion":9,
            "lastModifiedAt":"\(ISODate.format(t0.addingTimeInterval(86_400)))"}
         ],"deleted":[]},
         "photos":{"upserted":[],"deleted":[]},
         "settings":null,"serverTime":"\(ISODate.format(t0))","ownedCounts":null,"journeys":null}
        """
    }

    /// Тот же разбор дат, что у боевого клиента: иначе тест проверял бы
    /// сериализацию, которой в приложении не существует.
    private func applyPull(_ json: String) throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = ISODate.parse(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: s))
            }
            return date
        }
        let response = try dec.decode(SyncPullResponse.self, from: Data(json.utf8))
        PullApplier().apply(response)
    }

    // MARK: - Дорога целиком

    /// Выбрал → сохранилось → уехало → приехало → показалось.
    func testTheChoiceTravelsTheWholeRoad() async throws {
        // 1. ВЫБРАЛ. Тойота с километровой панелью у человека, у которого всё
        //    приложение в милях.
        let id = localVehicle(name: "Тойота")
        SettingsManager.shared.setDashboardUnits(vehicleId: id, .metric)

        // 2. СОХРАНИЛОСЬ — и в базе, и в том, что читают экраны.
        XCTAssertEqual(entity(id)?.dashboardUnits, "metric", "выбор не доехал до базы")
        XCTAssertEqual(vehicle(id)?.dashboardUnits, .metric, "выбор не доехал до модели")
        XCTAssertEqual(entity(id)?.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "без pendingUpload первый же пул положит поверх серверное значение")

        // 3. УЕХАЛО В ПЕЙЛОАДЕ. Не «в структуре», а в теле POST'а на проводе.
        serve(["/vehicles/upsert": ok(#"{"id":"\#(id.uuidString)","conflictVersion":2}"#)])
        try await transport.execute(
            SyncOperation(entityType: .vehicle, entityId: id, action: .update))

        let body = try XCTUnwrap(Self.upsertBody, "тело апсерта не снялось с провода")
        XCTAssertEqual(body["dashboardUnits"] as? String, "metric",
                       "поле не уходит на сервер — оно не переживёт переустановку")

        // 4. ПРИЕХАЛО ПУЛОМ. Ответ — настоящий: см. доку класса.
        try applyPull(pullJSON(id: id, unitsKey: #""dashboardUnits":"imperial","#))
        XCTAssertEqual(entity(id)?.dashboardUnits, "imperial",
                       "приехавшее со второго телефона не применилось")
        let pulled = try XCTUnwrap(vehicle(id))
        XCTAssertEqual(pulled.dashboardUnits, .imperial)

        // 5. ПОКАЗАЛОСЬ. Единица машины сильнее единицы приложения — в обе
        //    стороны, потому что дыра владельца тоже двусторонняя: американец
        //    с километровой тойотой и русский с мильной американкой.
        XCTAssertEqual(pulled.dashboardUnit(app: .km), .miles,
                       "американка в РФ-гараже обязана остаться в милях")
        let toyota = Vehicle(name: "Тойота", dashboardUnits: .metric)
        XCTAssertEqual(toyota.dashboardUnit(app: .miles), .km,
                       "километровая панель у человека с милями — ровно тот случай, ради которого поле заведено")
    }

    /// То самое число из жалобы: 142 000 с километровой панели у человека,
    /// который выбрал мили. Разбор идёт по единице МАШИНЫ и обязан дать те же
    /// 142 000 километров, а не 228 527.
    func testTheNumberFromTheDashboardIsParsedInTheVehiclesUnit() {
        let toyota = Vehicle(name: "Тойота", dashboardUnits: .metric)
        let unit = toyota.dashboardUnit(app: .miles)

        let storedKm = unit.metres(fromDistance: 142_000) / 1000

        XCTAssertEqual(storedKm, 142_000, accuracy: 0.001,
                       "приложение в милях увезло километровую панель на 86 тысяч километров")
    }

    /// Молчание сервера — не ответ. Старый бэкенд ключа не шлёт, и локальный
    /// выбор обязан остаться: иначе каждый пул сбрасывал бы приборку в «как в
    /// приложении», причём тот же пул, который следует за собственным
    /// апсертом.
    func testAServerWithoutTheColumnDoesNotResetTheChoice() throws {
        let id = localVehicle(name: "Тойота")
        SettingsManager.shared.setDashboardUnits(vehicleId: id, .metric)
        markSynced(id)

        try applyPull(pullJSON(id: id, unitsKey: ""))

        XCTAssertEqual(entity(id)?.dashboardUnits, "metric")
        XCTAssertEqual(vehicle(id)?.dashboardUnits, .metric)
    }

    /// Значение, которого мы не знаем (клиент с четвёртой единицей — тот самый
    /// британский микс), — тоже не ответ. Подменить его на `app` значило бы
    /// молча перевести километровую панель в единицы приложения, то есть
    /// сделать ровно ту поломку, ради которой поле заведено.
    func testAnUnknownValueLeavesTheLocalChoiceAlone() throws {
        let id = localVehicle(name: "Тойота")
        SettingsManager.shared.setDashboardUnits(vehicleId: id, .metric)
        markSynced(id)

        try applyPull(pullJSON(id: id, unitsKey: #""dashboardUnits":"imperial_uk","#))

        XCTAssertEqual(entity(id)?.dashboardUnits, "metric",
                       "«не знаю» обязано означать «не трогаю»")
    }

    /// И весь остальной ответ при этом применяется: незнакомое значение одного
    /// поля не имеет права уронить разбор машины целиком.
    func testAnUnknownValueDoesNotBreakTheRestOfTheVehicle() throws {
        let id = localVehicle(name: "Тойота")

        // Число вместо строки — чужой ТИП, а не просто чужое значение. Разбор
        // обязан отбросить поле, а не уронить ответ пула целиком: человек
        // остался бы без поездок и снимков из-за подсказки для показа.
        try applyPull(pullJSON(id: id, unitsKey: #""dashboardUnits":42,"#))

        XCTAssertEqual(entity(id)?.conflictVersion, 9, "машина не применилась вовсе")
        XCTAssertEqual(entity(id)?.manualOdometerKm?.doubleValue, 142_000)
    }

    /// Правка, которая ещё не уехала, сильнее приехавшего ответа.
    ///
    /// Пятая ось к четырём осям видимости, и по причине сильнее их: человек
    /// выбирает «километры» в самолёте, полный пул обгоняет очередь и
    /// возвращает `app` — поле ввода снова разбирает мили, и списанные с
    /// панели 142 000 уезжают в базу как 228 527. Вернувшееся имя машины —
    /// досада, вернувшаяся единица приборки — неверное число в базе.
    func testAChoiceThatHasNotLeftYetSurvivesAPull() throws {
        let id = localVehicle(name: "Тойота")
        SettingsManager.shared.setDashboardUnits(vehicleId: id, .metric)
        XCTAssertEqual(entity(id)?.syncStatus, SyncStatus.pendingUpload.rawValue)

        try applyPull(pullJSON(id: id, unitsKey: #""dashboardUnits":"app","#))

        XCTAssertEqual(entity(id)?.dashboardUnits, "metric",
                       "пул обогнал очередь и отменил выбор человека")
    }

    /// Машина, заведённая до 0.6.7, — «как в приложении», и это не заглушка, а
    /// единственное умолчание, при котором версия физически не может никому
    /// сменить показания: у такой машины ответа на вопрос «что у неё на
    /// панели» просто нет.
    func testAVehicleFromBeforeThisVersionFollowsTheApp() {
        let id = localVehicle(name: "Старая")

        let old = SettingsManager.shared.vehicles.first { $0.id == id }

        XCTAssertEqual(old?.dashboardUnits, .app)
        XCTAssertEqual(old?.dashboardUnit(app: .miles), .miles)
        XCTAssertEqual(old?.dashboardUnit(app: .km), .km)
    }
}
