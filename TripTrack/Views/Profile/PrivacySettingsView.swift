import SwiftUI

/// «Приватность» — who can see you, one level down from Настройки.
///
/// The three switches used to be the first thing the settings sheet showed:
/// «Публичный профиль», «Поездки на глобальной карте» and «Добавление в
/// попутчики», each with a «?» bubble, stacked above everything a person opens
/// Настройки for. They are decided once and then left alone for months, and
/// three switches in a row read as a form to fill in rather than as an answer
/// to a question. Re-homed behind one row, the way «Единицы и формат» was.
///
/// The subtitle replaces the «?»: with the whole screen to itself each switch
/// can simply say what it does, instead of hiding it behind a bubble that has
/// to be tapped, read, and dismissed. `settingsHint*` copy stays in AppStrings
/// — CloudSyncView still draws its own copy of the profile toggle.
///
/// Presented as a sheet FROM the settings sheet, exactly like
/// `AppPreferencesView` — see that file for why a push is not an option here.
struct PrivacySettingsView: View {
    /// Owned by `ProfileSettingsSheet` and passed in: the companion switch and
    /// the «Уведомления» master are two views onto ONE server payload, and two
    /// loaders would each write all five flags over each other's changes.
    @ObservedObject var notifications: NotificationSwitches

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared

    /// Optimistic value for «Публичный профиль» while the server write is in
    /// flight; nil = mirror `auth.isPublicProfile`.
    @State private var publicProfileDraft: Bool?
    /// True while /auth/me is in flight — the row draws inert rather than
    /// absent for that moment. See the F2 note on the row itself.
    @State private var visibilityDrafts: [ProfileVisibilityBlock: Bool] = [:]
    @State private var visibilityGenerations: [ProfileVisibilityBlock: Int] = [:]
    @State private var probing = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(l)

            ScrollView {
                VStack(spacing: 0) {
                    card(c, l)
                    footnote(c, l)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg)
        // Three switches and a caption do not need a full-height sheet, and a
        // half one keeps the settings card it came from in view behind it.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("privacy_screen")
        .task {
            // The one caller of /auth/me on this path. Before this screen
            // existed the switch was drawn only if some OTHER screen had
            // already asked (F2), so it materialised in the settings card on
            // the way back from «Аккаунт и синхронизация».
            guard auth.isSignedIn else { return }
            probing = true
            await auth.refreshMe()
            probing = false
        }
    }

    // MARK: - Chrome

