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
            // fake-succeed on the one thing nobody may be wrong about. While
            // the question is out it renders inert instead of absent, so the
            // card can't grow a row after it is already on screen.
            if auth.isPublicProfile != nil || probing {
                PrivacyToggleRow(
                    icon: "globe",
                    tint: AppTheme.accent,
                    title: AppStrings.publicProfileTitle(l),
                    subtitle: AppStrings.privacyPublicProfileSub(l),
                    isOn: publicProfileBinding,
                    isEnabled: auth.isPublicProfile != nil
                )
                .accessibilityIdentifier("settings_public_profile")

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
