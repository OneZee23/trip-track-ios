import Foundation
import StoreKit
import OSLog
import Combine

private let plusLog = Logger(subsystem: "com.triptrack", category: "plus")

/// «Плюс» на этом телефоне: что куплено, что продаётся и что показывать.
///
/// **Источник правды для ГЕЙТОВ — StoreKit, а не сервер.** `currentEntitlements`
/// отвечает офлайн, в самолёте и на втором телефоне того же Apple ID; сервер
/// отвечает, только когда есть сеть и аккаунт. Поэтому косметика и ручная
/// поездка открываются по `PlusAccess.shared.isPlus`, который пишет сюда этот
/// класс, а `POST /plus/attach` уходит отдельной дорогой
/// (`PlusAttachQueue`) — он нужен ЧУЖИМ глазам: профилю, ленте, гаражу.
///
/// **Слушатель `Transaction.updates` живёт всё время работы приложения.** Не
/// «пока открыт пейвол»: покупка бывает отложенной (Ask To Buy), продление
/// приезжает само, а возврат денег приезжает уведомлением, которого никто не
/// ждёт. Стоит его пропустить — и транзакция переигрывается на каждом запуске,
/// что выглядит ровно как баг StoreKit и им не является (то же решение, что в
/// `TipJarService`).
///
/// **Непроверенная транзакция игнорируется.** `.unverified` — это подпись,
/// которая не сошлась; принять её значит открыть платное по подделке. Она не
/// `finish()`-ится нарочно: незакрытая приедет снова и останется видимой в
/// логе, а закрытая молча исчезнет.
@MainActor
final class PlusStore: ObservableObject {
    static let shared = PlusStore()

    /// Состояние подписки. `rawValue` — только для лога и тестов: в базу оно
    /// не ложится и на провод не уезжает.
    enum State: String, Equatable {
        /// Никогда не покупал.
        case none
        /// Идут семь бесплатных дней.
        case trial
        /// Оплаченный период.
        case active
        /// Оплата не прошла, но Apple ещё пытается (grace / billing retry).
        /// «Плюс» при этом РАБОТАЕТ: человек ничего не нарушил, а карта
        /// протухает на три дня раз в два года.
        case grace
        /// Был и кончился.
        case expired
    }

    /// Пересказ `Product.SubscriptionInfo.RenewalState` своими словами.
    ///
    /// Свой тип, потому что правило «что считать плюсом» обязано проверяться
    /// таблицей, без StoreKit и без покупки: собрать `RenewalState` в тесте
    /// нечем, а перечислить пять случаев — можно.
    enum RenewalSummary: Equatable {
        case subscribed
        case inGracePeriod
        case inBillingRetryPeriod
        case expired
        case revoked
    }

