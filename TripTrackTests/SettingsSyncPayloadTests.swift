import XCTest
import CoreData
@testable import TripTrack

/// Где ЖИВЁТ косметика «Плюса» на проводе (0.8.0).
///
/// Задача 0 положила `avatarFrame`/`showPlusBadge` в `SettingsSyncPayload`;
/// контракт сервера, приехавший следом, поставил их на АККАУНТ — пишутся они
/// только через `POST /auth/profile-update` (тем же путём, что
/// `profileBackground`), читаются из `/auth/me`. Эти тесты держат именно
/// границу: у поля один писатель, а не два спорящих запроса, порядок которых
/// никто не гарантирует.
final class SettingsSyncPayloadTests: XCTestCase {

    private func sample() -> SettingsSyncPayload {
        SettingsSyncPayload(
            id: UUID(), avatarEmoji: "😎", themeMode: "dark", language: "ru",
            distanceUnit: "km", volumeUnit: "liters", fuelConsumption: 7.8,
            fuelPrice: 56, fuelCurrency: "€", selectedVehicleId: nil,
            profileLevel: 1, profileXp: 0, currentStreak: 0, bestStreak: 0,
            lastTripDate: nil, conflictVersion: 1, lastModifiedAt: Date()
        )
    }

    // MARK: - Провод настроек

    /// Пейлоад настроек про косметику «Плюса» не знает вовсе. Тест смотрит в
    /// САМ JSON, а не в тип: поле, добавленное «заодно» в структуру, иначе
    /// уехало бы вторым писателем молча.
    func testSettingsWireCarriesNoPlusCosmetics() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(sample())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["avatarFrame"], "рамка уехала вторым проводом")
        XCTAssertNil(json["showPlusBadge"], "значок уехал вторым проводом")
    }

    /// Сервер, приславший эти ключи в строке настроек (например, старая
    /// сборка 0.8.0-dev), не роняет разбор — и ничего не меняет.
    func testUnknownPlusKeysInTheSettingsRowDecodeHarmlessly() throws {
        let old = """
        {"id":"\(UUID().uuidString)","avatarEmoji":"😎","themeMode":"dark",
         "language":"ru","distanceUnit":"km","volumeUnit":"liters",
         "fuelConsumption":7.8,"fuelPrice":56,"fuelCurrency":"€",
         "selectedVehicleId":null,"profileLevel":1,"profileXp":0,
         "currentStreak":0,"bestStreak":0,"lastTripDate":null,
         "conflictVersion":1,"lastModifiedAt":"2026-09-19T00:00:00Z",
         "avatarFrame":"frame_neon","showPlusBadge":false}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let p = try d.decode(SettingsSyncPayload.self, from: Data(old.utf8))
        XCTAssertEqual(p.avatarEmoji, "😎")
    }

    // MARK: - Провод профиля

    /// `POST /auth/profile-update` — единственный писатель пары. Кодируется
    /// запрос ВРУЧНУЮ (отсутствующее поле значит «не менять»), поэтому
    /// проверяется он тоже по JSON: свойство, забытое в `encode(to:)`, молча
    /// не уезжает и запрос при этом успешен.
    func testProfileUpdateCarriesPlusCosmetics() throws {
        var req = ProfileUpdateRequest(
            displayName: nil, avatarEmoji: nil, profileBackground: nil,
            profileLevel: nil, profileXp: nil, currentStreak: nil, bestStreak: nil,
            activeVehicleId: nil, language: nil, showOnPublicMap: nil)
        req.avatarFrame = "frame_neon"
        req.showPlusBadge = false

        let data = try JSONEncoder().encode(req)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["avatarFrame"] as? String, "frame_neon")
        // `false` — ответ человека («значок спрятать»), а не «нечего
        // сказать»: он обязан уехать значением, а не быть выброшен.
        XCTAssertEqual(json["showPlusBadge"] as? Bool, false)
    }

    /// Ничего не выбрано — ничего и не шлём: `nil` в этом запросе значит «не
    /// менять», и зеркало, отправленное пустым, затёрло бы выбор, сделанный
    /// со второго телефона.
    func testProfileUpdateOmitsWhatWasNotAsked() throws {
        let req = ProfileUpdateRequest(
            displayName: "A", avatarEmoji: nil, profileBackground: nil,
            profileLevel: nil, profileXp: nil, currentStreak: nil, bestStreak: nil,
            activeVehicleId: nil, language: nil, showOnPublicMap: nil)

        let data = try JSONEncoder().encode(req)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["avatarFrame"])
        XCTAssertNil(json["showPlusBadge"])
    }

    /// `/auth/me` — обратная половина. Старый сервер ключей не шлёт, и это
    /// «не сказано», а не «сними рамку».
    func testMeResponseReadsThePairAndToleratesItsAbsence() throws {
        let d = JSONDecoder()
        let withPair = """
        {"id":"\(UUID().uuidString)","isPublic":true,
         "avatarFrame":"frame_gold","showPlusBadge":false}
        """
        let parsed = try d.decode(MeResponse.self, from: Data(withPair.utf8))
        XCTAssertEqual(parsed.avatarFrame, "frame_gold")
        XCTAssertEqual(parsed.showPlusBadge, false)

        let without = """
        {"id":"\(UUID().uuidString)","isPublic":true}
        """
        let old = try d.decode(MeResponse.self, from: Data(without.utf8))
        XCTAssertNil(old.avatarFrame)
        XCTAssertNil(old.showPlusBadge)
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

    /// Пул настроек косметику «Плюса» НЕ трогает — ни свежий, ни устаревший:
    /// у неё другой источник (`/auth/me`), и второй писатель отбирал бы у
    /// первого только что выбранную рамку.
    func testPullOfSettingsNeverTouchesPlusCosmetics() {
        let local = UserSettingsEntity(context: pc.container.viewContext)
        local.id = UUID()
        local.avatarFrame = "frame_chrome"
        local.showPlusBadge = false
        local.lastModifiedAt = Date().addingTimeInterval(-3600)

        repo.applyRemoteSettings(SettingsSyncPayload(
            id: local.id!, avatarEmoji: "🚗", themeMode: "light", language: "en",
            distanceUnit: "km", volumeUnit: "liters", fuelConsumption: 7.8,
            fuelPrice: 56, fuelCurrency: "€", selectedVehicleId: nil,
            profileLevel: 1, profileXp: 0, currentStreak: 0, bestStreak: 0,
            lastTripDate: nil, conflictVersion: 1, lastModifiedAt: Date()))

        // Соседнее поле того же блока доехало — значит пул реально
        // применился, и «не тронуто» ниже это не «ничего не произошло».
        XCTAssertEqual(local.avatarEmoji, "🚗")
        XCTAssertEqual(local.avatarFrame, "frame_chrome")
        XCTAssertEqual(local.showPlusBadge, false)
    }
}
