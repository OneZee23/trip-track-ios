import XCTest
@testable import TripTrack

/// Запись в keychain НЕ ИМЕЕТ ПРАВА терять значение. До 0.7.0 `save` делала
/// `delete` + `SecItemAdd`, а все вызывающие писали `try?` — то есть неудачный
/// `SecItemAdd` (телефон не разблокирован после перезагрузки, все записи под
/// `AfterFirstUnlockThisDeviceOnly`) стирал токен насовсем и молча.
/// `TokenStore.set` делал так дважды подряд, теряя пару целиком.
///
/// Проверяется через seam `KeychainHelper.ops`: настоящий keychain на
/// симуляторе всегда разблокирован, и ветку «недоступен» руками не получить.
final class KeychainWriteTests: XCTestCase {

    /// Фейковый keychain: своя память по паре «сервис + ключ» и заданные
    /// `OSStatus` на каждую операцию.
    private final class FakeKeychain {
        var items: [String: Data] = [:]
        /// Если задан — подменяет ответ `probe` (существование записи).
        var probeStatus: OSStatus?
        var updateStatus: OSStatus = errSecSuccess
        var addStatus: OSStatus = errSecSuccess
        /// Если задан — подменяет ответ чтения.
        var copyStatus: OSStatus?
        private(set) var updates = 0
        private(set) var adds = 0

        private func slot(_ service: String, _ key: String) -> String { "\(service)|\(key)" }

        func seed(_ value: String, service: String, key: String) {
            items[slot(service, key)] = Data(value.utf8)
        }

        func value(service: String, key: String) -> String? {
            items[slot(service, key)].flatMap { String(data: $0, encoding: .utf8) }
        }

        func ops() -> KeychainOps {
            KeychainOps(
                probe: { [unowned self] service, key in
                    if let probeStatus { return probeStatus }
                    return items[slot(service, key)] == nil ? errSecItemNotFound : errSecSuccess
                },
                update: { [unowned self] service, key, data in
                    updates += 1
                    guard updateStatus == errSecSuccess else { return updateStatus }
                    items[slot(service, key)] = data
                    return errSecSuccess
                },
                add: { [unowned self] service, key, data in
                    adds += 1
                    guard addStatus == errSecSuccess else { return addStatus }
                    items[slot(service, key)] = data
                    return errSecSuccess
                },
                copy: { [unowned self] service, key in
                    if let copyStatus { return (copyStatus, nil) }
                    guard let data = items[slot(service, key)] else { return (errSecItemNotFound, nil) }
                    return (errSecSuccess, data)
                },
                remove: { [unowned self] service, key in
                    items.removeValue(forKey: slot(service, key)) == nil ? errSecItemNotFound : errSecSuccess
                })
        }
    }

    private var fake: FakeKeychain!
    private var savedOps: KeychainOps!
    private var savedService: String!
    private let service = "com.triptrack.test.auth.api.example"
    private let key = "com.triptrack.auth.refreshToken"

    override func setUp() {
        super.setUp()
        fake = FakeKeychain()
        savedOps = KeychainHelper.ops
        savedService = KeychainHelper.service
        KeychainHelper.ops = fake.ops()
        KeychainHelper.service = service
    }

    override func tearDown() {
        KeychainHelper.ops = savedOps
        KeychainHelper.service = savedService
        // Фикстуру надо отпустить: XCTest держит экземпляры теста до конца
        // прогона, а замыкания `ops` захватывают `fake`.
        fake = nil
        savedOps = nil
        savedService = nil
        super.tearDown()
    }

    // MARK: - Запись

    func testExistingItemIsUpdatedNeverDeletedAndAdded() throws {
        fake.seed("old", service: service, key: key)

        try KeychainHelper.saveString("new", for: key)

        XCTAssertEqual(fake.value(service: service, key: key), "new")
        XCTAssertEqual(fake.updates, 1, "запись должна идти через SecItemUpdate")
        XCTAssertEqual(fake.adds, 0, "SecItemAdd поверх существующей записи не зовётся")
    }

    func testMissingItemIsAdded() throws {
        try KeychainHelper.saveString("first", for: key)

        XCTAssertEqual(fake.value(service: service, key: key), "first")
        XCTAssertEqual(fake.adds, 1)
        XCTAssertEqual(fake.updates, 0)
    }

    func testFailedUpdateThrowsAndKeepsPreviousValue() {
        fake.seed("live-token", service: service, key: key)
        fake.updateStatus = errSecInteractionNotAllowed

        XCTAssertThrowsError(try KeychainHelper.saveString("new", for: key)) { error in
            XCTAssertEqual(error as? KeychainHelper.KeychainError,
                           .saveFailed(errSecInteractionNotAllowed))
        }
        XCTAssertEqual(fake.value(service: service, key: key), "live-token",
                       "неудачная запись не имеет права потерять прежний токен")
    }

