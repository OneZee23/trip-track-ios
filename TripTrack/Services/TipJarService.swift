import Foundation
import StoreKit
import OSLog

private let tipLog = Logger(subsystem: "com.triptrack", category: "tipjar")

/// Чаевые: три расходуемые покупки, которые НЕ открывают ничего.
///
/// Файл родился пробником денежного тракта (0.7.0) и с 0.8.0 стал боевым —
/// логи и оговорки пробника остались намеренно. Вопрос, ради которого они
/// писались, никуда не делся: зелёная покупка в `.xcode` доказывает, что
/// компилируется код, и ничего больше.
///
/// Три окружения, и отвечают они на разное:
///
///   * `.xcode`     — локальный `Config/TripTrack.storekit`. На серверы Apple
///                    не ходит, чек подписан локальным сертификатом, и любая
///                    серверная проверка его отвергнет. Доказывает, что
///                    работает КОД.
///   * `.sandbox`   — настоящая запись в App Store Connect, купленная
///                    sandbox-аккаунтом. Доказывает, что ПРОДУКТ существует.
///                    Денег всё равно не двигает.
///   * `.production`— единственное, где деньги есть.
///
/// **Расходуемые, а не единоразовые.** Чаевые должны повторяться, и правило
/// 3.1.1 обязывает КАЖДУЮ единоразовую покупку нести рабочее «Восстановить»,
/// для которого у чаевых нет смысла. Обещать за них нечего — и текст листа
/// (`TipJarSheet`) не обещает: одно спасибо.
@MainActor
final class TipJarService: ObservableObject {
    static let shared = TipJarService()

    /// Идентификатор в App Store Connect ПОСТОЯНЕН: однажды заведённый, он не
    /// переиспользуется никогда, даже после удаления продукта. Поэтому ещё
    /// пробник 0.7.0 брал боевой id, а не `…probe`.
    static let tipID = "com.onezee.TripTrack.tip.small"
    static let tipMediumID = "com.onezee.TripTrack.tip.medium"
    static let tipLargeID = "com.onezee.TripTrack.tip.large"
    /// Порядок значим — он же порядок кнопок в листе.
    static let tipIDs = [tipID, tipMediumID, tipLargeID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var storefront: String?
    #if DEBUG
    /// Человекочитаемый разбор последней транзакции — вывод пробника, который
    /// читают глазами на экране `TipJarDebugView`.
    @Published private(set) var report: String?
    #endif

    /// Самая мелкая — её покупает пробник и с неё начинается лист.
    var product: Product? { products.first { $0.id == Self.tipID } }

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case purchasing
        case succeeded
        case cancelled
        /// Ask To Buy / SCA — покупка ни прошла, ни упала, и вердикт приедет
        /// позже через `Transaction.updates`.
        case deferred
        case failed(String)
    }

