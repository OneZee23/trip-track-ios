import SwiftUI

/// Тихая просьба сказать спасибо — последней строкой карточки итогов.
///
/// Здесь, а не в настройках, потому что правило одно: сначала дать, потом
/// тихо спросить. Выше на этом же экране человек только что увидел свою
/// дорогу, километры, награды и то, что она открыла на карте; карточка стоит
/// ПОСЛЕ всего этого и ничего не перекрывает.
///
/// Чего здесь нарочно НЕТ:
/// - **модальности.** Ни листа, ни диалога: просьба о подарке не имеет права
///   загораживать человеку его собственный итог;
/// - **сумм и цен.** Их показывает витрина Apple в листе чаевых, и второго
///   места с деньгами на этом экране быть не должно;
/// - **обещаний.** Что ничего не откроется, сказано в самом листе
///   (`AppStrings.tipsText`) — до оплаты и своими словами.
///
/// Показывать её или нет, решает `TipMoment`, а не этот вид: «не чаще раза в
/// полгода» и «два отказа — навсегда» проверяются календарём, а не экраном.
struct TripSummaryTipCard: View {
    /// Нажали «Сказать спасибо».
    let onTip: () -> Void
    /// Закрыли крестиком. Для `TipLedger` это отказ, и он считается.
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.tipMomentLine(l))
                    .font(AppType.meta)
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Haptics.tap()
                    onTip()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart")
                            .font(.system(size: 13))
                        Text(AppStrings.tipsEntry(l))
                            .font(AppType.meta)
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("tip_moment_action")
            }

            Spacer(minLength: 0)

            // Крестик, а не «Не сейчас» словом: кнопка отказа, набранная в
            // строку рядом с просьбой, читается как выбор из двух равных
            // вариантов — а равными они не являются. Отказ здесь должен быть
            // незаметным и бесплатным.
            Button {
                Haptics.tap()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.close(l))
            .accessibilityIdentifier("tip_moment_dismiss")
        }
        .padding(14)
        .surfaceCard()
        .accessibilityIdentifier("tip_moment_card")
    }
}
