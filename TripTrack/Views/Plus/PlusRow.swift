import SwiftUI
import StoreKit

/// Строка «Плюс» в профиле — единственное место, где о подписке говорят, когда
/// её не покупают.
///
/// Форма — `ProfileClubsRow`: диск 44 pt, заголовок, подпись, шеврон. Три
/// состояния и три разных нажатия: не куплено — пейвол; куплено — системный
/// лист управления подпиской Apple (своего экрана «отменить» у нас нет и быть
/// не может: отмена живёт у Apple, и подделывать её кнопкой значит обещать
/// действие, которого мы не совершаем); витрина без платного — строки нет
/// вовсе.
struct PlusRow: View {
    /// Открыть пейвол. Зовётся только там, где платное продаётся.
    let onOpenPaywall: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var store = PlusStore.shared

    /// Длина бесплатного периода годового тарифа. В `@State`, а не вычислением
    /// в `body`: разбор `introductoryOffer` идёт на каждой перерисовке строки,
    /// а меняется он ровно тогда, когда приезжает список продуктов.
    @State private var trialDays: Int?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let plus = store.isPlus

        Button {
            Haptics.tap()
            if plus {
                Self.openManageSubscriptions()
            } else {
                onOpenPaywall()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.accentBg)
                        .frame(width: 44, height: 44)
                    Image(systemName: plus ? "star.fill" : "star")
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.plusTitle(l))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(Self.status(
                        state: store.state,
                        expiresAt: store.expiresAt,
                        trialDays: trialDays,
                        lang: l
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Text(plus ? AppStrings.plusManage(l) : AppStrings.plusSubscribe(l))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("profile_plus_row")
        .task(id: store.products.map(\.id)) { trialDays = Self.trialDays(of: store.yearly) }
    }

    /// Длина бесплатного периода — приманка в подписи у того, кто ещё не
    /// покупал. Из `introductoryOffer`, не из литерала.
    private static func trialDays(of product: Product?) -> Int? {
        product.flatMap(PlusProductInfo.init(product:))?.trialDays
    }

    // MARK: - Правила

    /// Подпись строки. Чистая, чтобы держаться тестом: четыре состояния и
    /// «ещё не покупал» разводятся здесь, а не в `body`.
    static func status(
        state: PlusStore.State,
        expiresAt: Date?,
        trialDays: Int?,
        lang: LanguageManager.Language
    ) -> String {
        switch state {
        case .active, .trial:
            guard let expiresAt else { return AppStrings.plusRowSubtitle(lang) }
            return AppStrings.plusUntil(lang, date: shortDate(expiresAt, lang))
        case .grace:
            return AppStrings.plusGraceStatus(lang)
        case .expired:
            return AppStrings.plusExpiredStatus(lang)
        case .none:
            if let trialDays { return AppStrings.plusTrialAvailable(lang, days: trialDays) }
            return AppStrings.plusRowSubtitle(lang)
        }
    }

    /// «12 окт» — день и месяц своим порядком для каждого языка. Года нет
    /// нарочно: подписка живёт год, и «до 12 окт» читается однозначно, а
    /// полная дата в строке шириной с профиль обрезается.
    private static let formatters = LocalizedDateFormatter.templates("dMMM")

    static func shortDate(_ date: Date, _ lang: LanguageManager.Language) -> String {
        formatters[lang]?.string(from: date) ?? ""
    }

    /// Системный лист Apple. Единственное место в приложении, где системная
    /// презентация законна: отмену подписки делает Apple, и своего экрана для
    /// неё не существует (см. «Dialogs» — запрет там про диалоги, которые мы
    /// могли бы нарисовать сами).
    static func openManageSubscriptions() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
    }
}
