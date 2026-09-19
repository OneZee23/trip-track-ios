import SwiftUI

/// Строка «Поддержать» в профиле — вход в `TipJarSheet`.
///
/// Отдельная от `PlusRow` нарочно: подписка и чаевые — разные сделки, и
/// поставить их одной строкой значило бы намекнуть, что чаевые что-то дают.
/// Форма та же, что у `ProfileClubsRow` и `PlusRow`; подпись говорит вслух,
/// что обещаний нет.
struct ProfileSupportRow: View {
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.accentBg)
                        .frame(width: 44, height: 44)
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.profileRowSupport(l))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(AppStrings.profileRowSupportSubtitle(l))
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

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
        .accessibilityIdentifier("profile_support_row")
    }
}
