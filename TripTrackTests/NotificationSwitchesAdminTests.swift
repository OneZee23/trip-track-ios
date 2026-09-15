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
    private nonisolated(unsafe) static var paths: [String] = []

    private static let preMuteKey = "com.triptrack.settings.notificationsPreMute"
    private var savedPreMute: Any?

    override func setUp() async throws {
        try await super.setUp()
        savedPreMute = UserDefaults.standard.object(forKey: Self.preMuteKey)
        UserDefaults.standard.removeObject(forKey: Self.preMuteKey)
        MockURLProtocol.reset()
        Self.bodies = []
        Self.paths = []
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
        MockURLProtocol.reset()
        Self.bodies = []
        Self.paths = []
        // Без этого сессия не отпускает ни очередь, ни `MockURLProtocol`, и
        // роняет ЧУЖОЙ класс где-то в конце прогона — см. CLAUDE.md.
        session?.invalidateAndCancel()
        session = nil
        client = nil
        try await super.tearDown()
    }

    // MARK: - Мир на другом конце провода

    private func serve(_ payload: String) {
        let body = Data(#"{"status":"ok","payload":\#(payload)}"#.utf8)
        MockURLProtocol.requestHandler = { req in
            Self.paths.append(req.url?.path ?? "")
            if let data = Self.bodyData(of: req),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.bodies.append(json)
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

    func testCopyExistsInEveryTable() {
        for lang in LanguageManager.Language.allCases {
            for text in [AppStrings.adminSectionTitle(lang),
                         AppStrings.adminNotifyNewUsers(lang),
                         AppStrings.adminHintNewUsers(lang)] {
                XCTAssertFalse(text.isEmpty, "\(lang.rawValue)")
            }
        }
        XCTAssertEqual(AppStrings.adminSectionTitle(.ru), "Админ")
        XCTAssertEqual(AppStrings.adminSectionTitle(.en), "Admin")
    }
}
