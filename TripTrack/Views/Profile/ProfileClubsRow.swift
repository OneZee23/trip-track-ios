import SwiftUI

/// Строка «Клубы — скоро» в профиле (0.6.8, Figma 2902:161 · S8).
///
/// Вкладка «Группы» ушла — её слот занял «Места», — а обещание клубов и лист
/// ожидания под ним остались. Профиль — их место: это социальная часть
/// приложения, здесь же подписки. В ленту не пошло нарочно: лента про чужие
/// поездки, и обещание будущей функции там — шум (спека 0.6.8 §3).
///
/// Форма — `garageEmptyCard`: диск 44 pt на `accentBg`, заголовок, подпись,
/// шеврон. Подпись — те же слова, что печатал тизер: настоящее число из
/// `/groups/waitlist` или приглашение быть первым, и «вы записаны» у
/// телефона из списка. Число приходит из кэша мгновенно и обновляется в
/// `.task` — тот же вызов, что делал тизер при открытии вкладки.
struct ProfileClubsRow: View {
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var waitlist = GroupsWaitlistStore.shared

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
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.groupsComingTitle(l))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(Self.subtitle(total: waitlist.state.total,
                                       joined: waitlist.state.joined,
                                       lang: l))
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
        // Соседние карточки гаража стоят на `.plain` — они старше правила
        // «нажатие обязано отвечать». Новая строка правило соблюдает.
        .buttonStyle(PressableCardStyle())
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("profile_clubs_row")
        .task { await waitlist.refresh() }
    }

    /// Чистая, чтобы держаться тестом (`ProfileClubsRowTests`).
    static func subtitle(total: Int, joined: Bool, lang: LanguageManager.Language) -> String {
        // Записанный телефон — сам в счётчике: даже без ответа сервера
        // «ждут» как минимум один, и «будьте первым» ему уже не сказать.
        let n = max(total, joined ? 1 : 0)
        let count = n > 0
            ? AppStrings.groupsWaitlistCount(lang, count: n)
            : AppStrings.groupsWaitlistFirst(lang)
        return joined ? "\(count) · \(AppStrings.clubsRowJoined(lang))" : count
    }
}
