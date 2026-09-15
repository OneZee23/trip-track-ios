import XCTest
@testable import TripTrack

/// Карточка «Админ» (0.7.0) — от ответа сервера до тела POST'а.
///
/// Проверять здесь нечего «на глаз»: карточку видит ровно один человек на
/// всё приложение, и увидеть её сломанной он сможет только после деплоя.
/// Поэтому обе границы пройдены по-настоящему — декодер против фикстуры,
/// какую вернёт сервер, и тело запроса, снятое с провода через
/// `MockURLProtocol`.
///
/// Главное, что держит этот набор: **молчание сервера не даёт админских
/// прав**. Ключа `isAdmin` нет — карточки нет; ключ пришёл `false` — карточки
/// нет. Старый бэкенд, задеплоенный до 0.7.0, обязан вести себя как «не
/// админ», а не как «неизвестно».
@MainActor
final class NotificationSwitchesAdminTests: XCTestCase {

    private var session: URLSession!
    private var client: APIClient!
    /// Тела POST'ов, снятые С ПРОВОДА. `nonisolated(unsafe)` — обработчик
    /// `MockURLProtocol` зовётся с очереди сессии, как и он сам.
    private nonisolated(unsafe) static var bodies: [[String: Any]] = []

    private static let preMuteKey = "com.triptrack.settings.notificationsPreMute"
    private var savedPreMute: Any?
    private var savedForcesAdmin = false

    override func setUp() async throws {
        try await super.setUp()
        savedForcesAdmin = NotificationSwitches.forcesAdmin
        NotificationSwitches.forcesAdmin = false
        savedPreMute = UserDefaults.standard.object(forKey: Self.preMuteKey)
        UserDefaults.standard.removeObject(forKey: Self.preMuteKey)
        MockURLProtocol.reset()
        Self.bodies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(session: session, tokenStore: TokenStore.shared)
    }

    override func tearDown() async throws {
        // Мьют пишет набор в общий `UserDefaults` — вернуть как было, иначе
        // следующий тест (или следующий запуск приложения) получит наш.
        if let savedPreMute {
            UserDefaults.standard.set(savedPreMute, forKey: Self.preMuteKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.preMuteKey)
        }
        savedPreMute = nil
        NotificationSwitches.forcesAdmin = savedForcesAdmin
        MockURLProtocol.reset()
        Self.bodies = []
        // Без этого сессия не отпускает ни очередь, ни `MockURLProtocol`, и
        // роняет ЧУЖОЙ класс где-то в конце прогона — см. CLAUDE.md.
        session?.invalidateAndCancel()
        session = nil
        client = nil
        try await super.tearDown()
    }

    // MARK: - Мир на другом конце провода

