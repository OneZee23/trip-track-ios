import XCTest
import CoreData
@testable import TripTrack

/// Провод выбора единицы: экран → `UserDefaults` → `UserSettingsEntity` →
/// пейлоад синка, и обратно.
///
/// До 0.6.7 провода не было вовсе — и это не «не доделали фичу», а сломанная
/// настройка, которая в приложении УЖЕ есть. Пикер писал единицу только в
/// `UserDefaults`, `saveSettings()` колонку не заполнял, а `APISyncTransport`
/// читал именно колонку и на пустой честно подставлял `"km"`. То есть выбор
/// миль не уезжал с телефона НИКОГДА: ни на сервер, ни на второй телефон, ни
/// в восстановление после переустановки.
///
/// Обратная половина была сломана симметрично: приехавший пулом выбор
/// `applyRemoteSettings` клал в колонку, а читают единицу экраны через
/// `@AppStorage`, то есть из `UserDefaults` — куда его никто не переносил.
///
/// Отдельно заперта отметка времени. `lastModifiedAt` у строки настроек
/// ставил только сервер, поэтому свежая местная правка выглядела прошлогодней
/// и любой пул её затирал. Флагом `syncStatus` это чинить нельзя: у строки
/// настроек он равен нулю (`pendingUpload`) с рождения, и защита по нему
/// отменила бы первый пул на новом телефоне — то есть восстановление аккаунта.
final class SettingsUnitWireTests: XCTestCase {

    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var settings: SettingsManager!
    /// Свой сьют вместо `UserDefaults.standard`: прогон не имеет права
    /// переписать настоящий выбор человека, а синглтон `SettingsManager.shared`
    /// подписан на тот же `.syncPullCompleted` и дрался бы за тот же ключ.
    private var store: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsUnitWireTests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        settings = SettingsManager(persistenceController: pc, unitStore: store)
    }

    override func tearDown() {
        settings = nil
        repo = nil
        pc = nil
        store?.removePersistentDomain(forName: suiteName)
        store = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func entity() -> UserSettingsEntity? {
        let request: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        request.fetchLimit = 1
        return try? pc.container.viewContext.fetch(request).first
    }

    private func payload(
        distance: String, volume: String = "liters", modified: Date
    ) -> SettingsSyncPayload {
        SettingsSyncPayload(
            id: entity()?.id ?? UUID(), avatarEmoji: "😎", themeMode: "dark", language: "ru",
            distanceUnit: distance, volumeUnit: volume, fuelConsumption: 7.8,
            fuelPrice: 56, fuelCurrency: "€", selectedVehicleId: nil,
            profileLevel: 1, profileXp: 0, currentStreak: 0, bestStreak: 0,
            lastTripDate: nil, conflictVersion: 1, lastModifiedAt: modified)
    }

    // MARK: - Телефон → сервер

    /// Выбрал мили — значит в базе мили. Без этой строки провод обрывается на
    /// первом же метре.
    func testChoosingMilesLandsInTheEntity() {
        settings.setDistanceUnit(.miles)

        XCTAssertEqual(entity()?.distanceUnit, "miles")
        XCTAssertEqual(settings.distanceUnit, .miles)
    }

    /// «Километры» — такой же ответ человека, как «мили», и записывается так же.
    /// Отличать «выбрал км» от «не выбирал» надо по отсутствию ключа, а не по
    /// отсутствию записи в базе.
    func testChoosingKilometresIsWrittenDownToo() {
        settings.setDistanceUnit(.miles)
        settings.setDistanceUnit(.km)

        XCTAssertEqual(entity()?.distanceUnit, "km")
    }

    func testChoosingGallonsLandsInTheEntity() {
        settings.setVolumeUnit(.gallons)

        XCTAssertEqual(entity()?.volumeUnit, "gallons")
        XCTAssertEqual(settings.volumeUnit, .gallons)
    }

    /// Любая дорога к сохранению доносит единицу — не только сеттер. Иначе
    /// следующий экран, забывший про `setDistanceUnit`, снова оборвал бы провод.
    func testAnyOtherSaveCarriesTheChoiceToo() {
        store.set("miles", forKey: SettingsManager.distanceUnitKey)

        settings.selectVehicle(id: nil)

        XCTAssertEqual(entity()?.distanceUnit, "miles")
    }

    /// То, что реально уедет на сервер.
    func testTheChoiceReachesTheSyncPayload() {
        settings.setDistanceUnit(.miles)
        settings.setVolumeUnit(.gallons)

        guard let e = entity() else { return XCTFail("нет строки настроек") }
        let p = SettingsSyncPayload(entity: e, settings: settings)

        XCTAssertEqual(p.distanceUnit, "miles")
        XCTAssertEqual(p.volumeUnit, "gallons")
    }

    /// Строка, заведённая прежней сборкой: в колонке пусто, а выбор у человека
    /// есть. Пейлоад обязан везти ВЫБОР, а не «km» — молчаливое умолчание в
    /// этом месте и означало «мили не уезжают».
    func testARowFromAnOlderBuildStillSendsTheRealChoice() {
        store.set("miles", forKey: SettingsManager.distanceUnitKey)
        store.set("gallons", forKey: SettingsManager.volumeUnitKey)
        guard let e = entity() else { return XCTFail("нет строки настроек") }
        e.distanceUnit = nil
        e.volumeUnit = nil

        let p = SettingsSyncPayload(entity: e, settings: settings)

        XCTAssertEqual(p.distanceUnit, "miles")
        XCTAssertEqual(p.volumeUnit, "gallons")
    }

    /// Правка обязана быть датирована — иначе входящий пул считает её старее
    /// себя и затирает.
    func testSavingStampsTheRow() {
        let before = Date().addingTimeInterval(-1)
        settings.setDistanceUnit(.miles)

        guard let stamp = entity()?.lastModifiedAt else { return XCTFail("нет отметки времени") }
        XCTAssertGreaterThan(stamp, before)
    }

    // MARK: - Сервер → телефон

    /// Второй телефон выбрал мили. Пул кладёт их в колонку — здесь проверяется,
    /// что они доезжают до `UserDefaults`, откуда единицу читают экраны.
    func testAPullWithMilesReachesTheDefaults() {
        repo.applyRemoteSettings(payload(distance: "miles", volume: "gallons", modified: Date()))
        settings.reloadUnitsFromStore()

        XCTAssertEqual(settings.distanceUnit, .miles)
        XCTAssertEqual(settings.volumeUnit, .gallons)
        XCTAssertEqual(store.string(forKey: SettingsManager.distanceUnitKey), "miles")
    }

    /// Та же дорога, но через настоящее уведомление: без подписки пул посреди
    /// сессии не обновляет ничего до перезапуска приложения.
    func testAPullNotificationRefreshesTheChoice() {
        repo.applyRemoteSettings(payload(distance: "miles", modified: Date()))

        let done = expectation(description: "единица перечитана")
        NotificationCenter.default.post(name: .syncPullCompleted, object: nil)
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)

        XCTAssertEqual(settings.distanceUnit, .miles)
    }

    /// Нераспознанное значение (чужой клиент, будущая версия) не стирает выбор
    /// человека и не превращается молча в километры.
    func testAnUnknownServerValueLeavesTheChoiceAlone() {
        settings.setDistanceUnit(.miles)

        entity()?.distanceUnit = "kilometres"
        settings.reloadUnitsFromStore()

        XCTAssertEqual(settings.distanceUnit, .miles)
    }

    // MARK: - Гонка

    /// Правка, ещё не уехавшая с телефона, входящим пулом не затирается.
    ///
    /// Это самый частый случай, а не редкий: очередь синка ставит апсерт через
    /// пять секунд, и фоновый пул успевает прийти раньше.
    func testIncomingDoesNotOverwriteAnEditWaitingToBeSent() {
        settings.setDistanceUnit(.miles)

        repo.applyRemoteSettings(
            payload(distance: "km", modified: Date().addingTimeInterval(-3600)))
        settings.reloadUnitsFromStore()

        XCTAssertEqual(entity()?.distanceUnit, "miles")
        XCTAssertEqual(settings.distanceUnit, .miles)
    }

    /// Обратная сторона того же правила: телефон, который честно отстал,
    /// принимает выбор со второго телефона целиком.
    func testAGenuinelyNewerRemoteChoiceWins() {
        settings.setDistanceUnit(.km)
        entity()?.lastModifiedAt = Date().addingTimeInterval(-3600)

        repo.applyRemoteSettings(payload(distance: "miles", modified: Date()))
        settings.reloadUnitsFromStore()

        XCTAssertEqual(settings.distanceUnit, .miles)
    }
}
