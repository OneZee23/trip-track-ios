import Foundation
import OSLog

private let remoteConfigLog = Logger(subsystem: "com.triptrack", category: "remoteconfig")

/// Ответ `GET /app/config`.
struct RemoteConfigResponse: Decodable {
    let version: String
    let unchanged: Bool?
    let config: RemoteConfig?
}

protocol RemoteConfigTransport: Sendable {
    func config(version: String?) async throws -> RemoteConfigResponse
}

struct RemoteConfigAPI: RemoteConfigTransport {
    /// Публичный маршрут: конфигурация нужна до всякого входа.
    func config(version: String?) async throws -> RemoteConfigResponse {
        let client = await MainActor.run { APIClient.shared }
        return try await client.get(APIEndpoint.appConfig(version: version), requiresAuth: false)
    }
}

/// Хранилище удалённой конфигурации (0.9.0) — та же схема, что у
/// `CachedSecretCatalog`: ответ сервера + версия + кэш на диске, и ни одно из
/// состояний не оставляет приложение без значений. Нет сети и нет кэша —
/// действует то, что вшито в приложение, то есть ровно поведение до 0.9.0.
///
/// Читается синхронно и с любого потока (`flag(_:)` зовут в том числе вне
/// главного актёра — у Metal-тумана), поэтому состояние под `NSLock`, а
/// `@Published` — только для экранов, на главном актёре.
final class RemoteConfigStore: ObservableObject, @unchecked Sendable {
    static let shared = RemoteConfigStore()

    /// Не чаще раза в шесть часов: выключатель обязан доходить быстрее
    /// суток, а молотить сервер на каждом возврате в приложение незачем.
    static let refreshInterval: TimeInterval = 6 * 60 * 60
    static let refreshedAtKey = "remoteConfig.refreshedAt"

    private let transport: RemoteConfigTransport
    private let defaults: UserDefaults
    private let fileURL: URL
    private let lock = NSLock()
    private var cached: Cache?

    /// Для экранов: меняется, когда приехала новая конфигурация.
    @MainActor @Published private(set) var config = RemoteConfig()

    struct Cache: Codable {
        let version: String
        let config: RemoteConfig
    }

    init(transport: RemoteConfigTransport = RemoteConfigAPI(),
         defaults: UserDefaults = .standard,
         fileURL: URL = RemoteConfigStore.defaultFileURL()) {
        self.transport = transport
        self.defaults = defaults
        self.fileURL = fileURL
        cached = Self.read(fileURL)
        if let cached {
            let snapshot = cached.config
            Task { @MainActor [weak self] in self?.config = snapshot }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// Значение флага с сервера, или `nil` — «сервер про него молчит», и
    /// тогда действует вшитое значение.
    func flag(_ name: String) -> Bool? {
        withLock { cached?.config.flags[name] }
    }

    var version: String? { withLock { cached?.version } }

    // MARK: - Обновление

    @discardableResult
    func refreshIfNeeded(now: Date = Date()) async -> Bool {
        let last = defaults.object(forKey: Self.refreshedAtKey) as? Date
        if let last, now.timeIntervalSince(last) < Self.refreshInterval, version != nil { return false }
        await refresh(now: now)
        return true
    }

    /// Ошибка сети или старый сервер без маршрута — не событие: остаётся то,
    /// что было, дата не двигается, следующий запуск попробует снова.
    func refresh(now: Date = Date()) async {
        do {
            let response = try await transport.config(version: version)
            if response.unchanged == true {
                defaults.set(now, forKey: Self.refreshedAtKey)
                return
            }
            guard let config = response.config else { return }
            let cache = Cache(version: response.version, config: config)
            withLock { cached = cache }
            write(cache)
            defaults.set(now, forKey: Self.refreshedAtKey)
            await MainActor.run { self.config = config }
            remoteConfigLog.notice("config updated: \(config.flags.count, privacy: .public) flags, \(config.announcements.count, privacy: .public) announcements")
        } catch {
            remoteConfigLog.notice("config refresh skipped: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    // MARK: - Диск

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("remote-config.json")
    }

    private static func read(_ url: URL) -> Cache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(Cache.self, from: data)
    }

    private func write(_ cache: Cache) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Self.encoder.encode(cache).write(to: fileURL, options: .atomic)
        } catch {
            remoteConfigLog.error("config cache write failed")
        }
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