    /// Заведён один раз и не отменяется: синглтон переживает любой экран. Без
    /// слушателя незакрытая расходуемая покупка переигрывается на каждом
    /// запуске — это выглядит ровно как баг StoreKit и им не является.
    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.apply(update, source: "updates")
            }
        }
    }

    // MARK: - Load

    func load() async {
        phase = .loading
        #if DEBUG
        report = nil
        #endif
        storefront = await Self.describeStorefront()

        do {
            let found = try await Product.products(for: Self.tipIDs)
            let ordered = Self.tipIDs.compactMap { id in found.first { $0.id == id } }
            guard !ordered.isEmpty else {
                // Пустой массив — это РЕЗУЛЬТАТ, а не ошибка: ни один id не
                // разрешился. В `.xcode` это значит, что схема не смотрит на
                // `.storekit`; в песочнице — что продуктов нет, они ещё не
                // разъехались или не в продажном состоянии.
                phase = .failed("Продукты не найдены")
                tipLog.error("load: no products for \(Self.tipIDs.joined(separator: ","), privacy: .public)")
                return
            }
            products = ordered
            phase = .ready
            for p in ordered {
                tipLog.notice("""
                    load ok id=\(p.id, privacy: .public) \
                    displayPrice=\(p.displayPrice, privacy: .public) \
                    currency=\(p.priceFormatStyle.currencyCode, privacy: .public) \
                    storefront=\(self.storefront ?? "—", privacy: .public)
                    """)
            }
        } catch {
            phase = .failed(error.localizedDescription)
            tipLog.error("load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Buy

    /// Какие опции несёт покупка. Чистая и вынесенная из `buy()`, чтобы
    /// правило проверялось без StoreKit.
    ///
    /// `appAccountToken` записывается в подписанную транзакцию и читается
    /// потом через App Store Server API — это единственный шанс связать платёж
    /// с аккаунтом в нашем бэкенде, и задним числом он не добавляется. Покупки
    /// без него остаются анонимными навсегда.
    ///
    /// Ставится ТОЛЬКО когда человек вошёл. Соблазнительный запасной вариант,
    /// `SettingsManager.localUserId`, — это id строки CoreData: он рождается
    /// заново при потере стора, что на живом пользователе случилось дважды за
    /// две недели. Писать сбрасывающийся идентификатор в поле, которое не
    /// меняется никогда, значит получить чеки, указывающие на личности,
    /// которых больше нет. `TokenStore.accountId` живёт в Keychain и
    /// переживает и стирание базы, и переустановку.
    ///
    /// Не вошёл — покупка анонимна, и это честно. Требовать входа прежде, чем
    /// принять чаевые, честно не было бы.
    nonisolated static func purchaseOptions(accountId: UUID?) -> Set<Product.PurchaseOption> {
        guard let accountId else { return [] }
        return [.appAccountToken(accountId)]
    }

    /// Пробник: покупает самую мелкую. Боевой лист зовёт `buy(_:)`.
    func buy() async {
        guard let product else {
            phase = .failed("Нечего покупать — сначала загрузите продукт")
            return
        }
        await buy(product)
    }

    func buy(_ product: Product) async {
        phase = .purchasing
        let options = Self.purchaseOptions(accountId: TokenStore.shared.accountId)
        tipLog.notice("""
            purchase begin id=\(product.id, privacy: .public) \
            accountToken=\(TokenStore.shared.accountId?.uuidString ?? "—", privacy: .private)
            """)

        do {
            switch try await product.purchase(options: options) {
            case .success(let verification):
                await apply(verification, source: "purchase")

            case .userCancelled:
                phase = .cancelled
                tipLog.notice("purchase cancelled by user")

            case .pending:
                // Ask To Buy (детский аккаунт) или подтверждение банка. Ничего
                // не должны и ничего не упало — вердикт приедет позже, иногда
                // через дни.
                phase = .deferred
                tipLog.notice("purchase pending (ask-to-buy / SCA)")

            @unknown default:
                phase = .failed("Неизвестный результат покупки")
                tipLog.error("purchase: unknown result case")
            }
        } catch {
            phase = .failed(error.localizedDescription)
            tipLog.error("purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Transaction handling

    private func apply(_ result: VerificationResult<Transaction>, source: String) async {
        switch result {
        case .verified(let transaction):
            // Подписка едет тем же потоком, и закрывать её здесь нельзя: у неё
            // свой хозяин (`PlusStore`), которому нужна её подпись.
            guard Self.tipIDs.contains(transaction.productID) else { return }
            #if DEBUG
            report = Self.describe(transaction, verified: true)
            #endif
            phase = .succeeded
            tipLog.notice("""
                tx verified source=\(source, privacy: .public) \
                id=\(Self.shortId(transaction.id), privacy: .public) \
                env=\(transaction.environment.rawValue, privacy: .public) \
                accountToken=\(transaction.appAccountToken?.uuidString ?? "—", privacy: .private)
                """)
            // Незакрытая расходуемая покупка передаётся заново вечно.
            await transaction.finish()

        case .unverified(let transaction, let error):
            guard Self.tipIDs.contains(transaction.productID) else { return }
            // Нарочно НЕ закрывается. Тихо закрыть непроверенную транзакцию —
            // это способ сделать настоящий сбой невидимым; оставленная
            // открытой, она вернётся и останется видна.
            #if DEBUG
            report = Self.describe(transaction, verified: false)
                + "\n\nОШИБКА ПРОВЕРКИ: \(error.localizedDescription)"
            #endif
            phase = .failed("Подпись не прошла проверку")
            tipLog.error("""
                tx UNVERIFIED source=\(source, privacy: .public) \
                id=\(Self.shortId(transaction.id), privacy: .public) \
                error=\(error.localizedDescription, privacy: .public)
                """)
        }
    }

    /// Хвост id транзакции — ровно столько, чтобы склеить строку лога с
    /// серверной, и не столько, чтобы получился идентификатор покупки.
    ///
    /// **Дисциплина лога держится только на дисциплине авторов строк.**
    /// `APILogger.redact` чистит ТЕЛА HTTP, а `DebugLogExporter` и «Журнал»
    /// копируют `log.composedMessage` дословно — `PIISensitiveKeys` их не
    /// касается вовсе. Файл был пробником под `#if DEBUG` и логи писал
    /// щедро; с 0.8.0 он боевой, а серверное правило «не длиннее восьми
    /// символов» (`plus.service.ts`) теперь соблюдают обе стороны.
    nonisolated static func shortId(_ id: UInt64) -> String {
        String(String(id).suffix(8))
    }

    // MARK: - Reporting

    #if DEBUG
    private static func describe(_ t: Transaction, verified: Bool) -> String {
        let env: String
        switch t.environment {
        case .xcode:      env = "xcode — локальный файл, денег нет, чек невалиден для сервера"
        case .sandbox:    env = "sandbox — реальный продукт ASC, денег всё равно нет"
        case .production: env = "production — НАСТОЯЩИЕ деньги"
        default:          env = t.environment.rawValue
        }

        return """
        Проверка подписи: \(verified ? "прошла" : "НЕ ПРОШЛА")
        Окружение: \(env)

        transaction.id:   \(t.id)
        originalID:       \(t.originalID)
        productID:        \(t.productID)
        purchaseDate:     \(t.purchaseDate.formatted(.iso8601))
        ownershipType:    \(t.ownershipType.rawValue)
        appAccountToken:  \(t.appAccountToken?.uuidString ?? "— (покупка анонимна: не вошёл)")
        """
    }
    #endif

    private static func describeStorefront() async -> String {
        guard let sf = await Storefront.current else { return "неизвестен" }
        return "\(sf.countryCode) (id \(sf.id))"
    }
}
