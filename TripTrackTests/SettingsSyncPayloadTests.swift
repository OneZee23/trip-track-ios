import XCTest
import CoreData
@testable import TripTrack

/// `avatarFrame` / `showPlusBadge` на проводе (0.8.0, «Плюс»).
///
/// Гейт здесь НЕ повторяет `hasLocalEdits` дословно, вопреки первому чтению
/// «скопировать приём `dashboardUnits`»: `applyRemoteSettings` уже объясняет
/// в своей доке, почему `syncStatus` не годится для строки настроек — он
/// равен `pendingUpload` (0) с рождения, и `saveSettings()` не переводит его
/// обратно после правки СУЩЕСТВУЮЩЕЙ строки (в отличие от машины и поездки,
/// где каждый мутатор явно ставит `pendingUpload`). Копия гейта дословно
/// держала бы эту пару вечно неприменимой к синхронизированной строке.
/// Поэтому пара защищена ТОЙ ЖЕ «newest wins» проверкой по `lastModifiedAt`,
/// что и остальные предпочтения в том же блоке (`avatarEmoji`, `themeMode`,
/// …) — тот же результат («правка, ещё не уехавшая, не теряется»), но
/// правильным для этой сущности механизмом.
final class SettingsSyncPayloadTests: XCTestCase {

    // MARK: - Провод

    private func sample(avatarFrame: String?, showPlusBadge: Bool?) -> SettingsSyncPayload {
        SettingsSyncPayload(
            id: UUID(), avatarEmoji: "😎", themeMode: "dark", language: "ru",
            distanceUnit: "km", volumeUnit: "liters", fuelConsumption: 7.8,
            fuelPrice: 56, fuelCurrency: "€", selectedVehicleId: nil,
            profileLevel: 1, profileXp: 0, currentStreak: 0, bestStreak: 0,
            lastTripDate: nil, conflictVersion: 1, lastModifiedAt: Date(),
            avatarFrame: avatarFrame, showPlusBadge: showPlusBadge
        )
    }

    func testFieldsReachTheWire() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(sample(avatarFrame: "chrome", showPlusBadge: false))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["avatarFrame"] as? String, "chrome")
        XCTAssertEqual(json["showPlusBadge"] as? Bool, false)
    }

    /// `false` — ответ человека («значок спрятать»), а не «нечего сказать»,
    /// и обязан уехать как значение, а не быть выброшен как пустой.
    func testFalseShowPlusBadgeIsSentNotDropped() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(sample(avatarFrame: nil, showPlusBadge: false))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["showPlusBadge"] as? Bool, false)
    }

    func testFieldsRoundTrip() throws {
        let original = sample(avatarFrame: "neon", showPlusBadge: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let data = try e.encode(original)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(SettingsSyncPayload.self, from: data)

        XCTAssertEqual(back.avatarFrame, "neon")
        XCTAssertEqual(back.showPlusBadge, true)
    }

    /// Сервер до 0.8.0 про эти два ключа не знает — декодер обязан
    /// отработать, а поля прочитаться как «не сказано».
    func testAServerWithoutTheColumnsDecodesAsNil() throws {
        let old = """
        {"id":"\(UUID().uuidString)","avatarEmoji":"😎","themeMode":"dark",
         "language":"ru","distanceUnit":"km","volumeUnit":"liters",
         "fuelConsumption":7.8,"fuelPrice":56,"fuelCurrency":"€",
         "selectedVehicleId":null,"profileLevel":1,"profileXp":0,
         "currentStreak":0,"bestStreak":0,"lastTripDate":null,
         "conflictVersion":1,"lastModifiedAt":"2026-09-19T00:00:00Z"}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let p = try d.decode(SettingsSyncPayload.self, from: Data(old.utf8))

        XCTAssertNil(p.avatarFrame)
        XCTAssertNil(p.showPlusBadge)
    }

    // MARK: - `applyRemoteSettings`

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
    private func makeLocal(avatarFrame: String?, showPlusBadge: Bool, modified: Date) -> UserSettingsEntity {
        let e = UserSettingsEntity(context: pc.container.viewContext)
        e.id = UUID()
        e.avatarFrame = avatarFrame
        e.showPlusBadge = showPlusBadge
        e.lastModifiedAt = modified
        return e
    }

    private func payload(
        id: UUID, avatarFrame: String?, showPlusBadge: Bool?, modified: Date
    ) -> SettingsSyncPayload {
        SettingsSyncPayload(
            id: id, avatarEmoji: "😎", themeMode: "dark", language: "ru",
            distanceUnit: "km", volumeUnit: "liters", fuelConsumption: 7.8,
            fuelPrice: 56, fuelCurrency: "€", selectedVehicleId: nil,
            profileLevel: 1, profileXp: 0, currentStreak: 0, bestStreak: 0,
            lastTripDate: nil, conflictVersion: 1, lastModifiedAt: modified,
            avatarFrame: avatarFrame, showPlusBadge: showPlusBadge
        )
    }

    /// Молчание сервера (`nil`) не стирает локальный выбор, даже когда
    /// временная метка пришедшего ответа свежее.
    func testNilFieldsLeaveLocalUntouchedEvenWhenNewer() {
        let local = makeLocal(avatarFrame: "chrome", showPlusBadge: false,
                              modified: Date().addingTimeInterval(-3600))

        repo.applyRemoteSettings(payload(
            id: local.id!, avatarFrame: nil, showPlusBadge: nil, modified: Date()))

        XCTAssertEqual(local.avatarFrame, "chrome")
        XCTAssertEqual(local.showPlusBadge, false)
    }

    /// Свежий ответ с настоящим значением применяется — так выбор доезжает
    /// со второго телефона.
    func testFreshValueIsApplied() {
        let local = makeLocal(avatarFrame: "chrome", showPlusBadge: false,
                              modified: Date().addingTimeInterval(-3600))

        repo.applyRemoteSettings(payload(
            id: local.id!, avatarFrame: "neon", showPlusBadge: true, modified: Date()))

        XCTAssertEqual(local.avatarFrame, "neon")
        XCTAssertEqual(local.showPlusBadge, true)
    }

    /// Устаревший ответ (не пришедший позже локальной правки) не имеет
    /// права откатить выбор — тот же приём, что у `themeMode`/`language`.
    func testStaleValueIsIgnored() {
        let local = makeLocal(avatarFrame: "chrome", showPlusBadge: true, modified: Date())

        repo.applyRemoteSettings(payload(
            id: local.id!, avatarFrame: "neon", showPlusBadge: false,
            modified: Date().addingTimeInterval(-3600)))

        XCTAssertEqual(local.avatarFrame, "chrome")
        XCTAssertEqual(local.showPlusBadge, true)
    }

    /// Первая строка на новом телефоне: нечего защищать, сервер применяется
    /// целиком.
    func testAFirstEverRowAdoptsTheServerValues() {
        let serverId = UUID()
        repo.applyRemoteSettings(payload(
            id: serverId, avatarFrame: "neon", showPlusBadge: false,
            modified: Date().addingTimeInterval(-86_400)))

        let req: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        let saved = try? pc.container.viewContext.fetch(req).first
        XCTAssertEqual(saved?.avatarFrame, "neon")
        XCTAssertEqual(saved?.showPlusBadge, false)
    }
}