    /// GET отдаёт `payload`; UPDATE — то, что ему прислали, плюс `isAdmin`,
    /// как настоящий сервер: ответ на апдейт это СОХРАНЁННОЕ состояние, и
    /// экран теперь читает именно его.
    private func serve(_ payload: String, admin: Bool = true) {
        let getBody = Data(#"{"status":"ok","payload":\#(payload)}"#.utf8)
        MockURLProtocol.requestHandler = { req in
            let path = req.url?.path ?? ""
            var json: [String: Any]?
            if let data = Self.bodyData(of: req) {
                json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            if let json { Self.bodies.append(json) }
            var body = getBody
            if path.hasSuffix("/update"), var echo = json {
                echo["isAdmin"] = admin
                if let saved = try? JSONSerialization.data(withJSONObject: echo) {
                    body = Data(#"{"status":"ok","payload":"#.utf8) + saved + Data("}".utf8)
                }
            }
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

    /// Ответ `/auth/notification-prefs/get` 0.7.0 — пять категорий плюс два
    /// новых ключа.
    private func prefs(admin: Bool, newAccounts: Bool) -> String {
        """
        {"notifyReactions":true,"notifyFollows":true,"notifyComments":true,
         "notifyWeeklyRecap":true,"notifyCompanions":true,
         "isAdmin":\(admin),"notifyNewAccounts":\(newAccounts)}
        """
    }

    /// Ответ сервера ДО 0.7.0: ни `isAdmin`, ни `notifyNewAccounts`.
    private var legacyPrefs: String {
        """
        {"notifyReactions":true,"notifyFollows":true,"notifyComments":true,
         "notifyWeeklyRecap":true,"notifyCompanions":true}
        """
    }

    // MARK: - Кто админ

    func testAdminFlagArrivesFromServer() async {
        serve(prefs(admin: true, newAccounts: false))
        let switches = NotificationSwitches(client: client)
        await switches.load()
        XCTAssertTrue(switches.isAdmin)
        XCTAssertFalse(switches.newAccounts, "тумблер обязан показать серверное выключено")
    }

    func testOldServerWithoutKeysIsNotAdmin() async {
        serve(legacyPrefs)
        let switches = NotificationSwitches(client: client)
        await switches.load()
        XCTAssertFalse(switches.isAdmin, "молчание сервера не даёт админских прав")
        // Серверный дефолт колонки — true; отсутствие ключа читается им же,
        // иначе включённый на сервере тумблер показывался бы выключенным.
        XCTAssertTrue(switches.newAccounts)
    }

    func testExplicitFalseIsNotAdmin() async {
        serve(prefs(admin: false, newAccounts: true))
        let switches = NotificationSwitches(client: client)
        await switches.load()
        XCTAssertFalse(switches.isAdmin)
    }

    /// Резолвер отдельно от загрузки: он и есть правило «нет ключа = не
    /// админ», и ломается оно одной строкой `?? true`.
    func testResolveAdminTreatsMissingAsFalse() {
        XCTAssertFalse(NotificationSwitches.resolveAdmin(nil))
        XCTAssertFalse(NotificationSwitches.resolveAdmin(false))
        XCTAssertTrue(NotificationSwitches.resolveAdmin(true))
    }

    /// `-debug-admin` рисует карточку — и НИЧЕГО больше. Флаг, взводивший
    /// заодно `isLoaded`, выключал `load()` на его же `guard`: настройки
    /// оставались дефолтными «всё включено», и первый щелчок любого тумблера
    /// записывал эти дефолты поверх настоящих настроек аккаунта. Поэтому
    /// здесь ответ сервера НАРОЧНО не дефолтный.
    func testDebugAdminFlagDoesNotSkipTheRealLoad() async throws {
        NotificationSwitches.forcesAdmin = true
        serve("""
        {"notifyReactions":false,"notifyFollows":true,"notifyComments":false,
         "notifyWeeklyRecap":true,"notifyCompanions":true,
         "isAdmin":false,"notifyNewAccounts":false}
        """, admin: false)

        let switches = NotificationSwitches(client: client)
        XCTAssertTrue(switches.isAdmin, "карточка обязана появиться и без сервера")
        XCTAssertFalse(switches.isLoaded, "загрузка ещё не шла")

        await switches.load()
        XCTAssertTrue(switches.isLoaded, "`load()` обязан отработать по-настоящему")
        XCTAssertTrue(switches.isAdmin, "флаг держит карточку и поверх ответа «не админ»")
        XCTAssertFalse(switches.newAccounts, "значение из ответа, не дефолт")
        Self.bodies = []

        switches.setCompanions(false)
        try await Task.sleep(nanoseconds: 900_000_000)
        let update = try XCTUnwrap(Self.bodies.last)
        XCTAssertEqual(update["notifyReactions"] as? Bool, false,
                       "уехали настоящие настройки аккаунта, а не дефолты")
        XCTAssertEqual(update["notifyComments"] as? Bool, false)
        XCTAssertEqual(update["notifyCompanions"] as? Bool, false)
    }

    // MARK: - Что уезжает на сервер

    func testSetNewAccountsPostsTheFlag() async throws {
        serve(prefs(admin: true, newAccounts: true))
        let switches = NotificationSwitches(client: client)
        await switches.load()
        Self.bodies = []

        switches.setNewAccounts(false)
        XCTAssertFalse(switches.newAccounts, "оптимистично, до ответа сервера")
        // Сохранение отложено на 400 мс, чтобы два щелчка схлопнулись в один POST.
        try await Task.sleep(nanoseconds: 900_000_000)

        let update = try XCTUnwrap(Self.bodies.last)
        XCTAssertEqual(update["notifyNewAccounts"] as? Bool, false)
        // Остальные пять уезжают неизменными — сервер пишет ВСЕ поля.
        XCTAssertEqual(update["notifyReactions"] as? Bool, true)
        XCTAssertEqual(update["notifyCompanions"] as? Bool, true)
    }

    func testSameValueDoesNotPost() async throws {
        serve(prefs(admin: true, newAccounts: true))
        let switches = NotificationSwitches(client: client)
        await switches.load()
        Self.bodies = []

        switches.setNewAccounts(true)
        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertTrue(Self.bodies.isEmpty, "щелчок в ту же сторону — не правка")
    }

    /// Ответ на UPDATE — это СОХРАНЁННОЕ сервером состояние, а не эхо
    /// запроса: `notifyNewAccounts` у не-админа сервер игнорирует. Без
    /// применения ответа экран показывал бы значение, которого в базе нет.
    func testUpdateResponseWins() async throws {
        let switches = NotificationSwitches(client: client)
        serve(prefs(admin: false, newAccounts: true), admin: false)
        await switches.load()
        XCTAssertFalse(switches.isAdmin)

        // Сервер не-админа: присланный `notifyNewAccounts` отброшен, в базе
        // осталось прежнее `true`.
        MockURLProtocol.requestHandler = { req in
            let path = req.url?.path ?? ""
            let payload = path.hasSuffix("/update")
                ? #"{"notifyReactions":true,"notifyFollows":true,"notifyComments":true,"notifyWeeklyRecap":true,"notifyCompanions":false,"isAdmin":false,"notifyNewAccounts":true}"#
                : #"{"notifyReactions":true,"notifyFollows":true,"notifyComments":true,"notifyWeeklyRecap":true,"notifyCompanions":true,"isAdmin":false,"notifyNewAccounts":true}"#
            let body = Data(#"{"status":"ok","payload":"#.utf8) + Data(payload.utf8) + Data("}".utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, body)
        }

        switches.setNewAccounts(false)
        XCTAssertFalse(switches.newAccounts, "оптимистично — до ответа")
        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertTrue(switches.newAccounts, "сервер не сохранил — экран обязан это показать")
        XCTAssertFalse(switches.companions, "остальные флаги тоже из ответа")
    }

    // MARK: - Общий выключатель про СВОИ события

    /// «Уведомления» — пять своих категорий. Чужая регистрация в него не
    /// входит: иначе выключение общего тумблера молча отрезало бы админский
    /// пуш, а включение — воскрешало бы его у того, кто его сам выключил.
    func testMasterIgnoresNewAccounts() async throws {
        serve(prefs(admin: true, newAccounts: true))
        let switches = NotificationSwitches(client: client)
        await switches.load()
        XCTAssertTrue(switches.master)

        switches.setNewAccounts(false)
        XCTAssertTrue(switches.master, "мастер не про чужую регистрацию")

        switches.setMaster(false)
        XCTAssertFalse(switches.master)
        XCTAssertFalse(switches.newAccounts, "выключенным его оставил человек, а не мастер")

        switches.setMaster(true)
        XCTAssertTrue(switches.master)
        XCTAssertFalse(switches.newAccounts, "мастер не воскрешает то, чего не гасил")
        try await Task.sleep(nanoseconds: 900_000_000)
    }

    // MARK: - Пуш в форграунде

    func testNewAccountPushBannersLikeSocialOnes() {
        XCTAssertEqual(
            NotificationManager.presentationOptions(for: NotificationManager.newAccountCategory),
            [.banner, .sound]
        )
        XCTAssertEqual(NotificationManager.presentationOptions(for: "REACTION"), [.banner, .sound])
        XCTAssertEqual(
            NotificationManager.presentationOptions(for: NotificationManager.tripStartPromptCategory),
            []
        )
        XCTAssertEqual(NotificationManager.presentationOptions(for: "WHATEVER"), [])
    }

    /// Пуша нет во «Входящих» — сервер его не записывает, и дёргать список
    /// не за чем.
    func testNewAccountPushDoesNotTouchTheInbox() {
        XCTAssertFalse(NotificationManager.refreshesInbox(NotificationManager.newAccountCategory))
        XCTAssertTrue(NotificationManager.refreshesInbox("REACTION"))
        XCTAssertTrue(NotificationManager.refreshesInbox("COMPANION_ACCEPTED"))
    }

    // MARK: - Строки

    /// Проверяется НАЛИЧИЕ КЛЮЧА в каждой таблице, а не получившаяся строка:
    /// `tr` при промахе молча отдаёт английский, и сравнение результатов
    /// прошло бы на непереведённом ключе. Сравнить с английским тоже нельзя —
    /// «Admin» по-немецки и правда «Admin».
    func testCopyExistsInEveryTable() {
        let tables: [(String, [String: String])] = [
            ("de", Translations.de), ("es", Translations.es), ("fr", Translations.fr),
            ("it", Translations.it), ("pl", Translations.pl), ("tr", Translations.tr),
            ("id", Translations.id), ("uk", Translations.uk), ("pt", Translations.pt),
            ("kk", Translations.kk), ("fil", Translations.fil),
        ]
        XCTAssertEqual(tables.count, 11)
        for key in ["adminSectionTitle", "adminNotifyNewUsers", "adminHintNewUsers"] {
            for (name, table) in tables {
                let value = table[key]
                XCTAssertNotNil(value, "\(name): ключа «\(key)» нет в таблице")
                XCTAssertFalse(value?.isEmpty ?? true, "\(name): «\(key)» пустой")
            }
        }
        XCTAssertEqual(AppStrings.adminSectionTitle(.ru), "Админ")
        XCTAssertEqual(AppStrings.adminSectionTitle(.en), "Admin")
        XCTAssertEqual(AppStrings.adminNotifyNewUsers(.de), "Neue Nutzer")
        XCTAssertEqual(AppStrings.adminNotifyNewUsers(.tr), "Yeni kullanıcılar")
    }
}
