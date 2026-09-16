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
        let response = try await transport.reveal(request(for: item, tripId: item.tripId))
        await store.apply(reveal: response)
    }

    // MARK: - Внутри

    private func reveal(_ item: Discovery, tripId: UUID?) async {
        do {
            let response = try await transport.reveal(
                request(for: item, tripId: tripId ?? item.tripId))
            await store.apply(reveal: response)
        } catch {
            revealLog.notice("""
                reveal failed for \(item.key, privacy: .public): \
                \(error.localizedDescription, privacy: .public) — queued
                """)
            enqueue(SyncOperation(entityType: .discovery, entityId: item.id, action: .upload))
        }
    }

    private func request(for item: Discovery, tripId: UUID?) -> SecretRevealRequest {
        SecretRevealRequest(id: item.key, kind: item.kind.rawValue, tripId: tripId)
    }
}
