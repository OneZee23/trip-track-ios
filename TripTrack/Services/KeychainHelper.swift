import Foundation
import Security
import OSLog

private let keychainLog = Logger(subsystem: "com.triptrack", category: "keychain")

/// Результат чтения из keychain. Нужен ТРЁХЗНАЧНЫЙ, а не `Data?`: «записи нет»
/// и «прочитать сейчас нельзя» — разные ответы, и в 0.7.0 их путали три места
/// (`APIClient.refreshIfNeeded`, `AuthService.loadFromKeychain`, `TokenStore`).
/// Все записи лежат под `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
/// а приложение просыпается в фоне по локации и автозапуску — то есть запуск
/// на ЗАБЛОКИРОВАННОМ после перезагрузки телефоне не экзотика. Тогда чтение
/// возвращает `errSecInteractionNotAllowed`, и прочитанное как «сессии нет»
/// выкидывало человека из аккаунта без единой строки на сервере.
enum KeychainRead: Equatable {
    /// Запись есть и прочитана.
    case value(Data)
    /// Записи нет — `errSecItemNotFound`. Единственный ответ, по которому
    /// можно решать, что сессии не существует.
    case missing
    /// Прочитать нельзя: телефон не разблокирован после перезагрузки, ошибка
    /// демона, что угодно ещё. «Состояние неизвестно» — держим то, что уже в
    /// памяти, и перечитываем позже.
    case unavailable(OSStatus)
}

/// Записи/чтения keychain, вынесенные за seam. Тесты подменяют их фейком с
/// заданными `OSStatus` — иначе «неудачная запись не теряет прежнее значение»
/// проверяется только руками на устройстве с заблокированным экраном.
struct KeychainOps {
    /// `errSecSuccess` — запись есть, `errSecItemNotFound` — нет, иначе беда.
    var probe: (_ service: String, _ key: String) -> OSStatus
    var update: (_ service: String, _ key: String, _ data: Data) -> OSStatus
    var add: (_ service: String, _ key: String, _ data: Data) -> OSStatus
    var copy: (_ service: String, _ key: String) -> (OSStatus, Data?)
    var remove: (_ service: String, _ key: String) -> OSStatus

    static let system = KeychainOps(
        probe: { service, key in
            var query = KeychainHelper.baseQuery(service: service, key: key)
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            return SecItemCopyMatching(query as CFDictionary, &result)
        },
        update: { service, key, data in
            let query = KeychainHelper.baseQuery(service: service, key: key)
            let attrs: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        },
        add: { service, key, data in
            var query = KeychainHelper.baseQuery(service: service, key: key)
            query[kSecValueData as String] = data
            // `ThisDeviceOnly` so tokens & identity DO NOT replicate via iCloud
            // Keychain or encrypted device backup. Without this, an attacker who
            // restores a backup of the user's iPhone (including via known passcode-
            // bypass attacks at low PIN entropy) inherits a valid session.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(query as CFDictionary, nil)
        },
        copy: { service, key in
            var query = KeychainHelper.baseQuery(service: service, key: key)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        },
        remove: { service, key in
            var query = KeychainHelper.baseQuery(service: service, key: key)
            // `kSecAttrSynchronizableAny` ensures the delete sweeps any old
            // iCloud-synced records left over from pre-hardening builds.
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            return SecItemDelete(query as CFDictionary)
        })
}

enum KeychainHelper {

    enum KeychainError: Error, Equatable {
        case saveFailed(OSStatus)
        case loadFailed
        case deleteFailed(OSStatus)
    }

    /// Имя сервиса ДО 0.7.0 — одно на все сборки и все бэкенды. Токен,
    /// выданный локальным dev-сервером, лежал там же, где продовый, и
    /// `INVALID_REFRESH_TOKEN` от Мака убивал сессию App Store-сборки.
    /// Не удаляется никогда: прод-сборка на том же телефоне может всё ещё
    /// читать эти записи, и снос был бы разлогином, который мы и чиним.
    static let legacyService = "com.triptrack.keychain"

    /// Имя сервиса = bundle id + ХОСТ API. Обе половины обязательны: bundle id
    /// разводит Debug (`…TripTrack.dev`) и App Store, хост разводит
    /// `MacBook-Pro.local` и `api.trip-track.app` внутри одной сборки. Токен
    /// одной вселенной физически нельзя предъявить другой.
    static func composeService(bundleId: String?, host: String?) -> String {
        let bundle = bundleId?.isEmpty == false ? bundleId! : "com.triptrack"
        let apiHost = (host?.isEmpty == false ? host! : "unknown").lowercased()
        return "\(bundle).auth.\(apiHost)"
    }

    static var defaultService: String {
        composeService(bundleId: Bundle.main.bundleIdentifier, host: AppConfig.apiBaseURL.host)
    }

    /// Подменяется в тестах. Присвоение НЕ трогает миграцию: она уже отработала
    /// (или отработает) для настоящего имени.
    static var service: String = {
        let name = defaultService
        migrateLegacySessionIfNeeded(into: name)
        return name
    }()

    /// Ключи сессии. Всё, что при переезде на новое имя сервиса обязано
    /// приехать вместе — иначе человек, обновившийся с 0.6.8, получил бы
    /// пустой keychain и карточку «войдите снова» прямо на апдейте.
    static let sessionKeys = [
        "com.triptrack.auth.accessToken",
        "com.triptrack.auth.refreshToken",
        "com.triptrack.auth.accountId",
        "com.triptrack.auth.userIdentifier",
        "com.triptrack.auth.userName",
        "com.triptrack.auth.userEmail",
        "com.triptrack.auth.identityToken",
        "com.triptrack.auth.isSignedIn",
        "com.triptrack.auth.sessionExpired"
    ]

