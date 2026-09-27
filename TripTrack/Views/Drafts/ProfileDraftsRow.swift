import SwiftUI

/// Раздел «Черновики» на «Я»: ОДНА карточка вместо списка полных карточек
/// поездок (спека §2, доски 1 и 2).
///
/// Прежний раздел ждущих клал на главный экран человека столько
/// карточек, сколько записал автотрекинг, и каждая несла чип «Не
/// подтверждена». Статус задаёт ЭКРАН, а не бейдж (принцип 1 спеки): в Ленте
/// сохранённые поездки, в «Черновиках» записанные автоматически, а карточка
/// поездки везде одна и та же.
///
/// Нет черновиков — раздела нет совсем: ни пустой карточки, ни текста. Пустое
/// место на главном экране лучше строки, которая сообщает об отсутствии.
struct ProfileDraftsRow: View {
    let count: Int
    /// Когда записан самый свежий черновик.
    let lastAt: Date?
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    private static let time = LocalizedDateFormatter.templates("Hmm")

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
                        .frame(width: 40, height: 40)
                    Image(systemName: "tray.full")
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(AppStrings.formattedCount(count, lang: l)) \(AppStrings.nounTrips(l, count))")
                        .font(AppType.itemValue)
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    if let subtitle = subtitle(l) {
                        Text(subtitle)
                            .font(AppType.meta)
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            // Карточка 68 pt: плитка 40 плюс поля 14 сверху и снизу.
            .frame(height: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("profile_drafts_row")
    }

    /// «Последняя вчера, 18:01». Дата — существующими относительными
    /// строками: заводить под «сегодня» и «вчера» свои ключи незачем, они уже
    /// переведены на тринадцать языков.
    private func subtitle(_ l: LanguageManager.Language) -> String? {
        guard let lastAt, let clock = Self.time[l] else { return nil }
        return AppStrings.draftsCardLast(l,
                                         date: RelativeTripDate.string(from: lastAt, language: l),
                                         time: clock.string(from: lastAt))
    }
}
