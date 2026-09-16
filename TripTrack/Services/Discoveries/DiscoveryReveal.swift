import Foundation
import OSLog

private let revealLog = Logger(subsystem: "com.triptrack", category: "discoveries")

/// Раскрытие находки: спросить сервер про то, чего на телефоне нет и быть не
/// может — историю секрета, счётчик нашедших, первооткрывателя, редкость.
///
/// **Только при включённом Cloud Sync и только со своим аккаунтом.** Заявка
/// «я нашёл это» — личные данные: она говорит, где человек был и когда.
/// Правило проекта здесь ровно то же, что у машины и путешествия: без облака с
/// телефона не уезжает ничего, и находка тогда живёт печатью на своей карте, без
/// «нашли 7 человек». Поэтому гейт стоит ДО первого запроса, а не внутри
/// транспорта.
///
/// **Зовётся после финиша**, из той же цепочки, что и разбор трека: `process`
/// сложил новые находки — `reveal` спрашивает про них. Вехи не спрашиваются
/// никогда: это собственная география, сервер про неё не знает и знать не
/// должен.
///
/// Сеть упала — находка не теряется: в очередь синка ложится
/// `.discovery/.upload` с id находки, и `APISyncTransport` повторит её тем же
/// механизмом, что поездки и машины. Ответ дописывается в базу
/// (`DiscoveryStore.apply(reveal:)`), а не подменяет находку: своё найденное
/// остаётся источником правды.
///
/// **Сервер ОТКАЗАЛ — находка в очередь НЕ ложится.** `SECRET_NOT_FOUND` и
/// любой другой 4xx-класс это ответ, который не изменится ни через минуту, ни
/// через сутки: повтор вернёт ровно то же, пять раз подряд, после чего строка
/// навсегда краснеет в `SyncStatusSheetView`, и снять её человек не может
/// ничем. Состояние достижимо на живых данных (сервер знает не все ключи
/// каталога), поэтому постоянный отказ логируется один раз и роняется — ровно
/// так же, как `retry` уже поступает с находкой, которой больше нет в базе.
@MainActor
final class DiscoveryReveal {
    static let shared = DiscoveryReveal()

    private let transport: SecretsTransport
    private let store: DiscoveryStore
    /// Гейт приватности замыканием, а не чтением флагов напрямую: тест обязан
    /// уметь задать оба ответа, не включая облако и не входя в аккаунт.
    private let isAllowed: @MainActor () -> Bool
    private let enqueue: @MainActor (SyncOperation) -> Void

    init(transport: SecretsTransport = SecretsAPI(),
         store: DiscoveryStore = .shared,
         isAllowed: @escaping @MainActor () -> Bool = {
             SettingsManager.shared.cloudSyncEnabled && AuthService.shared.isSignedIn
         },
         enqueue: @escaping @MainActor (SyncOperation) -> Void = { SyncEnqueuer.enqueue($0) }) {
        self.transport = transport
        self.store = store
        self.isAllowed = isAllowed
        self.enqueue = enqueue
    }

    /// Спросить сервер про каждую НОВУЮ находку поездки.
    ///
    /// `tripId` едет вместе с заявкой: им сервер подтверждает находку
    /// (`verified`), сверив свой экземпляр трека. Трека на сервере может не
    /// быть — тогда заявка засчитается неподтверждённой, и это нормально.
    func reveal(_ items: [Discovery], tripId: UUID?) async {
        guard isAllowed() else { return }
        for item in items where item.kind != .milestone {
            await reveal(item, tripId: tripId)
        }
    }

