import Foundation
import OSLog

private let attachLog = Logger(subsystem: "com.triptrack", category: "plus")

/// Привязка покупки к аккаунту: подписанная транзакция уезжает на
/// `POST /plus/attach` и повторяется, пока не доедет.
///
/// **Почему своя очередь, а не `SyncQueue`.** Та везёт СУЩНОСТИ базы —
/// поездку, машину, путешествие, находку — и повторяет их по id, поднимая
/// строку из CoreData. У привязки нет строки: её предмет — подпись Apple,
/// которая живёт в `Transaction`, а не у нас, и завести ради неё шестой тип
/// операции значило бы научить очередь доставать то, чего в базе нет. Правило
/// повтора при этом одно и то же, и записано оно здесь словами: сеть и пятисотые
/// — повторить с откатом; четырёхсотые (кроме таймаута и троттлинга) — уронить,
/// потому что завтра сервер ответит ровно то же.
///
/// **Человеку это НИКОГДА не видно.** Источник правды для гейтов на телефоне —
/// StoreKit (`PlusStore`), и он работает офлайн; привязка нужна чужим глазам
/// (профиль, лента) и второму телефону. Поэтому её отказ не гасит покупку, не
/// красит строку и не показывает ошибку — он просто откладывается.
///
/// **Одна транзакция уезжает ровно один раз.** Ключ дедупликации —
/// `originalID` транзакции: `Transaction.updates` переигрывает одну и ту же
/// покупку на каждом запуске, пока она не `finish()`, а продление приезжает
/// своей транзакцией с тем же `originalID` — сервер всё равно ведёт строку по
/// нему (спека §4), и второй POST с тем же ключом ничего не добавляет.
@MainActor
final class PlusAttachQueue {
    static let shared = PlusAttachQueue()

    /// Ждут отправки: ключ (`originalID`) → подпись.
    private(set) var pending: [(key: String, jws: String)] = []
    /// Уже принятые сервером ключи. Ограничены хвостом: список растёт на
    /// продление, то есть раз в месяц, и держать его целиком незачем.
    private(set) var sent: [String] = []

    private let transport: PlusTransport
    /// Гейт замыканием, а не чтением флага: тест обязан уметь задать ответ, не
    /// заводя сессии. Без аккаунта привязывать покупку НЕ к чему — сервер
    /// знает подписку по аккаунту (спека §4), — поэтому очередь копится и
    /// разбирается на первом же входе.
    private let isAllowed: @MainActor () -> Bool
    private let defaults: UserDefaults
    /// Тест-шов: настоящий откат — секунды, и ждать их в прогоне нечем.
    private let backoff: @Sendable (Int) async -> Void
    private var draining = false

    private static let pendingKey = "plus.attach.pending"
    private static let sentKey = "plus.attach.sent"
    private static let sentCap = 40
    /// Пять попыток подряд, дальше — до следующего запуска или возвращения в
    /// приложение. Столько же, сколько у `SyncQueue`.
    static let maxAttempts = 5

    init(transport: PlusTransport = PlusAPI(),
         isAllowed: @escaping @MainActor () -> Bool = { AuthService.shared.isSignedIn },
         defaults: UserDefaults = .standard,
         backoff: @escaping @Sendable (Int) async -> Void = { attempt in
             let seconds = min(pow(2.0, Double(attempt)), 32)
             try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
         }) {
        self.transport = transport
        self.isAllowed = isAllowed
        self.defaults = defaults
        self.backoff = backoff
        pending = Self.loadPending(defaults)
        sent = defaults.stringArray(forKey: Self.sentKey) ?? []
    }

    /// Поставить транзакцию в очередь и попробовать отправить сейчас.
    ///
    /// Зовётся с каждой ПРОВЕРЕННОЙ транзакции — и из `purchase`, и из
    /// `Transaction.updates`, и с `currentEntitlements` на старте. Все три
    /// дороги ведут к одной покупке, и дедупликация по ключу — единственное,
    /// что мешает им троить запрос.
    func enqueue(key: String, jws: String) {
        guard !sent.contains(key) else { return }
        guard !pending.contains(where: { $0.key == key }) else { return }
        pending.append((key, jws))
        savePending()
        Task { await drain() }
    }

    /// Разобрать очередь. Идемпотентно: второй заход при идущем первом выходит
    /// сразу — то же правило, что у `PlaceManager.reconcile`.
    func drain() async {
        guard isAllowed() else { return }
        guard !draining, !pending.isEmpty else { return }
        draining = true
        defer { draining = false }

        while let item = pending.first {
            var delivered = false
            for attempt in 0..<Self.maxAttempts {
                do {
                    _ = try await transport.attach(signedTransaction: item.jws)
                    delivered = true
                    break
                } catch {
                    if Self.isPermanent(error) {
                        attachLog.notice("""
                            attach rejected for \(item.key.prefix(8), privacy: .public): \
                            \(Self.reason(error), privacy: .public) — dropped
                            """)
                        delivered = true   // роняем так же, как доставленное
                        break
                    }
                    guard attempt + 1 < Self.maxAttempts else { break }
                    await backoff(attempt)
                }
            }
            guard delivered else {
                // Сеть не поднялась за пять попыток — оставляем в очереди до
                // следующего запуска. Человеку про это знать нечего.
                attachLog.notice("attach deferred for \(item.key.prefix(8), privacy: .public)")
                return
            }
            pending.removeFirst()
            remember(key: item.key)
            savePending()
        }
    }

    // MARK: - Правила

    /// Отказ, который повтор не вылечит. Та же развилка, что у
    /// `DiscoveryReveal.isPermanent`: пятисотые — икота сервера, четырёхсотые —
    /// «наш запрос не годится». Таймаут и троттлинг исключены нарочно: они как
    /// раз про «попробуй позже».
    static func isPermanent(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .validationFailed:
            return true
        case .unknownServer(let code, _):
            // 409 у чужой подписки — ответ навсегда: транзакция принадлежит
            // другому аккаунту, и повтор вернёт тот же код (спека §4).
            return code == "PLUS_BELONGS_TO_ANOTHER"
        case .invalidHTTPStatus(let status):
            return (400..<500).contains(status) && status != 408 && status != 429
        default:
            return false
        }
    }

    /// В лог уезжает КОД, а не `localizedDescription`: в том едет текст
    /// сервера — тот же класс данных, что чистит `PIIScrubber`.
    static func reason(_ error: Error) -> String {
        guard let api = error as? APIError else { return "transport" }
        switch api {
        case .unknownServer(let code, _):    return code
        case .validationFailed:              return "VALIDATION_FAILED"
        case .invalidHTTPStatus(let status): return "HTTP \(status)"
        default:                             return "\(api)"
        }
    }

    // MARK: - Диск

    private func remember(key: String) {
        sent.append(key)
        if sent.count > Self.sentCap { sent.removeFirst(sent.count - Self.sentCap) }
        defaults.set(sent, forKey: Self.sentKey)
    }

    private func savePending() {
        let rows = pending.map { [$0.key, $0.jws] }
        defaults.set(rows, forKey: Self.pendingKey)
    }

    private static func loadPending(_ defaults: UserDefaults) -> [(key: String, jws: String)] {
        guard let rows = defaults.array(forKey: pendingKey) as? [[String]] else { return [] }
        return rows.compactMap { row in
            guard row.count == 2 else { return nil }
            return (row[0], row[1])
        }
    }
}
