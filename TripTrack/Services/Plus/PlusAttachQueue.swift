import Foundation
import OSLog

private let attachLog = Logger(subsystem: "com.triptrack", category: "plus")

/// Куда ложится САМА подпись Apple.
///
/// Отдельный тип, потому что мест хранения два и различие между ними —
/// безопасность, а не вкус: бухгалтерия очереди (ключи, попытки, время
/// следующей попытки) живёт в `UserDefaults`, а подписанная транзакция — в
/// Keychain. `UserDefaults` — обычный plist в песочнице, без класса защиты
/// данных: он уезжает в НЕЗАШИФРОВАННУЮ резервную копию и читается на
/// джейле, а внутри JWS открытым текстом лежат `originalTransactionId`,
/// `productId`, даты и `appAccountToken` (= id нашего аккаунта).
protocol PlusJWSVault {
    func read() -> [String: String]
    func write(_ rows: [String: String])
}

/// Боевое хранилище: один JSON-словарь «ключ → подпись» под
/// `AfterFirstUnlockThisDeviceOnly`, как токены сессии.
struct KeychainJWSVault: PlusJWSVault {
    static let key = "plus.attach.jws.v1"

    func read() -> [String: String] {
        guard let data = KeychainHelper.load(key: Self.key),
              let rows = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return rows
    }

    func write(_ rows: [String: String]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? KeychainHelper.save(data, for: Self.key)
    }
}

/// Привязка покупки к аккаунту: подписанная транзакция уезжает на
/// `POST /plus/attach` и повторяется, пока не доедет.
///
/// **Почему своя очередь, а не `SyncQueue`.** Та везёт СУЩНОСТИ базы —
/// поездку, машину, путешествие, находку — и повторяет их по id, поднимая
/// строку из CoreData. У привязки нет строки: её предмет — подпись Apple,
/// которая живёт в `Transaction`, а не у нас, и завести ради неё шестой тип
/// операции значило бы научить очередь доставать то, чего в базе нет.
///
/// **Человеку это НИКОГДА не видно.** Источник правды для гейтов на телефоне
/// — StoreKit (`PlusStore`), и он работает офлайн; привязка нужна чужим
/// глазам (профиль, лента) и второму телефону. Поэтому её отказ не гасит
/// покупку, не красит строку и не показывает ошибку — он просто
/// откладывается.
///
/// **Ключ дедупликации — `transaction.id`, а не `originalID`.** У всех
/// продлений одной подписки `originalID` одинаков: по нему сервер получал бы
/// ровно ОДНУ подпись за всю жизнь подписки — ту, чей `expiresDate` кончается
/// через год. Сервер апсертит строку по `originalTransactionId`, так что
/// лишний POST раз в период не стоит ничего, а пропущенный стоит подписки.
///
/// **Отказ никогда не закрывает дорогу навсегда.** Раньше любой 4xx (включая
/// 404 «маршрут ещё не выкачен» и 401 с протухшим токеном) снимал заявку и
/// клал её ключ в `sent`, откуда `enqueue` больше не выпускал: деньги
/// списаны, сервер о подписке не знает никогда, лечится только переустановкой.
/// Теперь развилка такая:
///
///  - **сеть, 5xx, 404/410, 408/429, 401/403** — ОТКЛАДЫВАЕМ. Это про
///    инфраструктуру и момент времени, а не про тело запроса; повтор
///    экспоненциальный, с потолком в сутки, и переживает перезапуск.
///  - **400/409/422 и `validationFailed`** — отказ по СМЫСЛУ: сервер понял
///    запрос и не принял его. Заявка остаётся в очереди, но помечается
///    сборкой, которой отказали, и не повторяется ДО следующего обновления
///    приложения: новая сборка шлёт другой запрос, и молча хоронить
///    оплаченную подписку из-за вчерашней ошибки нельзя. Но не вечно: после
///    ТРЁХ разных сборок заявка выбрасывается совсем, вместе с подписью в
///    Keychain. Чаще всего это `PLUS_BELONGS_TO_ANOTHER` — чужая подписка, и
///    держать её подписанный чек у себя годами незачем.
///
/// **Очередь ограничена по длине** (`maxPending`). Настоящих заявок там
/// одна-две; полсотни означают, что что-то их плодит, и расти списку
/// подписанных чеков дальше нельзя — выбрасывается самая старая, со строкой
/// в логе.
@MainActor
final class PlusAttachQueue {
    static let shared = PlusAttachQueue()

