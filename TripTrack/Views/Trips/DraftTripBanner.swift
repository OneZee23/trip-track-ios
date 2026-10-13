import SwiftUI

/// «Это твоя поездка?» — на экране поездки и в итогах черновика (спека §3.3).
/// «Моя» уходит в `DraftDecisionQueue`: ту же дверь зовёт кнопка уведомления,
/// и применяет её один `MapViewModel.applyDraftDecisions`. «Удалить» — через
/// подтверждение, которое держит экран: диалог висит в корне экрана, а не в
/// прокрутке (CLAUDE.md, «Dialogs»).
struct DraftTripBanner: View {
    let tripId: UUID
    let onDelete: () -> Void
    /// Что сделать экрану ПОСЛЕ «Моя». Решает экран, а не баннер: на экране
    /// поездки, открытом из списка черновиков, ответ на вопрос значит «уходим
    /// обратно в список» (спека, состояние 8), а на карточке итогов только что
    /// записанной поездки уходить некуда — там человек как раз на неё смотрит.
    var onConfirmed: (() -> Void)? = nil

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.draftBannerTitle(lang.language))
                .font(.inter(17, weight: .bold))
                .foregroundStyle(c.text)
            Text(AppStrings.draftBannerBody(lang.language))
                .font(.inter(14))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    DraftDecisionQueue.shared.enqueue(tripId, .confirm)
                    NotificationCenter.default.post(name: .draftTripDecisionQueued, object: nil)
                    onConfirmed?()
                } label: {
                    Text(AppStrings.draftConfirm(lang.language))
                        .font(.inter(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("draft_confirm")

                Button {
                    Haptics.tap()
                    onDelete()
                } label: {
                    Text(AppStrings.draftDiscard(lang.language))
                        .font(.inter(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(AppTheme.red)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("draft_discard")
            }
        }
        .padding(16)
        .surfaceCard()
    }
}
