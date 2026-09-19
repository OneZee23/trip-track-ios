import XCTest
import CoreData
@testable import TripTrack

/// Источник поездки — записана треком или вписана рукой (0.8.0, «Плюс»).
///
/// Тип называется `TripOrigin`, не `TripSource`: то имя уже занято
/// `Services/TripSource.swift`, протоколом «откуда для экрана читать список
/// поездок» (свои / чужие / машины) — понятием из другой оси. Имя ПОЛЯ на
/// проводе и в базе при этом ровно то, что просит спека: `Trip.source`,
/// `TripEntity.source`, `TripSyncPayload.source`.
///
/// Класс называется `TripOriginTests`, а не `TripSourceTests` — то имя занято
/// существующим сьютом про `RemoteTripSource`/пагинацию чужой карты
/// (`TripSourceTests.swift`), с которым у этого типа нет ничего общего.
final class TripOriginTests: XCTestCase {

    // MARK: - Разбор

    /// Незнакомая строка — будущий третий источник, о котором этот бинарник
    /// ещё не знает, — читается как «записана треком», а не роняет декодер.
    func testUnknownStringDecodesAsRecorded() throws {
        for raw in ["future-source", "", "MANUAL", "Recorded"] {
            let data = Data("\"\(raw)\"".utf8)
            let decoded = try JSONDecoder().decode(TripOrigin.self, from: data)
            XCTAssertEqual(decoded, .recorded, "«\(raw)» обязано читаться как «записана треком»")
        }
    }

    func testKnownValuesRoundTrip() throws {
        for value in TripOrigin.allCases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(TripOrigin.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    func testDefaultTripIsRecorded() {
        let trip = Trip(id: UUID(), startDate: Date())
        XCTAssertEqual(trip.source, .recorded)
    }

    // MARK: - Провод (`TripSyncPayload`)

    private func encode(_ p: TripSyncPayload) throws -> [String: Any] {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(p)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testManualSourceReachesTheWire() throws {
        var trip = Trip(id: UUID(), startDate: Date())
        trip.source = .manual
        let entity = TripEntity(context: PersistenceController(inMemory: true).container.viewContext)
        let payload = TripSyncPayload(trip: trip, entity: entity)

        let json = try encode(payload)
        XCTAssertEqual(json["source"] as? String, "manual")
    }

    func testRecordedSourceRoundTrips() throws {
        var trip = Trip(id: UUID(), startDate: Date())
        trip.source = .recorded
        let entity = TripEntity(context: PersistenceController(inMemory: true).container.viewContext)
        let payload = TripSyncPayload(trip: trip, entity: entity)

        let data = try { () -> Data in
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
            return try e.encode(payload)
        }()
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(TripSyncPayload.self, from: data)

        XCTAssertEqual(back.source, .recorded)
    }

    /// Старый сервер про поле не знает — ключа нет вовсе, а не `null`.
    func testAServerWithoutTheColumnDecodesAsNil() throws {
        let old = """
        {"id":"\(UUID().uuidString)","title":null,"description":null,
         "startDate":"2026-09-19T10:00:00Z","endDate":null,"distance":1000,
         "maxSpeed":10,"averageSpeed":8,"fuelUsed":0,"elevation":0,
         "maxAltitude":null,"drivingTime":null,"stoppedTime":null,
         "region":null,"isPrivate":true,"vehicleId":null,"fuelCurrency":null,
         "previewPolyline":null,"badgesJson":null,"xpEarned":0,
         "conflictVersion":1,"lastModifiedAt":"2026-09-19T10:00:00Z",
         "serverCreatedAt":null}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let p = try d.decode(TripSyncPayload.self, from: Data(old.utf8))

        XCTAssertNil(p.source, "молчание сервера обязано означать «не сказано», а не .recorded")
    }

    // MARK: - `applyRemoteTrip` — nil не трогает, значение применяется, кроме pendingUpload

    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
    }

    override func tearDown() {
        repo = nil
        pc = nil
        super.tearDown()
    }

    @discardableResult
    private func makeLocal(id: UUID, source: String, synced: Bool) -> TripEntity {
        let e = TripEntity(context: pc.container.viewContext)
        e.id = id
        e.startDate = Date()
        e.source = source
        e.conflictVersion = 5
        e.syncStatus = synced ? SyncStatus.synced.rawValue : SyncStatus.pendingUpload.rawValue
        return e
    }

    private func payload(id: UUID, source: TripOrigin?, conflictVersion: Int = 6) -> TripSyncPayload {
        let startDate = Date()
        return TripSyncPayload(
            id: id, title: nil, description: nil, startDate: startDate, endDate: nil,
            distance: 0, maxSpeed: 0, averageSpeed: 0, fuelUsed: 0, elevation: 0,
            maxAltitude: nil, drivingTime: nil, stoppedTime: nil, region: nil,
            isPrivate: true, vehicleId: nil, isTransfer: nil, fuelCurrency: nil,
            previewPolyline: nil, badgesJson: nil, xpEarned: 0,
            conflictVersion: conflictVersion, lastModifiedAt: Date(),
            serverCreatedAt: nil, trackPoints: nil, photos: nil, checkpoints: nil,
            segments: nil, source: source
        )
    }

    private func fetch(_ id: UUID) -> TripEntity? {
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? pc.container.viewContext.fetch(req).first
    }

    func testNilSourceLeavesLocalUntouched() {
        let id = UUID()
        makeLocal(id: id, source: "manual", synced: true)

        repo.applyRemoteTrip(payload(id: id, source: nil))

        XCTAssertEqual(fetch(id)?.source, "manual", "молчание сервера не имеет права стереть источник")
    }

    func testValueIsAppliedWhenSynced() {
        let id = UUID()
        makeLocal(id: id, source: "recorded", synced: true)

        repo.applyRemoteTrip(payload(id: id, source: .manual))

        XCTAssertEqual(fetch(id)?.source, "manual")
    }

    /// Правка, ещё не уехавшая (`pendingUpload`), сильнее приехавшего ответа —
    /// тот же приём, что у `dashboardUnits` машины. `conflictVersion` пейлоада
    /// выше локального НАРОЧНО: иначе сработал бы общий гейт вверху функции
    /// (он бы и так не применил ничего, но проверял бы не то) — здесь важно
    /// именно то, что источник защищён СВОИМ гейтом `!hasLocalEdits`, пока
    /// остальные поля применяются.
    func testValueIsNotAppliedOverAnUnsyncedLocalEdit() {
        let id = UUID()
        makeLocal(id: id, source: "manual", synced: false)

        repo.applyRemoteTrip(payload(id: id, source: .recorded, conflictVersion: 99))

        XCTAssertEqual(fetch(id)?.source, "manual",
                       "локальная правка, ещё не уехавшая, не должна перезаписываться пулом")
        XCTAssertEqual(fetch(id)?.conflictVersion, 99,
                       "остальные поля применились — значит сработал именно гейт у source, а не общий ранний возврат")
    }
}
