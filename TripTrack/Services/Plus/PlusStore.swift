import Foundation
import StoreKit
import OSLog
import Combine
import UIKit

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

    /// Чем кончилась покупка. `Bool` здесь стоял до ревью и был неправ: он
    /// сваливал в один `false` три разных ответа — «передумал», «ждём
    /// подтверждения взрослого» и «не вышло», — а экран на все три молчал.
    /// Молчание правильно ровно для первого.
    enum PurchaseOutcome {
        case success
        /// Человек сам закрыл лист Apple. Экрану говорить нечего.
        case cancelled
        /// Ask To Buy или подтверждение банка: вердикт приедет позже, в
        /// `Transaction.updates`.
        case pending
        /// Сеть, StoreKit или непрошедшая проверка подписи. Причина едет
        /// внутрь только для лога — на экран текст ошибки не попадает
        /// никогда: он английский, системный и человеку ничего не объясняет.
        case failed(Error)
    }

    /// Что экран показывает под кнопкой. Отдельный тип, потому что проверять
    /// надо именно это отображение, а собрать `Product.PurchaseResult` в
    /// тесте нечем.
    enum PurchaseMessage: Equatable {
        case none
        case pending
        case failed
    }

    nonisolated static func message(for outcome: PurchaseOutcome) -> PurchaseMessage {
        switch outcome {
        case .success, .cancelled: return .none
        case .pending:             return .pending
        case .failed:              return .failed
        }
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
    /// Даст ли Apple вводное предложение ЭТОМУ Apple ID.
    ///
    /// Спрашивается у StoreKit, а не выводится из наличия `introductoryOffer`:
    /// предложение у продукта существует ВСЕГДА, а право на него — нет.
    /// Вернувшемуся подписчику (отменил → передумал) пейвол обещал «7 дней
    /// бесплатно, потом 29,99 €», а списывалось 29,99 € сразу; это
    /// App Store Review 3.1.2 и потребительское право, а не косметика.
    /// `false` до ответа Apple — обещание даётся, только когда оно правда.
    @Published private(set) var introEligible = false

    var isPlus: Bool { Self.grants(state) }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var monthly: Product? { products.first { $0.id == Self.monthlyID } }

    private var updatesTask: Task<Void, Never>?
    private var storefrontTask: Task<Void, Never>?
    private var recheckTask: Task<Void, Never>?
    private var foregroundObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    /// Как часто перечитывать права у живого приложения. Сутки — потому что
    /// подписка кончается по календарю, а не по событию: истечение НЕ создаёт
    /// транзакции, и `Transaction.updates` про него молчит.
    static let recheckInterval: TimeInterval = 24 * 3600

    #if DEBUG
    /// Флаг запуска, которым снимаются экраны платного. Читается свежо:
    /// `PlusAccess.init` спрашивает его до того, как этот класс существует.
    static var isDebugPlus: Bool {
        ProcessInfo.processInfo.arguments.contains("-debug-plus")
    }
    #endif

    private init() {}

    // MARK: - Чистые правила

    /// Даёт ли состояние доступ к платному.
    nonisolated static func grants(_ state: State) -> Bool {
        state == .trial || state == .active || state == .grace
    }

    /// Витрина, которая платного не показывает. Решение владельца 19 сентября:
    /// в РФ платежи App Store мертвы с 1 апреля 2026, и пейвол там — это
    /// кнопка, которая не может сработать.
    ///
    /// Кодов ДВА, и оба законны: `Storefront.countryCode` трёхбуквенный
    /// (`RUS`), а `Locale.region.identifier`, которым засевается первый
    /// запуск, — двухбуквенный (`RU`). Сравнение только с одним из них
    /// молча пропустило бы второй.
    nonisolated static func hidesPlus(countryCode: String?) -> Bool {
        guard let code = countryCode?.uppercased() else { return false }
        return code == "RUS" || code == "RU"
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

        // **Права перечитываются на каждом возвращении в приложение.**
        // Истечение подписки не создаёт транзакции, и `Transaction.updates`
        // про него молчит: пересчитать состояние физически некому. А процесс
        // TripTrack живёт сутками — фоновая геолокация и significant location
        // changes его не отпускают, — так что без этого «Плюс» оставался бы
        // открытым сколь угодно долго после конца оплаченного периода (и
        // наоборот: подписка, купленная на втором телефоне, не подхватывалась
        // бы до перезапуска). Зовётся именно `refreshEntitlements`, а не
        // `refreshAll`: витрина и продукты на каждом фокусе не нужны, а
        // `currentEntitlements` отвечает офлайн и стоит ничего.
        for name in [UIApplication.didBecomeActiveNotification,
                     UIApplication.willEnterForegroundNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in await PlusStore.shared.refreshEntitlements() }
            }
            foregroundObservers.append(token)
        }
        // И на всякий случай — раз в сутки у приложения, которое так и не
        // уходило в фон: подписка кончается по календарю.
        recheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.recheckInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.refreshEntitlements()
            }
        }

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
            await refreshIntroEligibility()
            plusLog.notice("products loaded: \(self.products.count, privacy: .public)")
        } catch {
            plusLog.error("products failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Право на вводное предложение — у ГРУППЫ, а не у продукта: Apple даёт
    /// бесплатную неделю один раз на группу подписок, и спрашивать её у
    /// каждого тарифа отдельно бессмысленно.
    private func refreshIntroEligibility() async {
        guard let subscription = products.compactMap(\.subscription).first else {
            introEligible = false
            return
        }
        introEligible = await subscription.isEligibleForIntroOffer
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
            // Самая ПОЗДНЯЯ дата, а не последняя в перечислении: порядок
            // `currentEntitlements` Apple не обещает, а строк в группе у
            // человека, переехавшего с месячного на годовой, две — и «Плюс до
            // 12 окт» показывал бы ту из них, которая досталась циклу
            // последней.
            expires = Self.later(expires, transaction.expirationDate)
            PlusAttachQueue.shared.enqueue(
                key: String(transaction.id), jws: result.jwsRepresentation)
        }

        let renewal = await renewalSummary()
        let resolved = Self.resolve(entitled: entitled, isTrial: isTrial, renewal: renewal)

        // **Пустая витрина не гасит «Плюс».** `renewalSummary` начинается с
        // `products`, а в самолёте `loadProducts` кидает и оставляет их
        // пустыми: у человека в `billingRetry` (где `currentEntitlements`
        // права уже не отдаёт) состояние сложилось бы в `.none` — то есть
        // «Плюс» гас бы ровно тогда, когда он обещан работать. Молчание
        // Apple — это не ответ «не куплено».
        if products.isEmpty, !entitled, Self.grants(state) {
            plusLog.notice("entitlements: products unavailable — keeping state")
            return
        }

        expiresAt = expires
        state = resolved
        #if DEBUG
        // Флаг снимков платного держится ЗДЕСЬ, а не в `PlusAccess.init`:
        // первое же обновление прав перезаписывало его через секунду после
        // старта, и снимки «как выглядит Плюс» врали молча.
        if Self.isDebugPlus { state = .active }
        #endif
        PlusAccess.shared.isPlus = isPlus
        plusLog.notice("""
            state=\(self.state.rawValue, privacy: .public) \
            entitled=\(entitled, privacy: .public) trial=\(isTrial, privacy: .public)
            """)
    }

    /// Поздняя из двух дат; `nil` не считается датой вовсе.
    nonisolated static func later(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
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

    /// Чем кончилась покупка — см. `PurchaseOutcome`. Пейвол закрывается
    /// только на `.success`, а на `.pending` и `.failed` остаётся открытым и
    /// говорит об этом строкой под кнопкой.
    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard !isBusy else { return .cancelled }
        isBusy = true
        defer { isBusy = false }

        do {
            let options = TipJarService.purchaseOptions(accountId: TokenStore.shared.accountId)
            switch try await product.purchase(options: options) {
            case .success(let verification):
                // Непрошедшая проверка подписи — это ОТКАЗ, а не покупка:
                // `handle` её игнорирует, и «Плюс» не откроется. Сказать при
                // этом «успех» значило бы закрыть пейвол ни с чем.
                if case .unverified(_, let error) = verification {
                    await handle(verification, source: "purchase")
                    return .failed(error)
                }
                await handle(verification, source: "purchase")
                return isPlus ? .success : .failed(PurchaseError.entitlementDidNotArrive)
            case .userCancelled:
                plusLog.notice("purchase cancelled")
                return .cancelled
            case .pending:
                // Ask To Buy: вердикт приедет в `Transaction.updates`.
                plusLog.notice("purchase pending")
                return .pending
            @unknown default:
                return .failed(PurchaseError.unknownResult)
            }
        } catch {
            plusLog.error("purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error)
        }
    }

    /// Две причины отказа, у которых своей ошибки нет ни у StoreKit, ни у сети.
    enum PurchaseError: Error {
        /// Транзакция прошла, а права не появилось. На живом StoreKit не
        /// встречается, но молча считать это успехом нельзя.
        case entitlementDidNotArrive
        /// Новый случай `Product.PurchaseResult` из будущей iOS.
        case unknownResult
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
    @discardableResult
    func restore() async -> PurchaseMessage {
        guard !isBusy else { return .none }
        isBusy = true
        defer { isBusy = false }
        var failed = false
        do {
            try await syncWithAppStore()
        } catch {
            // Провал восстановления обязан быть ВИДЕН: человек, у которого
            // оно упало по сети, иначе видит ровно то же, что человек,
            // которому нечего восстанавливать, — ничего. А ревью Apple эту
            // кнопку жмёт первой.
            failed = true
            plusLog.notice("restore sync: \(error.localizedDescription, privacy: .public)")
        }
        await refreshEntitlements()
        if isPlus { return .none }
        return failed ? .failed : .none
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
            // Ключ — `transaction.id`, а не `originalID`: у ВСЕХ продлений
            // одной подписки `originalID` одинаков, и продление молча не
            // уезжало бы на сервер никогда (сервер апсертит строку по
            // `originalTransactionId`, так что лишний POST раз в период не
            // стоит ничего).
            PlusAttachQueue.shared.enqueue(
                key: String(transaction.id), jws: result.jwsRepresentation)
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

    /// `nil` — это «не знаю», а НЕ «витрина сменилась на разрешающую».
    /// `Storefront.current` умеет промолчать офлайн, и сброс на этом молчании
    /// открывал бы платное на витрине, которая его не продаёт, — на всю
    /// сессию. Поэтому известное значение переживает молчание и запоминается
    /// до следующего запуска.
    private func applyStorefront(_ code: String?) {
        guard let code else {
            plusLog.notice("storefront unknown — keeping last known")
            return
        }
        storefrontCountry = code
        UserDefaults.standard.set(code, forKey: PlusAccess.storefrontKey)
        PlusAccess.shared.storefrontHidesPlus = Self.hidesPlus(countryCode: code)
        plusLog.notice("storefront=\(code, privacy: .public)")
    }
}
