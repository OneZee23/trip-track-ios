import SwiftUI

/// Тизер клубов (Figma 117:2265 «09 · Группы · Скоро»): кластер марок,
/// примеры клубов, «Уведомить меня» и «Посмотреть что будет».
///
/// С 0.6.8 это НЕ вкладка: «Группы» ушли строкой в профиль (спека 0.6.8 §3),
/// и экран пушится из «Я». Отсюда две вещи:
///  • шапка — `CustomNavBar` с «назад», а не заголовок вкладки;
///  • своего `NavigationStack` нет (вложенный запрещён), а в типизированном
///    `[MeDest]` профиля `NavigationLink(value:)` с чужим типом отключён —
///    поэтому «Посмотреть что будет» сообщает о нажатии замыканием, а пушит
///    профиль (`MeDest.clubsCatalog`).
///
/// Two things here used to be theatre and are not any more:
///  • «Уведомить меня» set a local `@AppStorage` bool. Nothing on the server
///    knew anyone wanted this, so nobody could ever have been notified — the
///    button promised a message that had no way of being sent. It now joins a
///    real waitlist AND asks for notification permission, which is the other
///    half of being able to keep that promise.
///  • «Уже ждут 1 240 человек» was a string in the layout. It is the count of
///    that waitlist now, and it does not appear at all until somebody is on it.
struct GroupsComingSoonView: View {
    let onOpenCatalog: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var waitlist = GroupsWaitlistStore.shared
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            CustomNavBar(title: AppStrings.clubsTitle(l)) { EmptyView() }

            content(c: c, l: l)
        }
        // Как у каталога и страницы клуба: контент до физического низа, иначе
        // к клиренсу прибавляется домашний индикатор, и `CustomTabBar.clearance`
        // перестаёт значить то, что написано.
        .ignoresSafeArea(edges: .bottom)
        .background(c.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await waitlist.refresh() }
    }

    @ViewBuilder
    private func content(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                // Shared Figma 114:151 hero (accent-tinted outer ring + peach
                // accentBg disc) — same component instance the frame places
                // here (117:2280).
                // A generic car in a ring told you nothing about clubs. The
                // marks themselves do, and they are the thing the screen is
                // promising.
                ClubMarkCluster()

                Text(AppStrings.groupsComingTitle(l))
                    .font(.inter(21, weight: .heavy))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)

                Text(AppStrings.groupsComingBody(l))
                    .font(.inter(14))
                    .lineSpacing(6)
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                chipRows(c: c)
                    .padding(.top, 18)

                notifyButton(c: c, l: l)
                    .padding(.top, 22)

                previewButton(c: c, l: l)
                    .padding(.top, 10)

                waitlistLine(c: c, l: l)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 0)
        }
        .padding(.bottom, CustomTabBar.clearance)
        .frame(maxWidth: .infinity)
        .background(c.bg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: waitlist.state.joined)
    }

    // MARK: - Chips

    /// Example clubs (Figma order). Two fixed rows so the wrap matches the
    /// frame on every device width. Miata/VAG names stay untranslated.
    /// The chips name real clubs from the catalogue rather than four hardcoded
    /// strings, so the marks and the names cannot drift apart — and the emoji
    /// they used to carry were the last system glyphs on this screen.
    private func chipRows(c: AppTheme.Colors) -> some View {
        let clubs = Array(Club.all.prefix(4))
        return VStack(spacing: 7) {
            ForEach(Array(stride(from: 0, to: clubs.count, by: 2)), id: \.self) { i in
                HStack(spacing: 7) {
                    ForEach(clubs[i..<min(i + 2, clubs.count)]) { club in
                        chip(club, c: c)
                    }
                }
            }
        }
    }

    private func chip(_ club: Club, c: AppTheme.Colors) -> some View {
        HStack(spacing: 7) {
            if let asset = club.asset {
                Image(asset)
                    .resizable()
                    // After `resizable()`, as at every pixel-art call site.
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Text(club.emoji).font(.system(size: 13))
            }
            Text(club.name(lang.language))
                .font(.inter(13, weight: .semibold))
                .foregroundStyle(c.text)
        }
        .padding(.leading, 9)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .background(c.card, in: Capsule())
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }

    // MARK: - CTAs

    private func notifyButton(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let joined = waitlist.state.joined
        return Button {
            Haptics.success()
            Task { await waitlist.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: joined ? "checkmark" : "bell.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(joined ? AppStrings.groupsNotifyDone(l) : AppStrings.groupsNotifyMe(l))
                    .font(.inter(14, weight: .bold))
            }
            .foregroundStyle(joined ? AppTheme.accent : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                joined ? AnyShapeStyle(AppTheme.accentBg) : AnyShapeStyle(AppTheme.accent),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .shadow(
                color: joined ? .clear : AppTheme.accent.opacity(0.3),
                radius: 1.5, y: 1
            )
        }
        .buttonStyle(.plain)
        // Только своя запись, не фоновое чтение: иначе экран открывается с
        // погашенной главной кнопкой (см. `GroupsWaitlistStore.isJoining`).
        .disabled(waitlist.isJoining)
        .accessibilityIdentifier("groups_notify_cta")
    }

    /// «Посмотреть что будет» (canon 117:2265) — second CTA. Кнопка, не
    /// ссылка: см. комментарий к типу.
    private func previewButton(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            onOpenCatalog()
        } label: {
            Text(AppStrings.groupsPreviewCTA(l))
                .font(.inter(14, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(AppTheme.accent, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("groups_preview_cta")
    }

    /// The real number, and only when there IS one. «Уже ждут 0 человек» is
    /// worse than silence; an invitation is better than either.
    @ViewBuilder
    private func waitlistLine(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 4) {
            Text(waitlist.state.total > 0
                 ? AppStrings.groupsWaitlistCount(l, count: waitlist.state.total)
                 : AppStrings.groupsWaitlistFirst(l))
                .font(.inter(12))
                .foregroundStyle(c.textTertiary)
                .accessibilityIdentifier("groups_waitlist_count")

            // A guest's place in the queue is recorded, but a push needs an
            // account to land on — say so instead of quietly not sending one.
            if waitlist.state.joined && !auth.isSignedIn {
                Text(AppStrings.groupsNotifySignInHint(l))
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
