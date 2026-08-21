#if DEBUG
import Foundation
import StoreKit
import OSLog

private let tipLog = Logger(subsystem: "com.triptrack", category: "tipjar")

/// The donation tract probe — NOT a shipping feature.
///
/// The question this exists to answer is not «can the user pay», it is
/// «where does the money land and in what shape». So every step logs the
/// fields you would otherwise have to guess at: the storefront the device is
/// actually on, the currency the price came back in, and — the one that
/// matters most — `Transaction.environment`, because a green purchase in
/// `.xcode` proves only that this file compiles.
///
/// Three environments, and they answer different questions:
///
///   * `.xcode`     — the local `Config/TripTrack.storekit` file. Never
///                    touches Apple's servers, the receipt is signed by a
///                    local test certificate, and any server-side validation
///                    rejects it. Proves the CODE works. Needs no App Store
///                    Connect record, no agreement, no bank account.
///   * `.sandbox`   — a real product record in App Store Connect bought with
///                    a sandbox Apple ID. Proves the PRODUCT exists and the
///                    account plumbing is real. Still moves no money and
///                    appears in no financial report.
///   * `.production`— the only one where money exists.
///
/// The row that reaches this service is compiled out of Release builds (see
/// `ProfileSettingsSheet.devGroup`), so nothing here can reach a user.
@MainActor
final class TipJarService: ObservableObject {
    static let shared = TipJarService()

    /// Deliberately the id we would actually ship, not a `…probe` throwaway:
    /// a product identifier in App Store Connect is permanent — once created
    /// it can never be reused, even after the product is deleted. Burning a
    /// good id on a test is a mistake you cannot undo.
    static let tipID = "com.onezee.TripTrack.tip.small"

    /// Consumable, not non-consumable. A tip should be repeatable, and
    /// guideline 3.1.1 obliges every non-consumable to carry a working
    /// «Restore Purchases» control — which a tip jar has no meaning for.
    @Published private(set) var product: Product?
    @Published private(set) var phase: Phase = .idle
    /// Human-readable dump of the last transaction — this is the actual
    /// output of the probe, meant to be read on screen and screenshotted.
    @Published private(set) var report: String?
    @Published private(set) var storefront: String?

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case purchasing
        case succeeded
        case cancelled
        /// Ask To Buy / SCA — the purchase is neither done nor failed, and
        /// the resolution arrives later through `Transaction.updates`.
        case deferred
        case failed(String)
    }

    /// Started once, never cancelled: the singleton outlives every screen.
    /// Without this listener an unfinished consumable is re-delivered on
    /// every launch, which reads exactly like a StoreKit bug and is not one.
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
        report = nil
        storefront = await Self.describeStorefront()

        do {
            let found = try await Product.products(for: [Self.tipID])
            guard let p = found.first else {
                // An empty array IS a result, not an error: the id did not
                // resolve. In `.xcode` that means the scheme is not pointing
                // at the .storekit file; in sandbox it means the product is
                // missing, not yet propagated, or in a non-sellable state.
                phase = .failed("Продукт не найден. id=\(Self.tipID)")
                tipLog.error("load: no product for id=\(Self.tipID, privacy: .public)")
                return
            }
            product = p
            phase = .ready
            tipLog.notice("""
                load ok id=\(p.id, privacy: .public) \
                displayPrice=\(p.displayPrice, privacy: .public) \
                currency=\(p.priceFormatStyle.currencyCode, privacy: .public) \
                storefront=\(self.storefront ?? "—", privacy: .public)
                """)
        } catch {
            phase = .failed(error.localizedDescription)
            tipLog.error("load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Buy

    /// Which options a purchase carries. Pure and separated from `buy()` so the
    /// rule can be tested without StoreKit.
    ///
    /// `appAccountToken` is written into the signed transaction and is
    /// readable later through the App Store Server API, so it is the one
    /// chance to tie a payment to an account in our backend — and it cannot be
    /// added retroactively. Purchases made without it stay anonymous forever.
    ///
    /// It is stamped ONLY when signed in. The tempting fallback,
    /// `SettingsManager.localUserId`, is the id of a CoreData row: it is minted
    /// afresh whenever the store is lost, which we watched happen twice to one
    /// real user inside two weeks. Writing an identifier that resets into a
    /// field that never changes would produce receipts pointing at identities
    /// that no longer exist. `TokenStore.accountId` lives in the Keychain and
    /// survives both a store wipe and a reinstall.
    ///
    /// Signed out therefore means an anonymous purchase, which is honest.
    /// Demanding a sign-in before accepting a tip would not be.
    nonisolated static func purchaseOptions(accountId: UUID?) -> Set<Product.PurchaseOption> {
        guard let accountId else { return [] }
        return [.appAccountToken(accountId)]
    }

    func buy() async {
        guard let product else {
            phase = .failed("Нечего покупать — сначала загрузите продукт")
            return
        }
        phase = .purchasing
        let options = Self.purchaseOptions(accountId: TokenStore.shared.accountId)
        tipLog.notice("""
            purchase begin id=\(product.id, privacy: .public) \
            accountToken=\(TokenStore.shared.accountId?.uuidString ?? "—", privacy: .public)
            """)

        do {
            switch try await product.purchase(options: options) {
            case .success(let verification):
                await apply(verification, source: "purchase")

            case .userCancelled:
                phase = .cancelled
                tipLog.notice("purchase cancelled by user")

            case .pending:
                // Ask To Buy (child account) or a bank-side confirmation.
                // Nothing is owed yet and nothing failed — the verdict will
                // arrive on `Transaction.updates`, possibly days later.
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
            report = Self.describe(transaction, verified: true)
            phase = .succeeded
            tipLog.notice("""
                tx verified source=\(source, privacy: .public) \
                id=\(String(transaction.id), privacy: .public) \
                env=\(transaction.environment.rawValue, privacy: .public) \
                accountToken=\(transaction.appAccountToken?.uuidString ?? "—", privacy: .public)
                """)
            // A consumable that is never finished is redelivered forever.
            await transaction.finish()

        case .unverified(let transaction, let error):
            // Deliberately NOT finished. Finishing an unverified transaction
            // silently is how a real failure becomes invisible; leaving it
            // open means it comes back and stays visible.
            report = Self.describe(transaction, verified: false)
                + "\n\nОШИБКА ПРОВЕРКИ: \(error.localizedDescription)"
            phase = .failed("Подпись не прошла проверку")
            tipLog.error("""
                tx UNVERIFIED source=\(source, privacy: .public) \
                id=\(String(transaction.id), privacy: .public) \
                error=\(error.localizedDescription, privacy: .public)
                """)
        }
    }

    // MARK: - Reporting

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

    private static func describeStorefront() async -> String {
        guard let sf = await Storefront.current else { return "неизвестен" }
        return "\(sf.countryCode) (id \(sf.id))"
    }
}
#endif
