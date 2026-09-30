import SwiftUI
import StoreKit

/// Строка «TripTrack PRO» в разделе «Подписка» на экране «Я» — состояния
/// 12…17а матрицы 0.8.4.
///
/// Сама она больше ничего не решает: что написать и куда вести, отвечает
/// `ProStatus`. До 0.8.4 строка знала три состояния и разбирала их внутри
/// `body`; состояний восемь, два из них про витрину, и проверить такое
/// открытым экраном нельзя — отсюда чистый тип рядом и `ProStatusTests`.
///
/// Отмена подписки живёт у Apple, и своего экрана для неё не существует:
/// `.manageSubscription` открывает системный лист. Это единственная законная
/// системная презентация в приложении (запрет в «Dialogs» — про диалоги,
/// которые мы могли бы нарисовать сами).
struct PlusRow: View {
    /// Открыть пейвол. Зовётся только там, где платное продаётся.
    let onOpenPaywall: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var store = PlusStore.shared
    @ObservedObject private var access = PlusAccess.shared

    /// Что сейчас со подпиской — один ответ на восемь случаев.
    private var status: ProStatus {
        ProStatus.resolve(state: store.state,
                          expires: store.expiresAt,
                          isPending: store.awaitingApproval,
                          storefrontHidesPlus: access.storefrontHidesPlus)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let status = self.status

        // Витрина платного не продаёт и подписки нет — раздела нет вовсе, а не
        // «есть, но недоступен»: спека требует, чтобы платного не было ВИДНО.
        if status.showsRow {
            Button {
                Haptics.tap()
                switch status.destination {
                case .paywall:            onOpenPaywall()
                case .manageSubscription: Self.openManageSubscriptions()
                case .nothing, .none:     break
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.accentBg)
                            .frame(width: 40, height: 40)
                        Image(systemName: "star.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.rowTitle(lang: l))
                            .font(.inter(16, weight: .semibold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        Text(status.rowSubtitle(lang: l))
                            .font(.inter(13))
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    // Шеврон стоит только там, где нажатие что-то открывает.
                    // «Ждём подтверждения» не открывает ничего, и обещать
                    // переход было бы неправдой (CLAUDE.md, «Нажатие обязано
                    // отвечать»).
                    if status.destination != .nothing {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 68)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .disabled(status.destination == .nothing)
            .surfaceCard(cornerRadius: 16)
            .accessibilityIdentifier("profile_plus_row")
            .accessibilityElement(children: .combine)
        }
    }

    /// Системный лист Apple.
    static func openManageSubscriptions() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
    }
}