    /// Повтор из очереди синка: находка известна одним лишь id.
    ///
    /// Бросает, чтобы очередь повторила позже своим экспоненциальным
    /// откатом. Молчит (без броска) там, где повторять нечего: находки уже нет
    /// в базе (стёрли аккаунт), это веха или облако успели выключить — операция
    /// снимается, а не висит в очереди вечно.
    func retry(id: UUID) async throws {
        guard isAllowed() else { return }
        guard let item = await store.discovery(id: id), item.kind != .milestone else { return }
        do {
            let response = try await transport.reveal(request(for: item, tripId: item.tripId))
            await store.apply(reveal: response)
        } catch {
            // Постоянный отказ — выходим БЕЗ броска: `SyncQueue` снимает
            // операцию, вернувшуюся из `execute` молча, и парков-очередь не
            // копит строку, которую повторять нечем.
            guard !Self.isPermanent(error) else {
                revealLog.notice("""
                    reveal rejected for \(item.key, privacy: .public): \
                    \(Self.reason(error), privacy: .public) — dropped
                    """)
                return
            }
            throw error
        }
    }

    // MARK: - Постоянные отказы

    /// Коды сервера, после которых повторять нечего.
    ///
    /// `SECRET_NOT_FOUND` — главный: ключ секрета или загадки сервер не знает
    /// (каталоги на телефоне и на сервере разъезжаются по версиям), и завтра
    /// он его не узнает тоже.
    static let permanentCodes: Set<String> = [
        "SECRET_NOT_FOUND", "RIDDLE_NOT_FOUND", "DISCOVERY_NOT_FOUND",
    ]

    /// Отказ, который повтор не вылечит.
    ///
    /// Разделение 4xx/5xx здесь то же, что у `APIClient` в обновлении сессии:
    /// пять сотен — икота сервера (повторить), четыре сотни — «наш запрос не
    /// годится» (уронить). Таймаут и троттлинг из четырёхсотых исключены: они
    /// как раз про «попробуй позже».
    static func isPermanent(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .unknownServer(let code, _):
            return permanentCodes.contains(code)
        case .validationFailed, .tripNotFound, .photoNotFound, .userBanned:
            return true
        case .invalidHTTPStatus(let status):
            return (400..<500).contains(status) && status != 408 && status != 429
        default:
            return false
        }
    }

    /// Короткое описание отказа БЕЗ серверного текста.
    ///
    /// `error.localizedDescription` у `unknownServer` несёт сообщение СЕРВЕРА,
    /// а это тот же класс данных, который чистит `PIIScrubber` в отчётах
    /// Sentry. В лог уезжает код и ничего больше.
    static func reason(_ error: Error) -> String {
        if let url = error as? URLError { return "network \(url.code.rawValue)" }
        guard let api = error as? APIError else { return String(describing: type(of: error)) }
        switch api {
        case .unknownServer(let code, _):      return "server \(code)"
        case .invalidHTTPStatus(let status):   return "http \(status)"
        case .validationFailed:                return "validation"
        case .tripNotFound:                    return "trip not found"
        case .photoNotFound:                   return "photo not found"
        case .userBanned:                      return "banned"
        case .userNotAuth:                     return "not authorised"
        case .tooManyRequests:                 return "throttled"
        case .decoding:                        return "decoding"
        case .network(let url):                return "network \(url.code.rawValue)"
        default:                               return "transport"
        }
    }

    // MARK: - Внутри

    private func reveal(_ item: Discovery, tripId: UUID?) async {
        do {
            let response = try await transport.reveal(
                request(for: item, tripId: tripId ?? item.tripId))
            await store.apply(reveal: response)
        } catch {
            guard !Self.isPermanent(error) else {
                revealLog.notice("""
                    reveal rejected for \(item.key, privacy: .public): \
                    \(Self.reason(error), privacy: .public) — dropped
                    """)
                return
            }
            revealLog.notice("""
                reveal failed for \(item.key, privacy: .public): \
                \(Self.reason(error), privacy: .public) — queued
                """)
            enqueue(SyncOperation(entityType: .discovery, entityId: item.id, action: .upload))
        }
    }

    private func request(for item: Discovery, tripId: UUID?) -> SecretRevealRequest {
        SecretRevealRequest(id: item.key, kind: item.kind.rawValue, tripId: tripId)
    }
}
