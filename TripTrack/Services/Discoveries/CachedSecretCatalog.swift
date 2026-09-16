import Foundation
import OSLog

private let catalogLog = Logger(subsystem: "com.triptrack", category: "discoveries")

/// Каталог секретов с сервера, с кэшем на диске и бандлом за спиной.
///
/// Три состояния, и ни одно из них не оставляет приложение без каталога:
/// сеть есть — свежий список с `/secrets/catalog`; сети нет — тот, что лежит в
/// Application Support с прошлого раза; кэша нет вовсе (первый запуск в
/// самолёте) — бандловый `Secrets.json`, а он в 0.7.0 ПУСТ, то есть до первого
/// ответа сервера секретов нет вовсе. Поэтому `all()` не `async` и ничего не
/// ждёт: разбор трека на финише спрашивает каталог, и ждать сети в этот момент
/// нельзя — поездка закончилась, а не началась.
///
/// **Версия, а не время.** Обновление спрашивает сервер с `?version=` последней
/// известной; совпала — приходит `unchanged` без списка, и мы не тратим ни
/// байта. Само обращение — не чаще раза в сутки (`refreshInterval`): секреты
/// добавляются релизами, а не минутами.
///
/// Каталог — единственное в этой папке, что ходит в сеть, и это законно: он
/// ПУБЛИЧНЫЙ (усечённые хеши без координат и без имён), в нём нет ни одной
/// строки человека, и грузится он при любом состоянии Cloud Sync. Личное —
/// раскрытие — живёт рядом, в `DiscoveryReveal`, и без облака молчит.
///
/// `@unchecked Sendable`: всё изменяемое состояние — три поля под одним
/// `NSLock`, а файл пишется только внутри `refresh`.
final class CachedSecretCatalog: SecretCatalog, @unchecked Sendable {
    static let shared = CachedSecretCatalog()

    /// Раз в сутки. Чаще незачем: набор секретов живёт релизами.
    static let refreshInterval: TimeInterval = 24 * 60 * 60
    /// Когда каталог спрашивали в последний раз. В `UserDefaults`, а не в файле
    /// кэша: неудачная попытка дату НЕ двигает, и следующий запуск пробует
    /// снова, вместо того чтобы ждать сутки после ошибки.
    static let refreshedAtKey = "secrets.catalogRefreshedAt"

    private let transport: SecretsTransport
    private let fallback: SecretCatalog
    private let defaults: UserDefaults
    private let fileURL: URL

    private let lock = NSLock()
    private var cached: Cache?

    /// То, что лежит на диске. `version` — ключ следующего разговора с
    /// сервером, и без него кэш бесполезен: пришлось бы качать список целиком
    /// каждые сутки.
    struct Cache: Codable {
        let version: String
        let salt: String
        let secrets: [SecretRecord]
    }

    init(transport: SecretsTransport? = nil,
         fallback: SecretCatalog = BundleSecretCatalog.shared,
         defaults: UserDefaults = .standard,
         fileURL: URL = CachedSecretCatalog.defaultFileURL()) {
        self.transport = transport ?? SecretsAPI()
        self.fallback = fallback
        self.defaults = defaults
        self.fileURL = fileURL
        cached = Self.read(fileURL)
    }

    // MARK: - SecretCatalog

    /// Соль СВОЕГО списка. Отдать серверную соль с бандловым списком (или
    /// наоборот) значило бы считать хеши не тем ключом — то есть не найти
    /// ничего и никогда, молча.
    var salt: String {
        lock.lock(); defer { lock.unlock() }
        return usable(cached)?.salt ?? fallback.salt
    }

    func all() -> [SecretRecord] {
        lock.lock(); defer { lock.unlock() }
        return usable(cached)?.secrets ?? fallback.all()
    }

    /// Пустой кэш — это НЕ каталог: список секретов пустеть не умеет (секреты
    /// выключают поштучно, а не набором), поэтому пустой ответ читается как
    /// «сервер волны 5 ещё не наполнен» и уступает бандлу.
    private func usable(_ cache: Cache?) -> Cache? {
        guard let cache, !cache.secrets.isEmpty else { return nil }
        return cache
    }

    /// Версия, известная этому телефону. `nil` — «не спрашивали ни разу».
    var version: String? {
        lock.lock(); defer { lock.unlock() }
        return cached?.version
    }

    // MARK: - Обновление

    /// Спросить сервер, если с прошлого раза прошли сутки.
    ///
    /// Возвращает, ходили ли в сеть, — читает тест: «раз в сутки» проверяется
    /// именно отсутствием второго запроса, а не тем, что список не изменился.
    @discardableResult
    func refreshIfNeeded(now: Date = Date()) async -> Bool {
        let last = defaults.object(forKey: Self.refreshedAtKey) as? Date
        if let last, now.timeIntervalSince(last) < Self.refreshInterval, cached != nil {
            return false
        }
        await refresh(now: now)
        return true
    }

    /// Спросить сервер прямо сейчас.
    ///
    /// Ошибка сети — не событие: кэш (или бандл) остаётся тем же, дата
    /// последнего обращения не двигается, и следующий запуск попробует снова.
    func refresh(now: Date = Date()) async {
        let known = version
        do {
            let response = try await transport.catalog(version: known)
            if response.isUnchanged {
                defaults.set(now, forKey: Self.refreshedAtKey)
                return
            }
            guard let salt = response.salt, let secrets = response.secrets else {
                catalogLog.error("catalog reply without salt/secrets — ignored")
                return
            }
            let cache = Cache(version: response.version, salt: salt, secrets: secrets)
            lock.lock()
            cached = cache
            lock.unlock()
            write(cache)
            defaults.set(now, forKey: Self.refreshedAtKey)
            catalogLog.notice("catalog updated: \(secrets.count, privacy: .public) secrets")
        } catch {
            catalogLog.notice("catalog refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Стирание аккаунта. Каталог не личные данные, но и хранить его после
    /// «удалить безвозвратно» незачем: он вернётся первым же обновлением, а
    /// файл, переживший вайп, выглядит как то, чего не стёрли.
    func wipe() {
        lock.lock()
        cached = nil
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
        defaults.removeObject(forKey: Self.refreshedAtKey)
    }

    // MARK: - Диск

    /// Application Support, а не Documents: каталог — производное от сервера,
    /// человеку его не показывают и в резервную копию тащить незачем.
    static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Secrets", isDirectory: true)
            .appendingPathComponent("catalog.json")
    }

    private static func read(_ url: URL) -> Cache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func write(_ cache: Cache) {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: fileURL, options: .atomic)
        } catch {
            catalogLog.error("catalog cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