    /// Одна заявка на привязку.
    struct Item: Equatable {
        /// `transaction.id` — уникален у каждого продления.
        let key: String
        let jws: String
        /// Сколько раз подряд не доехало по транзиентной причине.
        var attempts: Int = 0
        /// Раньше этого времени не пробовать (экспоненциальный откат).
        var notBefore: Date?
        /// Сборки, которым сервер отказал ПО СМЫСЛУ. Пока текущая среди них —
        /// заявка спит; обновление приложения будит её РОВНО ОДИН раз, и не
        /// больше трёх раз всего (`maxRejections`).
        ///
        /// Список, а не одна строка: «повторить после обновления» без счётчика
        /// означало «повторять после КАЖДОГО обновления вечно», и чужая
        /// подписка (`PLUS_BELONGS_TO_ANOTHER`) навсегда осталась бы и в
        /// очереди, и — что хуже — подписью в Keychain.
        var rejectedBuilds: [String] = []
    }

    /// Ждут отправки.
    private(set) var pending: [Item] = []
    /// Уже принятые сервером ключи.
    private(set) var sent: [String] = []

    private let transport: PlusTransport
    /// Гейт замыканием, а не чтением флага: тест обязан уметь задать ответ, не
    /// заводя сессии. Без аккаунта привязывать покупку НЕ к чему — сервер
    /// знает подписку по аккаунту (спека §4), — поэтому очередь копится и
    /// разбирается на первом же входе.
    private let isAllowed: @MainActor () -> Bool
    private let defaults: UserDefaults
    private let vault: PlusJWSVault
    /// Номер сборки. Параметром, а не чтением бандла: в прогоне тестов
    /// `Bundle.main` — это раннер xctest, и «обновление приложения» надо
    /// уметь разыграть.
    private let build: String
    /// Тест-шов: настоящий откат — секунды, и ждать их в прогоне нечем.
    private let backoff: @Sendable (Int) async -> Void
    /// Часы. Тоже шов: откат между заходами измеряется в минутах и часах, а
    /// прогон столько не живёт.
    private let now: @Sendable () -> Date
    private var draining = false

    /// Ключи с ВЕРСИЕЙ формата. Без неё смена формы строки прошла бы молча:
    /// `loadPending` отбрасывает всё, что не подходит, и очередь просто
    /// оказалась бы пустой — то есть непривязанные покупки исчезли бы без
    /// единой строки в логе. Меняешь форму — заводи следующую версию и решай
    /// судьбу прежней явно.
    private static let pendingKeyV1 = "plus.attach.pending.v1"
    private static let pendingKey = "plus.attach.pending.v2"
    private static let sentKey = "plus.attach.sent.v1"
    /// Ключей теперь по одному на ПРОДЛЕНИЕ, а не на подписку, поэтому
    /// крышка поднята. Выпавший из-под неё ключ не теряет ничего: он стоит
    /// одного лишнего POST, который сервер схлопнет по
    /// `originalTransactionId`.
    private static let sentCap = 200
    /// Пять попыток подряд, дальше — откат до следующего раза. Столько же,
    /// сколько у `SyncQueue`.
    static let maxAttempts = 5
    /// Потолок отката между заходами — сутки. Дальше растить бессмысленно:
    /// приложение всё равно дренирует очередь на каждом запуске и входе.
    static let maxRetryDelay: TimeInterval = 24 * 3600
    /// Отказы по смыслу: сервер понял запрос и не принял его.
    static let semanticRejections: Set<Int> = [400, 409, 422]
    /// Сколько РАЗНЫХ сборок могут получить отказ по смыслу, прежде чем
    /// заявку выбросят вместе с подписью.
    static let maxRejections = 3
    /// Потолок очереди. Заявок здесь бывает одна-две; полсотни — это уже не
    /// очередь, а накопитель чужих платёжных документов.
    static let maxPending = 50