    private func navRow(_ l: LanguageManager.Language) -> some View {
        HStack(alignment: .center) {
            Text(AppStrings.privacyTitle(l))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(AppTheme.colors(for: scheme).text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                SheetCloseCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.closeSheet(l))
            .accessibilityIdentifier("privacy_close")
        }
        .padding(.horizontal, 18)
        // The grabber UIKit draws over the sheet's top edge lands on the first
        // ~10pt, so the row starts below it.
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Card

    private func card(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            // F2 gating, same as CloudSyncView's copy of this toggle: OPERABLE
            // only after a successful /auth/me. An old server silently drops
            // unknown profile-update fields, so an ungated switch would
            // fake-succeed on the one thing nobody may be wrong about.
            //
            // The row's PRESENCE keys off being signed in, not off the answer.
            // It used to key off `isPublicProfile != nil || probing`, which
            // holds while the request is in flight and stops holding the
            // moment it fails — so on a bad connection the switch appeared,
            // sat there for a second, and vanished under the user's finger.
            // A row that disappears reads as a bug in the app, not as a
            // failed request; inert-with-a-reason is the honest version.
            if auth.isSignedIn {
                PrivacyToggleRow(
                    icon: "globe",
                    tint: AppTheme.accent,
                    title: AppStrings.publicProfileTitle(l),
                    subtitle: AppStrings.privacyPublicProfileSub(l),
                    isOn: publicProfileBinding,
                    isEnabled: auth.isPublicProfile != nil
                )
                .accessibilityIdentifier("settings_public_profile")

                // Inert and unexplained is the other half of the old bug: the
                // switch looked broken rather than unanswered. Only shown once
                // the request has actually come back empty-handed.
                if auth.isPublicProfile == nil && !probing {
                    Text(AppStrings.privacyProfileUnavailable(l))
                        .font(.inter(12))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                rowDivider(c)
            }

            // Directly under the profile switch, and never anywhere else: two
            // promises about who can see you are only readable next to each
            // other. This one is the narrower of the two — public trips only,
            // route ends trimmed — which is exactly what its subtitle says.
            PrivacyToggleRow(
                icon: "map.fill",
                tint: AppTheme.blue,
                title: AppStrings.settingsPublicProfile(l),
                subtitle: AppStrings.publishOnGlobeSubtitle(l),
                isOn: Binding(
                    get: { settings.showOnPublicMap },
                    set: { setShowOnPublicMap($0) }
                )
            )
            .accessibilityIdentifier("settings_public_map")

            rowDivider(c)

            // Кто что видит внутри ОТКРЫТОГО профиля (0.6.3). Стоят под
            // «Публичным профилем» намеренно: тот решает, виден ли профиль
            // вообще, эти — что именно в нём видно, и порядок читается как
            // сужение, а не как второй независимый список.
            if auth.isSignedIn {
                // Заголовок и вступление: четыре тумблера, приехавшие без
                // объяснения в общий список приватности, читаются как ещё
                // четыре независимых переключателя, а не как одна ось «что
                // видно внутри открытого профиля».
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.visibilityTitle(l))
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.22)
                        .foregroundStyle(c.textTertiary)
                        .textCase(.uppercase)
                    Text(AppStrings.visibilityIntro(l))
                        .font(.inter(11.5))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ForEach(ProfileVisibilityBlock.allCases, id: \.self) { block in
                    PrivacyToggleRow(
                        icon: Self.icon(for: block),
                        tint: Self.tint(for: block),
                        title: Self.title(for: block, l),
                        subtitle: Self.subtitle(for: block, l),
                        isOn: visibilityBinding(block),
                        isEnabled: auth.visibility != nil
                    )
                    .accessibilityIdentifier("settings_visibility_\(String(describing: block))")

                    rowDivider(c)
                }

                if auth.visibility == nil {
                    // Инертный переключатель без причины читается как баг в
                    // приложении, а не как незавершённый деплой.
                    Text(AppStrings.visibilityUnavailable(l))
                        .font(.inter(12))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                Text(AppStrings.visibilityFootnote(l))
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                rowDivider(c)

                // Единственный способ проверить тумблеры — посмотреть
                // результат. Экран превью уже существует (он же чужой профиль
                // с isOwnProfile), и с 0.6.3 он честно скрывает выключенные
                // блоки, так что это действительно проверка, а не витрина.
                Button {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .openOwnProfilePreview, object: nil)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppStrings.visibilityPreviewLink(l))
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                            Text(AppStrings.visibilityPreviewSub(l))
                                .font(.system(size: 11.5))
                                .foregroundStyle(c.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings_visibility_preview")

                rowDivider(c)
            }

            PrivacyToggleRow(
                icon: "person.2.fill",
                tint: AppTheme.purple,
                title: AppStrings.settingsCompanionAdds(l),
                subtitle: AppStrings.privacyCompanionSub(l),
                isOn: Binding(
                    get: { notifications.companions },
                    set: { notifications.setCompanions($0) }
                ),
                isEnabled: notifications.isLoaded
            )
            .accessibilityIdentifier("settings_companion_adds")
        }
        .surfaceCard(cornerRadius: 16)
    }