    static let yearlyID = "com.onezee.TripTrack.plus.yearly"
    static let monthlyID = "com.onezee.TripTrack.plus.monthly"
    /// Порядок значим: годовой первый и в пейволе, и в выборке продуктов.
    static let productIDs = [yearlyID, monthlyID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var state: State = .none
    /// До какого числа «Плюс». `nil` — не куплено или Apple не сказала.
    @Published private(set) var expiresAt: Date?
    /// Идёт покупка или восстановление — кнопки на пейволе выключены.
    @Published private(set) var isBusy = false
    /// Двухбуквенно-трёхбуквенный код витрины (`RUS`, `GEO`, `USA`).
    @Published private(set) var storefrontCountry: String?

    var isPlus: Bool { Self.grants(state) }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var monthly: Product? { products.first { $0.id == Self.monthlyID } }

    private var updatesTask: Task<Void, Never>?
    private var storefrontTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    // MARK: - Чистые правила

    /// Даёт ли состояние доступ к платному.
    nonisolated static func grants(_ state: State) -> Bool {
        state == .trial || state == .active || state == .grace
    }

    /// Витрина, которая платного не показывает. Решение владельца 19 сентября:
    /// в РФ платежи App Store мертвы с 1 апреля 2026, и пейвол там — это
    /// кнопка, которая не может сработать.
    nonisolated static func hidesPlus(countryCode: String?) -> Bool {
        countryCode == "RUS"
    }

    /// Состояние из того, что сказал StoreKit.
    ///
    /// Порядок проверок — это и есть правило, и переставить его нельзя:
    /// грейс проверяется ПЕРВЫМ, потому что `currentEntitlements` при
    /// billing retry права уже не отдаёт, а «Плюс» обязан работать — иначе
    /// сорвавшийся платёж отбирает у человека купленное на те несколько дней,
    /// пока Apple пробует карту ещё раз.
    nonisolated static func resolve(
        entitled: Bool,
        isTrial: Bool,
        renewal: RenewalSummary?
    ) -> State {
        if renewal == .inGracePeriod || renewal == .inBillingRetryPeriod { return .grace }
        if entitled { return isTrial ? .trial : .active }
        if renewal == .expired || renewal == .revoked { return .expired }
        return .none
    }

    /// `RenewalState` → наш пересказ. Самый «живой» статус группы побеждает:
    /// у человека, переехавшего с месячного на годовой, строк в группе две.
    nonisolated static func summarize(_ states: [Product.SubscriptionInfo.RenewalState]) -> RenewalSummary? {
        if states.contains(.inGracePeriod) { return .inGracePeriod }
        if states.contains(.inBillingRetryPeriod) { return .inBillingRetryPeriod }
        if states.contains(.subscribed) { return .subscribed }
        if states.contains(.revoked) { return .revoked }
        if states.contains(.expired) { return .expired }
        return nil
    }

    // MARK: - Жизнь

    /// Зовётся один раз за запуск, из `AppBootstrap`. Идемпотентно.
    func start() {
        guard !started else { return }
        started = true

        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update, source: "updates")
            }
        }
        storefrontTask = Task { [weak self] in
            for await storefront in Storefront.updates {
                await self?.applyStorefront(storefront.countryCode)
            }
        }
        // Вход в аккаунт — момент, когда накопленную привязку наконец есть
        // куда отправить: без сессии `/plus/attach` некому адресовать, и
        // очередь копится молча (см. `PlusAttachQueue.isAllowed`).
        AuthService.shared.$isSignedIn
            .removeDuplicates()
            .filter { $0 }
            .sink { _ in Task { await PlusAttachQueue.shared.drain() } }
            .store(in: &cancellables)

        Task { [weak self] in
            await self?.refreshAll()
            await PlusAttachQueue.shared.drain()
        }
    }

    /// Витрина, продукты, права — в этом порядке: цена и наличие продуктов
    /// зависят от витрины, а состояние — от продуктов (статус группы читается
    /// у любого из них).
    func refreshAll() async {
        await readStorefront()
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        do {
            let found = try await Product.products(for: Self.productIDs)
            // Пустой ответ — это РЕЗУЛЬТАТ, а не ошибка: витрина без
            // соглашения о платных приложениях, продукт ещё не разъехался по
            // серверам Apple, схема без `.storekit`. Пейвол в этом случае
            // показывает «цены не загрузились», а не пустые карточки.
            products = Self.productIDs.compactMap { id in found.first { $0.id == id } }
            plusLog.notice("products loaded: \(self.products.count, privacy: .public)")
        } catch {
            plusLog.error("products failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Права

    func refreshEntitlements() async {
        var entitled = false
        var isTrial = false
        var expires: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                plusLog.error("entitlement UNVERIFIED — ignored")
                continue
            }
            guard Self.productIDs.contains(transaction.productID) else { continue }
            // Возврат денег: право формально ещё в списке, но его отозвали.
            if let revoked = transaction.revocationDate, revoked <= Date() { continue }

            entitled = true
            isTrial = Self.isIntroductory(transaction)
            expires = transaction.expirationDate
            PlusAttachQueue.shared.enqueue(
                key: String(transaction.originalID), jws: result.jwsRepresentation)
        }

        let renewal = await renewalSummary()
        expiresAt = expires
        state = Self.resolve(entitled: entitled, isTrial: isTrial, renewal: renewal)
        PlusAccess.shared.isPlus = isPlus
        plusLog.notice("""
            state=\(self.state.rawValue, privacy: .public) \
            entitled=\(entitled, privacy: .public) trial=\(isTrial, privacy: .public)
            """)
    }

    /// Триал ли это. Ветка по версии, а не один вызов: `offerType` объявлен
    /// устаревшим в 17.2, а `offer` появился там же, и цель сборки — 17.0.
    private nonisolated static func isIntroductory(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.type == .introductory
        }
        return transaction.offerType == .introductory
    }

    private func renewalSummary() async -> RenewalSummary? {
        guard let subscription = products.compactMap(\.subscription).first else { return nil }
        guard let statuses = try? await subscription.status else { return nil }
        return Self.summarize(statuses.map(\.state))
    }

    // MARK: - Покупка

    /// `true` — покупка прошла. `false` — отменили, отложили или не вышло; во
    /// всех трёх случаях пейвол просто остаётся открытым, без диалога.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }

        do {
            let options = TipJarService.purchaseOptions(accountId: TokenStore.shared.accountId)
            switch try await product.purchase(options: options) {
            case .success(let verification):
                await handle(verification, source: "purchase")
                return isPlus
            case .userCancelled:
                plusLog.notice("purchase cancelled")
                return false
            case .pending:
                // Ask To Buy: вердикт приедет в `Transaction.updates`.
                plusLog.notice("purchase pending")
                return false
            @unknown default:
                return false
            }
        } catch {
            plusLog.error("purchase failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Синхронизация с App Store — тест-шов.
    ///
    /// `AppStore.sync()` поднимает диалог аккаунта Apple, и в прогоне тестов
    /// ждёт его до тех пор, пока систему не убьёт по таймауту: `SKTestSession
    /// .disableDialogs` на него не распространяется. Подменяемое замыкание —
    /// единственный способ проверить остальную половину «Восстановить»
    /// (обновление прав и снятие занятости), не убив процесс.
    var syncWithAppStore: @Sendable () async throws -> Void = { try await AppStore.sync() }

    /// «Восстановить покупки» — обязательная кнопка ревью Apple.
    ///
    /// `AppStore.sync()` просит пароль Apple ID, поэтому он НЕ зовётся сам на
    /// старте: там хватает `currentEntitlements`, который восстанавливает
    /// подписку молча.
    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await syncWithAppStore()
        } catch {
            plusLog.notice("restore sync: \(error.localizedDescription, privacy: .public)")
        }
        await refreshEntitlements()
    }

    // MARK: - Транзакции

    private func handle(_ result: VerificationResult<Transaction>, source: String) async {
        switch result {
        case .verified(let transaction):
            // Чаевые едут по `Transaction.updates` тем же потоком, и закрывать
            // их здесь нельзя: у них свой хозяин (`TipJarService`), и подпись
            // чаевых на `/plus/attach` не имеет смысла вовсе.
            guard Self.productIDs.contains(transaction.productID) else { return }
            plusLog.notice("""
                tx verified source=\(source, privacy: .public) \
                product=\(transaction.productID, privacy: .public) \
                env=\(transaction.environment.rawValue, privacy: .public)
                """)
            PlusAttachQueue.shared.enqueue(
                key: String(transaction.originalID), jws: result.jwsRepresentation)
            await transaction.finish()
            await refreshEntitlements()

        case .unverified(let transaction, let error):
            plusLog.error("""
                tx UNVERIFIED source=\(source, privacy: .public) \
                product=\(transaction.productID, privacy: .public) \
                error=\(error.localizedDescription, privacy: .public)
                """)
        }
    }

    // MARK: - Витрина

    private func readStorefront() async {
        applyStorefront(await Storefront.current?.countryCode)
    }

    private func applyStorefront(_ code: String?) {
        storefrontCountry = code
        PlusAccess.shared.storefrontHidesPlus = Self.hidesPlus(countryCode: code)
        plusLog.notice("storefront=\(code ?? "—", privacy: .public)")
    }
}