    init(transport: PlusTransport = PlusAPI(),
         isAllowed: @escaping @MainActor () -> Bool = { AuthService.shared.isSignedIn },
         defaults: UserDefaults = .standard,
         vault: PlusJWSVault = KeychainJWSVault(),
         build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
         backoff: @escaping @Sendable (Int) async -> Void = { attempt in
             let seconds = min(pow(2.0, Double(attempt)), 32)
             try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
         },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.isAllowed = isAllowed
        self.defaults = defaults
        self.vault = vault
        self.build = build
        self.backoff = backoff
        self.now = now
        let loaded = Self.loadPending(defaults, vault: vault)
        pending = loaded.items
        sent = defaults.stringArray(forKey: Self.sentKey) ?? []
        if loaded.orphaned > 0 {
            // Бухгалтерия лежит в общих `UserDefaults`, а подпись — в Keychain,
            // ИМЯ СЕРВИСА которого собрано из bundle id и ХОСТА API
            // (`KeychainHelper.composeService`). Переезд между локальным
            // бэкендом и продом внутри одной сборки меняет второе и не меняет
            // первое: строки остаются, подписей к ним больше нет. Чистим их
            // здесь, чтобы очередь не таскала вечно пустые заявки, и говорим
            // об этом одной строкой — без единого идентификатора.
            attachLog.notice(
                "plus.attach.host_changed pending=\(loaded.orphaned, privacy: .public)")
            savePending()
        }
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
        pending.append(Item(key: key, jws: jws))
        while pending.count > Self.maxPending {
            let dropped = pending.removeFirst()
            attachLog.notice("""
                attach queue full — dropping \(dropped.key.suffix(8), privacy: .public)
                """)
        }
        savePending()
        Task { await drain() }
    }

    /// Чем кончилась одна заявка в этом заходе.
    private enum Outcome {
        case delivered
        case rejected(String)
        case deferred
    }

    /// Разобрать очередь. Идемпотентно: второй заход при идущем первом
    /// выходит сразу — то же правило, что у `PlaceManager.reconcile`.
    func drain() async {
        guard isAllowed() else { return }
        guard !draining, !pending.isEmpty else { return }
        draining = true
        defer { draining = false }

        var index = 0
        while index < pending.count {
            let item = pending[index]
            if let notBefore = item.notBefore, notBefore > now() { index += 1; continue }
            if item.rejectedBuilds.contains(build) { index += 1; continue }

            var outcome = Outcome.deferred
            for attempt in 0..<Self.maxAttempts {
                do {
                    _ = try await transport.attach(signedTransaction: item.jws)
                    outcome = .delivered
                    break
                } catch {
                    if Self.isPermanent(error) {
                        outcome = .rejected(Self.reason(error))
                        break
                    }
                    guard attempt + 1 < Self.maxAttempts else { break }
                    await backoff(attempt)
                }
            }

            // Заявку могли снять, пока мы ждали сеть (дренаж — не атомарный
            // шаг), поэтому ищем её по ключу, а не по индексу.
            guard let slot = pending.firstIndex(where: { $0.key == item.key }) else {
                index = 0
                continue
            }

            switch outcome {
            case .delivered:
                pending.remove(at: slot)
                remember(key: item.key)
                savePending()

            case .rejected(let reason):
                pending[slot].rejectedBuilds.append(build)
                pending[slot].notBefore = nil
                if pending[slot].rejectedBuilds.count >= Self.maxRejections {
                    attachLog.notice("""
                        attach rejected for \(item.key.suffix(8), privacy: .public): \
                        \(reason, privacy: .public) — given up after \
                        \(Self.maxRejections, privacy: .public) builds
                        """)
                    pending.remove(at: slot)
                    savePending()   // и подпись уходит из Keychain вместе с заявкой
                    index = slot
                } else {
                    attachLog.notice("""
                        attach rejected for \(item.key.suffix(8), privacy: .public): \
                        \(reason, privacy: .public) — sleeping until the next build
                        """)
                    savePending()
                    index = slot + 1
                }

            case .deferred:
                // Сеть не поднялась за пять попыток. Останавливаем ВЕСЬ заход:
                // за остальными заявками стоит та же сеть, и долбить её ими
                // подряд значит потратить батарею на тот же ответ.
                pending[slot].attempts += 1
                pending[slot].notBefore = now()
                    .addingTimeInterval(Self.retryDelay(attempt: pending[slot].attempts))
                savePending()
                attachLog.notice("attach deferred for \(item.key.suffix(8), privacy: .public)")
                return
            }
        }
    }