    static var ops: KeychainOps = .system

    static func baseQuery(service: String, key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // Match the saved record's synchronizable flag so we never read
            // a stale iCloud-synced copy from a previous install era.
            kSecAttrSynchronizable as String: false
        ]
    }

    // MARK: - Миграция имени сервиса

    /// Переезд на имя сервиса, привязанное к сборке и хосту. Условия строгие:
    /// у СТАРОГО имени есть сессия, у нового — ничего. Старое не удаляется
    /// (см. `legacyService`), флаг «сделано» пишется по имени нового сервиса,
    /// то есть Debug и Release мигрируют независимо, а смена хоста заводит
    /// свою вселенную с нуля, а не тащит туда чужие токены.
    @discardableResult
    static func migrateLegacySession(
        from legacy: String, to current: String,
        keys: [String] = sessionKeys, defaults: UserDefaults = .standard
    ) -> Int {
        let flag = "com.triptrack.keychain.migrated.\(current)"
        guard !defaults.bool(forKey: flag) else { return 0 }

        // «Сессия есть» = маркер входа или refresh-токен. Ни один из них не
        // должен читаться как «нет», когда keychain просто недоступен:
        // в этом случае выходим БЕЗ флага и попробуем на следующем запуске.
        let marker = read(key: "com.triptrack.auth.isSignedIn", service: legacy)
        let refresh = read(key: "com.triptrack.auth.refreshToken", service: legacy)
        if case .unavailable = marker { return 0 }
        if case .unavailable = refresh { return 0 }
        let legacyHasSession = marker != .missing || refresh != .missing
        guard legacyHasSession else {
            defaults.set(true, forKey: flag)
            return 0
        }

        let currentMarker = read(key: "com.triptrack.auth.isSignedIn", service: current)
        let currentRefresh = read(key: "com.triptrack.auth.refreshToken", service: current)
        if case .unavailable = currentMarker { return 0 }
        if case .unavailable = currentRefresh { return 0 }
        guard currentMarker == .missing, currentRefresh == .missing else {
            defaults.set(true, forKey: flag)
            return 0
        }

        var moved = 0
        for key in keys {
            guard case .value(let data) = read(key: key, service: legacy) else { continue }
            let status = write(data, key: key, service: current)
            if status == errSecSuccess { moved += 1 }
            else { keychainLog.error("migrate: write failed key=\(key, privacy: .public) status=\(status)") }
        }
        defaults.set(true, forKey: flag)
        keychainLog.notice("migrate: moved \(moved) keys from legacy service")
        return moved
    }

    static func migrateLegacySessionIfNeeded(into current: String) {
        migrateLegacySession(from: legacyService, to: current)
    }

    // MARK: - Запись

    /// Пишет `SecItemUpdate`-ом, если запись есть, и `SecItemAdd`-ом, если нет.
    /// НИКОГДА не удаляет перед записью: прежний `delete` + `SecItemAdd` терял
    /// уже удалённое значение, когда `SecItemAdd` не проходил (телефон не
    /// разблокирован после перезагрузки), а все вызывающие писали `try?`.
    /// `TokenStore.set` делал так ДВА раза подряд — то есть терял пару целиком.
    static func write(_ data: Data, key: String, service: String) -> OSStatus {
        let probe = ops.probe(service, key)
        switch probe {
        case errSecSuccess:
            return ops.update(service, key, data)
        case errSecItemNotFound:
            return ops.add(service, key, data)
        default:
            // Keychain недоступен — прежнее значение на месте, и это лучшее,
            // что может случиться. Наверх уезжает статус, а не молчание.
            return probe
        }
    }

    static func save(_ data: Data, for key: String) throws {
        let status = write(data, key: key, service: service)
        guard status == errSecSuccess else {
            keychainLog.error("save failed key=\(key, privacy: .public) status=\(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Чтение

    static func read(key: String, service: String) -> KeychainRead {
        let (status, data) = ops.copy(service, key)
        switch status {
        case errSecSuccess:
            guard let data else { return .unavailable(status) }
            return .value(data)
        case errSecItemNotFound:
            return .missing
        default:
            keychainLog.notice("read unavailable key=\(key, privacy: .public) status=\(status)")
            return .unavailable(status)
        }
    }

    static func read(key: String) -> KeychainRead { read(key: key, service: service) }

    /// Удобная обёртка для НЕ-сессионных чтений: «нет записи» и «нельзя
    /// прочитать» одинаково дают `nil`. Всё, что решает судьбу сессии, обязано
    /// звать `read(key:)` и различать эти два случая.
    static func load(key: String) -> Data? {
        guard case .value(let data) = read(key: key) else { return nil }
        return data
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        ops.remove(service, key) == errSecSuccess
    }

    // MARK: - String convenience

    static func saveString(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.saveFailed(errSecParam)
        }
        try save(data, for: key)
    }

    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Строка с разделением «нет» и «недоступно» — для сессионных чтений.
    static func readStringValue(key: String) -> (string: String?, read: KeychainRead) {
        let result = read(key: key)
        guard case .value(let data) = result else { return (nil, result) }
        return (String(data: data, encoding: .utf8), result)
    }
}