    func testUnavailableKeychainNeitherUpdatesNorAdds() {
        fake.seed("live-token", service: service, key: key)
        fake.probeStatus = errSecInteractionNotAllowed

        XCTAssertThrowsError(try KeychainHelper.saveString("new", for: key))
        XCTAssertEqual(fake.updates, 0)
        XCTAssertEqual(fake.adds, 0)
        XCTAssertEqual(fake.value(service: service, key: key), "live-token")
    }

    // MARK: - Чтение

    func testReadDistinguishesMissingFromUnavailable() {
        XCTAssertEqual(KeychainHelper.read(key: key), .missing)

        fake.seed("token", service: service, key: key)
        XCTAssertEqual(KeychainHelper.read(key: key), .value(Data("token".utf8)))

        fake.copyStatus = errSecInteractionNotAllowed
        XCTAssertEqual(KeychainHelper.read(key: key), .unavailable(errSecInteractionNotAllowed))
        XCTAssertNil(KeychainHelper.loadString(key: key),
                     "старая удобная обёртка по-прежнему отдаёт nil — решать судьбу сессии по ней нельзя")
    }

    // MARK: - Имя сервиса

    func testServiceNameBindsBuildAndApiHost() {
        XCTAssertEqual(
            KeychainHelper.composeService(bundleId: "com.onezee.TripTrack", host: "api.trip-track.app"),
            "com.onezee.TripTrack.auth.api.trip-track.app")
        XCTAssertNotEqual(
            KeychainHelper.composeService(bundleId: "com.onezee.TripTrack.dev", host: "macbook-pro.local"),
            KeychainHelper.composeService(bundleId: "com.onezee.TripTrack", host: "api.trip-track.app"),
            "dev-сборка с локальным бэкендом и App Store-сборка не делят ни одной записи")
        XCTAssertEqual(
            KeychainHelper.composeService(bundleId: nil, host: nil),
            "com.triptrack.auth.unknown")
    }

    // MARK: - Миграция

    private func freshDefaults() -> UserDefaults {
        let suite = "keychain-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults.standard.removeSuite(named: suite) }
        return defaults
    }

    func testMigrationCopiesSessionAndLeavesLegacyIntact() {
        let legacy = KeychainHelper.legacyService
        fake.seed("true", service: legacy, key: "com.triptrack.auth.isSignedIn")
        fake.seed("refresh-1", service: legacy, key: "com.triptrack.auth.refreshToken")
        fake.seed("apple-1", service: legacy, key: "com.triptrack.auth.userIdentifier")
        let defaults = freshDefaults()

        let moved = KeychainHelper.migrateLegacySession(from: legacy, to: service, defaults: defaults)

        XCTAssertEqual(moved, 3)
        XCTAssertEqual(fake.value(service: service, key: "com.triptrack.auth.refreshToken"), "refresh-1")
        XCTAssertEqual(fake.value(service: legacy, key: "com.triptrack.auth.refreshToken"), "refresh-1",
                       "старые записи не удаляются: их может читать другая сборка на том же телефоне")

        // Повтор ничего не делает.
        XCTAssertEqual(KeychainHelper.migrateLegacySession(from: legacy, to: service, defaults: defaults), 0)
    }

    func testMigrationDoesNotClobberAnExistingSession() {
        let legacy = KeychainHelper.legacyService
        fake.seed("true", service: legacy, key: "com.triptrack.auth.isSignedIn")
        fake.seed("refresh-old", service: legacy, key: "com.triptrack.auth.refreshToken")
        fake.seed("refresh-new", service: service, key: "com.triptrack.auth.refreshToken")

        let moved = KeychainHelper.migrateLegacySession(from: legacy, to: service, defaults: freshDefaults())

        XCTAssertEqual(moved, 0)
        XCTAssertEqual(fake.value(service: service, key: "com.triptrack.auth.refreshToken"), "refresh-new")
    }

    func testMigrationDefersWhileKeychainIsUnavailable() {
        let legacy = KeychainHelper.legacyService
        fake.seed("true", service: legacy, key: "com.triptrack.auth.isSignedIn")
        fake.seed("refresh-1", service: legacy, key: "com.triptrack.auth.refreshToken")
        fake.copyStatus = errSecInteractionNotAllowed
        let defaults = freshDefaults()

        XCTAssertEqual(KeychainHelper.migrateLegacySession(from: legacy, to: service, defaults: defaults), 0)
        XCTAssertFalse(defaults.bool(forKey: "com.triptrack.keychain.migrated.\(service)"),
                       "нечитаемый keychain нельзя залатчить как «мигрировано» — сессия пропала бы навсегда")

        // Телефон разблокировали — миграция доезжает.
        fake.copyStatus = nil
        XCTAssertEqual(KeychainHelper.migrateLegacySession(from: legacy, to: service, defaults: defaults), 2)
    }
}