    // MARK: - Правила

    /// Через сколько пробовать снова после транзиентного отказа. Растёт
    /// вдвое от минуты и упирается в сутки.
    static func retryDelay(attempt: Int) -> TimeInterval {
        let minutes = pow(2.0, Double(max(0, attempt - 1)))
        return min(60 * minutes, maxRetryDelay)
    }

    /// Отказ ПО СМЫСЛУ: сервер понял запрос и не принял его. Такой ответ не
    /// изменится ни через минуту, ни через сутки — но изменится со сборкой,
    /// поэтому «навсегда» здесь означает «до следующего обновления».
    ///
    /// Голые 4xx сюда НЕ входят, и это главное отличие от прежней версии:
    /// 404 — «маршрут ещё не выкачен», 410 — «маршрут убрали», 401/403 —
    /// «токен ещё не обновился». Каждый из них однажды случится в окне
    /// раскатки, и каждый из них раньше хоронил оплаченную подписку.
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
            return semanticRejections.contains(status)
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

    /// Бухгалтерия — в `UserDefaults`, подписи — в Keychain. Разделение и
    /// есть смысл этой функции.
    private func savePending() {
        let rows: [[String: Any]] = pending.map { item in
            var row: [String: Any] = ["k": item.key, "a": item.attempts]
            if let notBefore = item.notBefore { row["n"] = notBefore.timeIntervalSince1970 }
            if !item.rejectedBuilds.isEmpty { row["b"] = item.rejectedBuilds }
            return row
        }
        defaults.set(rows, forKey: Self.pendingKey)
        defaults.removeObject(forKey: Self.pendingKeyV1)
        vault.write(Dictionary(pending.map { ($0.key, $0.jws) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Заявки и СКОЛЬКО строк бухгалтерии осталось без подписи: второе —
    /// признак того, что Keychain отвечает по другому имени сервиса (сменился
    /// хост API), и его надо не проглотить, а сказать вслух.
    private static func loadPending(
        _ defaults: UserDefaults, vault: PlusJWSVault
    ) -> (items: [Item], orphaned: Int) {
        let signatures = vault.read()
        if let rows = defaults.array(forKey: pendingKey) as? [[String: Any]] {
            var items: [Item] = []
            var orphaned = 0
            for row in rows {
                guard let key = row["k"] as? String else { continue }
                guard let jws = signatures[key] else { orphaned += 1; continue }
                // `b` был строкой до этой волны — читаем оба написания, иначе
                // заявка, отвергнутая прежней сборкой, проснулась бы заново.
                let rejected: [String]
                if let list = row["b"] as? [String] { rejected = list }
                else if let one = row["b"] as? String { rejected = [one] }
                else { rejected = [] }
                items.append(Item(
                    key: key,
                    jws: jws,
                    attempts: row["a"] as? Int ?? 0,
                    notBefore: (row["n"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)),
                    rejectedBuilds: rejected))
            }
            return (items, orphaned)
        }
        // Формат 0.8.0-beta: пары `[ключ, подпись]` прямо в `UserDefaults`.
        // Подхватываем и переносим подпись в Keychain при первом сохранении;
        // старый ключ стирает `savePending`.
        guard let legacy = defaults.array(forKey: pendingKeyV1) as? [[String]] else {
            return ([], 0)
        }
        let items = legacy.compactMap { row -> Item? in
            guard row.count == 2 else { return nil }
            return Item(key: row[0], jws: row[1])
        }
        return (items, 0)
    }
}
