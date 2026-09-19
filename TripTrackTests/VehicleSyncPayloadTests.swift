import XCTest
import CoreData
@testable import TripTrack

/// `Vehicle.cardStyle` на проводе (0.8.0, «Плюс») — фон карточки машины в
/// гараже.
///
/// Тот же приём, что у `dashboardUnits` (0.6.7): `nil` значит «сервер
/// молчит», не «сбросить», и молчание не имеет права стереть выбор ни на
/// одном из трёх кругов — JSON, `applyRemoteVehicle`, правку в полёте.
final class VehicleSyncPayloadTests: XCTestCase {

    // MARK: - Провод

    private func encode(_ p: VehicleSyncPayload) throws -> [String: Any] {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(p)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sample(cardStyle: String?) -> VehicleSyncPayload {
        VehicleSyncPayload(
            id: UUID(), name: "Тойота", avatarEmoji: "🚗", odometerKm: 1000,
            level: 1, stickersJson: nil, cityConsumption: 10, highwayConsumption: 6,
            fuelPrice: 56, conflictVersion: 1, lastModifiedAt: Date(),
            cardStyle: cardStyle
        )
    }

    func testCardStyleReachesTheWire() throws {
        let json = try encode(sample(cardStyle: "sunset"))
        XCTAssertEqual(json["cardStyle"] as? String, "sunset")
    }

    /// `nil` уезжает ключом ОТСУТСТВУЮЩИМ, а не как `null` — сервер без
    /// колонки обязан декодироваться, и локальное «нечего сказать» не имеет
    /// права стать чужим «стереть».
    func testNilCardStyleIsOmittedRatherThanSentAsNull() throws {
        let json = try encode(sample(cardStyle: nil))
        XCTAssertNil(json["cardStyle"])
    }

    func testCardStyleRoundTrips() throws {
        let original = sample(cardStyle: "midnight")
        let data = try { () -> Data in
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
            return try e.encode(original)
        }()
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(VehicleSyncPayload.self, from: data)
        XCTAssertEqual(back.cardStyle, "midnight")
    }

    /// Сервер до 0.8.0 про колонку не знает — декодер обязан отработать, а
    /// поле прочитаться как «не сказано».
    func testAServerWithoutTheColumnDecodesAsNil() throws {
        let old = """
        {"id":"\(UUID().uuidString)","name":"Нива","avatarEmoji":"🚙",
         "odometerKm":38400,"level":22,"cityConsumption":10,
         "highwayConsumption":6,"fuelPrice":56,"conflictVersion":3,
         "lastModifiedAt":"2026-09-19T00:00:00Z"}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let p = try d.decode(VehicleSyncPayload.self, from: Data(old.utf8))
        XCTAssertNil(p.cardStyle)
    }

    // MARK: - `applyRemoteVehicle`

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
    private func makeLocal(id: UUID, cardStyle: String?, synced: Bool) -> VehicleEntity {
        let e = VehicleEntity(context: pc.container.viewContext)
        e.id = id
        e.name = "Тойота"
        e.avatarEmoji = "🚗"
        e.avatarStyle = VehicleAvatar.defaultStyle
        e.vehicleType = "car"
        e.odometerKm = 1000
        e.vehicleLevel = 1
        e.cardStyle = cardStyle
        e.lastModifiedAt = Date()
        e.syncStatus = synced ? SyncStatus.synced.rawValue : SyncStatus.pendingUpload.rawValue
        return e
    }

    private func payload(id: UUID, cardStyle: String?) -> VehicleSyncPayload {
        VehicleSyncPayload(
            id: id, name: "Тойота", avatarEmoji: "🚗", odometerKm: 1000,
            level: 1, stickersJson: nil, cityConsumption: 10, highwayConsumption: 6,
            fuelPrice: 56, conflictVersion: 1, lastModifiedAt: Date(),
            cardStyle: cardStyle
        )
    }

    private func fetch(_ id: UUID) -> VehicleEntity? {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? pc.container.viewContext.fetch(req).first
    }

    /// Молчание сервера не сбрасывает выбор — ровно как у силуэта в 0.6.2.
    func testSilentServerDoesNotResetCardStyle() {
        let id = UUID()
        makeLocal(id: id, cardStyle: "sunset", synced: true)

        repo.applyRemoteVehicle(payload(id: id, cardStyle: nil))

        XCTAssertEqual(fetch(id)?.cardStyle, "sunset")
    }

    /// Синхронизированная строка честно принимает пришедшее значение.
    func testServerValueOverwritesLocalCardStyleWhenSynced() {
        let id = UUID()
        makeLocal(id: id, cardStyle: "sunset", synced: true)

        repo.applyRemoteVehicle(payload(id: id, cardStyle: "midnight"))

        XCTAssertEqual(fetch(id)?.cardStyle, "midnight")
    }

    /// Правка, ещё не уехавшая, сильнее пришедшего ответа — тот же гейт, что
    /// у `dashboardUnits`/четырёх осей видимости.
    func testValueIsNotAppliedOverAnUnsyncedLocalEdit() {
        let id = UUID()
        makeLocal(id: id, cardStyle: "sunset", synced: false)

        repo.applyRemoteVehicle(payload(id: id, cardStyle: "midnight"))

        XCTAssertEqual(fetch(id)?.cardStyle, "sunset",
                       "локальная правка, ещё не уехавшая, не должна перезаписываться пулом")
    }

    /// Новая машина с молчащего сервера остаётся без фона, а не падает.
    func testNewVehicleFromSilentServerHasNoCardStyle() {
        let id = UUID()
        repo.applyRemoteVehicle(payload(id: id, cardStyle: nil))
        XCTAssertNil(fetch(id)?.cardStyle)
    }
}