    private func rowDivider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.borderBright)
            // Indented to the label, not to the card edge: a full-bleed rule
            // between rows that each carry an icon disc cuts the discs into a
            // column of their own.
            .frame(height: 1)
            .padding(.leading, 56)
    }

    private func footnote(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        Text(AppStrings.privacyFootnote(l))
            .font(.system(size: 11.5))
            .foregroundStyle(c.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    // MARK: - Writes

    /// Optimistic toggle with revert: flips immediately, sends the
    /// isPublic-only payload, snaps back (+ error haptic) on failure. Same
    /// contract as CloudSyncView's binding — both are views onto one server
    /// field, so they read the same `auth.isPublicProfile` and can't drift.
    private var publicProfileBinding: Binding<Bool> {
        Binding(
            get: { publicProfileDraft ?? auth.isPublicProfile ?? true },
            set: { newValue in
                publicProfileDraft = newValue
                Task {
                    let ok = await auth.setPublicProfile(newValue)
                    if !ok { Haptics.error() }
                    // Success → auth.isPublicProfile == newValue already;
                    // failure → dropping the draft reverts the toggle.
                    publicProfileDraft = nil
                }
            }
        )
    }

    // MARK: - Видимость блоков (0.6.3)

    /// Оптимистичный тумблер с откатом: сервер — источник истины, но ждать
    /// круговой ответ, чтобы переключатель сдвинулся, читается как залипание.
    private func visibilityBinding(_ block: ProfileVisibilityBlock) -> Binding<Bool> {
        Binding(
            get: { visibilityDrafts[block] ?? auth.visibility?.value(block) ?? true },
            set: { newValue in
                visibilityDrafts[block] = newValue
                // Поколение на блок: медленный ПРЕДЫДУЩИЙ запрос, вернувшись
                // после нового переключения, снимал бы чужой драфт — и тумблер
                // отскакивал бы к устаревшему значению под пальцем.
                visibilityGenerations[block, default: 0] += 1
                let generation = visibilityGenerations[block]
                Task {
                    let ok = await auth.setVisibility(block, newValue)
                    if !ok { Haptics.error() }
                    guard visibilityGenerations[block] == generation else { return }
                    visibilityDrafts[block] = nil
                }
            }
        )
    }

    private static func icon(for block: ProfileVisibilityBlock) -> String {
        switch block {
        case .counters: return "number"
        case .stats: return "chart.bar.fill"
        case .map: return "map.fill"
        case .achievements: return "rosette"
        }
    }

    private static func tint(for block: ProfileVisibilityBlock) -> Color {
        switch block {
        case .counters: return AppTheme.blue
        case .stats: return AppTheme.accent
        case .map: return AppTheme.green
        case .achievements: return AppTheme.yellow
        }
    }

    private static func title(
        for block: ProfileVisibilityBlock, _ l: LanguageManager.Language
    ) -> String {
        switch block {
        case .counters: return AppStrings.visibilityCounters(l)
        case .stats: return AppStrings.visibilityStats(l)
        case .map: return AppStrings.visibilityMap(l)
        case .achievements: return AppStrings.visibilityAchievements(l)
        }
    }

    private static func subtitle(
        for block: ProfileVisibilityBlock, _ l: LanguageManager.Language
    ) -> String {
        switch block {
        case .counters: return AppStrings.visibilityCountersSub(l)
        case .stats: return AppStrings.visibilityStatsSub(l)
        case .map: return AppStrings.visibilityMapSub(l)
        case .achievements: return AppStrings.visibilityAchievementsSub(l)
        }
    }

    /// Mutate-then-sync with a guard on unchanged values so redundant server
    /// syncs never fire.
    private func setShowOnPublicMap(_ value: Bool) {
        guard settings.showOnPublicMap != value else { return }
        settings.showOnPublicMap = value
        Task { await auth.syncProfileToServer(refreshFeedAfter: false) }
    }
}

// MARK: - Row

/// Icon disc, title, one line of what the switch does, switch. The settings
/// sheet's `SettingsToggleRow` has a «?» bubble instead of the subtitle and an
/// accent disc for every row; here each row gets its own tint, because three
/// identical orange discs in a card of three rows is a pattern, not a list.
private struct PrivacyToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>
    /// False while the server value is still loading — the switch renders
    /// dimmed rather than inviting a tap that would save a guess.
    var isEnabled: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.accent)
                // Canon's switch is 46×28 — the system's 51×31 at 0.9.
                // `scaleEffect` is a geometry effect and does not shrink
                // layout, so the frame states the drawn size and the 44pt
                // target is grown with padding and pulled back out again.
                .scaleEffect(0.9)
                .frame(width: 46, height: 28)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .padding(.vertical, -8)
                .disabled(!isEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}
