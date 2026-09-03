import SwiftUI
import OSLog

private let settingsLog = Logger(subsystem: "com.triptrack", category: "settings")

/// «Настройки» sheet (Figma 580:232, hints 1741:129) — the gear behind the Я
/// header. Three cards, grouped by what the row is ABOUT rather than by what
/// kind of control it wears:
///
/// 1. **Аккаунт** (signed-in only) — the canonical visibility and notification
///    switches, plus canon's «Аккаунт и синхронизация» chevron pulled up into
///    the same card. A one-row card sitting under a card of switches is a gap
///    pretending to be a group; the two promises about who can see you
///    («Публичный профиль», «Поездки на глобальной карте») only read together.
/// 2. **Приложение** — «Язык», «Тема», and one row, «Единицы и формат», that
///    opens `AppPreferencesView`. Words, then look, then numbers.
/// 3. **Поддержка** — «Написать автору», «Телеграм-канал», «Отправить логи».
///    The logs are not a tool: they are an attachment to a letter to the
///    author, which is the card they belong in and why the row now carries a
///    subtitle like its two neighbours.
///
/// What left this sheet, and where it went: «Страна» → «Мой профиль» (it is
/// profile data, not app config, and that row already existed); «Добавление в
/// попутчики» → Входящие → ⚙ (same server field, and the master switch right
/// above it already served the impulse); «Гараж» → the «Я» screen (a place
/// people want to walk into, not the bottom of a settings sheet); «Единицы» and
/// «Средняя скорость» → `AppPreferencesView`, one level down. Earlier passes
/// had already moved «Входящие» (the Home bell), «Поделиться профилем» (public
/// profile), «Выйти» (inside «Аккаунт и синхронизация») and «Фон профиля» (→
/// «Мой профиль»).
struct ProfileSettingsSheet: View {
    /// Открыть «Приватность» сразу при появлении (0.6.3).
    ///
    /// Нужно разовой карточке про видимость: её кнопка «Настроить» обязана
    /// приводить к тумблерам, а не к списку, где их ещё надо найти. Через флаг,
    /// а не через второй `PrivacySettingsView`: два экземпляра завели бы два
    /// загрузчика уведомлений, и каждый POST'ил бы все пять флагов поверх
    /// другого — см. комментарий на самом листе.
    var opensPrivacy: Bool = false

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    /// Feeds the live marker on «Аккаунт и синхронизация» — see `SyncState`.
    @ObservedObject private var syncQueue = SyncQueue.shared

    @AppStorage("distanceUnit") private var distanceUnit: String = "km"

    /// The «Уведомления» master over the server's notification prefs. Created
    /// here and owned here — nothing outside this sheet reads it.
    @StateObject private var notifications = NotificationSwitches()

    @State private var showLanguagePicker = false
    @State private var showThemePicker = false
    /// «Единицы и формат» — the once-per-install rows, one level down.
    @State private var showAppPrefs = false
    @State private var showCloudSync = false
    @State private var showDebugLogs = false
    /// «Приватность» — the three visibility switches, one level down.
    @State private var showPrivacy = false
    @State private var didOpenPrivacy = false
    #if DEBUG
    @State private var showTipJar = false
    #endif

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(l)

            ScrollView {
                VStack(spacing: 4) {
                    if auth.isSignedIn {
                        accountGroup(c, l)
                    }
                    appGroup(c, l)
                    supportGroup(c, l)
                    #if DEBUG
                    devGroup(c, l)
                    #endif
                    footer(c, l)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg)
        // Draws whichever «?» bubble is open, above every card in the sheet.
        // Applied at the root because a bubble drawn inside a row is painted
        // over by the groups below it — see `SettingsHintButton`.
        .settingsHintLayer()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("settings_sheet")
        // Keyed on the session: a guest has no account prefs to read, and a
        // sign-in that lands while this sheet is open must not leave the
        // switch that just appeared stuck in its loading state.
        .task(id: auth.isSignedIn) {
            guard auth.isSignedIn else { return }
            // Only the notification master is server-backed on THIS screen
            // now; /auth/me is asked for by «Приватность», which is the one
            // place that draws a row depending on the answer.
            await notifications.load()
        }
        .sheet(isPresented: $showLanguagePicker) {
            languagePicker(l)
        }
        .sheet(isPresented: $showThemePicker) {
            themePicker(l)
        }
        // Через `task` с паузой, а не из `onAppear`: вложенный лист, поднятый
        // посреди анимации показа родителя, UIKit молча роняет — и повторить
        // некому, флаг уже взведён.
        .onAppear {
            guard opensPrivacy, !didOpenPrivacy else { return }
            didOpenPrivacy = true
            // Неструктурированная `Task`, а НЕ `.task`: та привязана к времени
            // жизни вью и отменяется на первой же перерисовке — а перерисовка
            // здесь гарантирована, лист только что появился. Отменённая задача
            // молча не открывала «Приватность», и кнопка «Настроить» приводила
            // просто в список настроек.
            Task { @MainActor in
                // Пауза на анимацию показа родителя: вложенный лист, поднятый
                // посреди неё, UIKit роняет.
                try? await Task.sleep(for: .milliseconds(450))
                showPrivacy = true
            }
        }
        .sheet(isPresented: $showPrivacy) {
            // Same instance, not a second one: two loaders would each POST all
            // five notification flags and overwrite each other. See the type.
            PrivacySettingsView(notifications: notifications)
                .environmentObject(lang)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showAppPrefs) {
            AppPreferencesView()
                .environmentObject(lang)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showCloudSync) {
            CloudSyncView()
                .environmentObject(lang)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showDebugLogs) {
            DebugLogsView()
                .environmentObject(lang)
                .environmentObject(themeManager)
        }
        #if DEBUG
        .sheet(isPresented: $showTipJar) {
            TipJarDebugView()
        }
        #endif
    }

    // MARK: - Chrome

    /// The shared bar, so this sheet's chrome measures the same as every other
    /// screen's instead of a hand-sized row of its own. A sheet root has
    /// nothing to pop — it closes from the trailing side — so the back chevron
    /// is off and «×» is the one control (same shape as Discover). ProfileView
    /// hands the bar `navBarInSheet`, which is what lifts the row clear of the
    /// grabber UIKit draws over the sheet's top edge.
    private func navRow(_ l: LanguageManager.Language) -> some View {
        // NOT `CustomNavBar`: that bar centres its title and carries the 40pt
        // white nav circle with a shadow, which is right for a PUSHED screen
        // sitting over a map. Canon 580:232 heads this SHEET differently —
        // «Настройки» left-aligned at 22 heavy, and a flat 30pt grey close disc
        // with no shadow, the same `SheetCloseCircle` the garage sheets use.
        HStack(alignment: .center) {
            Text(AppStrings.settingsTitle(l))
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
        }
        .padding(.horizontal, 18)
        // The grabber UIKit draws over the sheet's top edge lands on the first
        // ~10pt, so the row starts below it.
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func rowDivider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.borderBright)
            .frame(height: 1)
    }

    // MARK: - Card A — account (signed-in only)

    /// Who can see you, what reaches you, and where the account itself is
    /// managed — one card, because they are one subject. The «Аккаунт и
    /// синхронизация» chevron used to be a card of its own directly underneath
    /// this one, which drew a 4pt gap between two halves of the same idea.
    private func accountGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            // «Публичный профиль», «Поездки на глобальной карте» and
            // «Добавление в попутчики» all live behind this row now — see
            // `PrivacySettingsView`. Three switches used to open this sheet,
            // which made Настройки look like a form.
            SettingsLinkRow(
                icon: "hand.raised.fill",
                title: AppStrings.privacyTitle(l),
                subtitle: AppStrings.privacyRowSub(l),
                action: { showPrivacy = true }
            )
            .accessibilityIdentifier("settings_privacy")

            rowDivider(c)

            SettingsToggleRow(
                icon: "bell.fill",
                title: AppStrings.settingsNotifications(l),
                hint: AppStrings.settingsHintNotifications(l),
                isOn: Binding(
                    get: { notifications.master },
                    set: { notifications.setMaster($0) }
                ),
                isEnabled: notifications.isLoaded
            )
            .accessibilityIdentifier("settings_notifications")

            rowDivider(c)

            // The row carries the state of the thing it opens: «выключена» /
            // «синхронизировано» / «3 в очереди», live. That marker spent 0.6.0
            // as a grey line under the name on the «Я» tab, where it was the
            // second thing on the screen and nothing could be done about it.
            SettingsIconRow(
                icon: settings.cloudSyncEnabled ? "icloud.fill" : "icloud.slash",
                title: AppStrings.settingsAccountSync(l),
                action: { showCloudSync = true }
            ) {
                HStack(spacing: 8) {
                    SyncStatusMarker(state: syncState, language: l)
                    SettingsRowChevron()
                }
            }
            .accessibilityIdentifier("settings_account_sync")
        }
        .surfaceCard(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.2), value: syncState)
    }

    private var syncState: SyncState {
        .current(
            enabled: settings.cloudSyncEnabled,
            isSyncing: syncQueue.isSyncing,
            pending: syncQueue.pendingCount,
            batchProcessed: syncQueue.batchProcessed,
            batchTotal: syncQueue.batchTotal
        )
    }

    // MARK: - Card B — the app itself

    /// Words, then look, then numbers. Guests get this card too — nothing in it
    /// needs a session.
    private func appGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let lng = l
        return VStack(spacing: 0) {
            SettingsIconRow(
                icon: "character.bubble",
                title: AppStrings.lang(l),
                action: { showLanguagePicker = true }
            ) {
                SettingsRowValue(text: l.endonym)
            }
            .accessibilityIdentifier("settings_language")

            rowDivider(c)

            SettingsIconRow(
                // The icon carries the current mode, same glyph the picker
                // badges it with — a fixed sun next to the value «Тёмная»
                // reads as a stale row.
                icon: themeBadge(themeManager.mode),
                title: AppStrings.theme(l),
                action: { showThemePicker = true }
            ) {
                SettingsRowValue(text: themeLabel(themeManager.mode, l))
            }
            .accessibilityIdentifier("settings_theme")

            rowDivider(c)

            // «Единицы» and «Средняя скорость» live behind this row now (see
            // `AppPreferencesView`). The current unit still prints on the right
            // edge, so «в чём считает?» is answered without opening anything —
            // which is what makes the nesting a cleanup and not a hiding place.
            SettingsIconRow(
                icon: "ruler",
                title: AppStrings.settingsAppPrefs(l),
                action: { showAppPrefs = true }
            ) {
                HStack(spacing: 6) {
                    SettingsRowValue(text: GarageFormat.distanceShort(distanceUnit, lng: lng))
                    SettingsRowChevron()
                }
            }
            .accessibilityIdentifier("settings_app_prefs")
        }
        .surfaceCard(cornerRadius: 16)
    }

    private func themeLabel(_ mode: ThemeManager.Mode, _ l: LanguageManager.Language) -> String {
        switch mode {
        case .system: return AppStrings.themeSystem(l)
        case .dark: return AppStrings.dark(l)
        case .light: return AppStrings.light(l)
        }
    }

    private func themeBadge(_ mode: ThemeManager.Mode) -> String {
        switch mode {
        case .system: return "gearshape.fill"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    // MARK: - Pickers (Figma 1685:119 / 176 / 233)

    private func languagePicker(_ l: LanguageManager.Language) -> some View {
        // RU first, as canon draws it, then EN, then the five added in 0.6.1
        // — `Language.displayOrder`, not `allCases`, which is declaration
        // order and would lead with English on a Russian phone.
        SettingsOptionPicker(
            title: AppStrings.lang(l),
            options: LanguageManager.Language.displayOrder,
            selection: l,
            footnote: AppStrings.languagePickerFootnote(l),
            badge: { $0.badge },
            // Endonyms: every language names itself, in itself. Not copy.
            label: { $0.endonym },
            onSelect: { lang.language = $0 },
            accessibilityPrefix: "settings_language"
        )
    }

    private func themePicker(_ l: LanguageManager.Language) -> some View {
        SettingsOptionPicker(
            title: AppStrings.theme(l),
            options: [ThemeManager.Mode.system, .light, .dark],
            selection: themeManager.mode,
            footnote: AppStrings.themePickerFootnote(l),
            badge: { themeBadge($0) },
            badgeIsSymbol: true,
            label: { themeLabel($0, l) },
            onSelect: { themeManager.mode = $0 },
            accessibilityPrefix: "settings_theme"
        )
    }

    // MARK: - Card C — the author, and what to send them

    /// The logs are here and not in a tools card because a log file is not a
    /// tool: it is the attachment to the letter directly above it. Three rows
    /// of the same shape, so the one that used to wear a bare chevron now
    /// carries a subtitle like its neighbours.
    private func supportGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            SettingsLinkRow(
                icon: "envelope.fill",
                title: AppStrings.writeAuthor(l),
                subtitle: AppStrings.settingsWriteToAuthorSub(l),
                action: { openURL("mailto:\(Self.authorEmail)") }
            )
            .accessibilityIdentifier("settings_write_author")

            rowDivider(c)

            SettingsLinkRow(
                icon: "paperplane.fill",
                assetIcon: "TelegramIcon",
                title: AppStrings.telegramChannel(l),
                subtitle: AppStrings.settingsTelegramSub(l),
                action: { openURL(Self.telegramChannelURL) }
            )
            .accessibilityIdentifier("settings_telegram")

            rowDivider(c)

            SettingsLinkRow(
                icon: "ladybug.fill",
                title: AppStrings.settingsSendLogs(l),
                subtitle: AppStrings.settingsSendLogsSub(l),
                action: { showDebugLogs = true }
            )
            .accessibilityIdentifier("settings_send_logs")
        }
        .surfaceCard(cornerRadius: 16)
    }

    /// The one address the app publishes (privacy policy + terms). Swap it the
    /// day there is a dedicated feedback inbox — the row's copy already
    /// promises «отзывы и идеи», not a legal channel.
    private static let authorEmail = "privacy@trip-track.app"
    private static let telegramChannelURL = "https://t.me/onezee_co"

    // MARK: - Footer

    private func footer(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("TRIP TRACK")
                    .font(.custom("PressStart2P-Regular", size: 8))
                    .foregroundStyle(AppTheme.accent)
                Text("· v\(version) · OneZee")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }

            HStack(spacing: 16) {
                Button {
                    Haptics.tap()
                    UIApplication.shared.open(AppConfig.privacyPolicyURL(l))
                } label: {
                    Text(AppStrings.privacyPolicy(l))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .underline()
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    UIApplication.shared.open(AppConfig.termsURL(l))
                } label: {
                    Text(AppStrings.termsOfService(l))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    #if DEBUG
    // MARK: - Dev (debug builds only)

    /// TEMPORARY. Replays first-run flows without deleting the app: flipping
    /// `hasCompletedOnboarding` is what the app root watches, so the
    /// onboarding takes over immediately.
    ///
    /// Wrapped in `#if DEBUG` so it cannot ship — a release build doesn't
    /// compile this group at all. Delete the whole block when the onboarding
    /// pass is done.
    private func devGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionLabel(text: "DEV · только debug-сборка")
                .padding(.leading, 2)
                .padding(.top, 6)

            VStack(spacing: 0) {
                SettingsIconRow(
                    icon: "arrow.counterclockwise",
                    iconColor: AppTheme.accent,
                    iconBg: AppTheme.accentBg,
                    title: "Пройти онбординг заново",
                    action: { restartOnboarding() }
                ) {
                    SettingsRowChevron()
                }

                rowDivider(c)

                // The finish screen is otherwise reachable only by driving far
                // enough for the trip to survive the junk filter, which makes
                // every change to it a trip outside.
                SettingsIconRow(
                    icon: "flag.checkered",
                    iconColor: AppTheme.accent,
                    iconBg: AppTheme.accentBg,
                    title: "Экран финиша (отладка)",
                    action: { showDebugFinishScreen() }
                ) {
                    SettingsRowChevron()
                }

                rowDivider(c)

                // The money-tract probe. Answers «does a purchase complete and
                // what does Apple hand back», not «can we take donations» —
                // see TipJarService for why a green result here proves less
                // than it looks like it does.
                SettingsIconRow(
                    icon: "cup.and.saucer.fill",
                    iconColor: AppTheme.accent,
                    iconBg: AppTheme.accentBg,
                    title: "Проба доната (StoreKit)",
                    action: {
                        Haptics.tap()
                        showTipJar = true
                    }
                ) {
                    SettingsRowChevron()
                }
            }
            .surfaceCard(cornerRadius: 16)
        }
    }

    private func showDebugFinishScreen() {
        Haptics.action()
        dismiss()
        // After the sheet is gone: the summary is presented from the app root
        // and would otherwise queue behind this one.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            mapVM.debugShowLastTripSummary()
        }
    }

    private func restartOnboarding() {
        Haptics.action()
        // Close settings first: the root swaps its whole content for the
        // onboarding, and doing that under a presented sheet leaves the
        // sheet floating over it.
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
    }
    #endif

    // MARK: - Handlers

    private func openURL(_ string: String) {
        if let u = URL(string: string) {
            UIApplication.shared.open(u)
        }
    }
}

// MARK: - Rows canon draws that the shared master can't

/// Canon's switch row (580:253). Geometry is `SettingsIconRow`'s to the point
/// — 30pt icon square, 12pt gap, 14/13 padding, 14.5 semibold label — but the
/// «?» has to sit immediately after the label, and that component's only
/// opening is its trailing slot. A hint parked next to the switch stops
/// reading as a footnote to the label and starts reading as part of the
/// control, which is the one thing it must not be.
private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    /// Already-localized hint body; nil = no «?» on this row.
    var hint: String?
    let isOn: Binding<Bool>
    /// False while the server value is still loading — the switch renders
    /// dimmed rather than inviting a tap that would save a guess.
    var isEnabled: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.accentBg)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 30, height: 30)

            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // The label yields the row's width last: on a 360pt phone
                // «Поездки на глобальной карте» plus disc plus switch is the
                // tight case, and it should shrink rather than push the «?» off.
                .layoutPriority(1)

            if let hint {
                SettingsHintButton(text: hint)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.accent)
                // Canon's switch is 46×28 — the system's 51×31 at 0.9.
                .scaleEffect(0.9)
                // 28, not 44: `scaleEffect` is a geometry effect and does not
                // shrink layout size, so a 44 frame made the switch the tallest
                // thing in the row and every switch row 70pt against canon's 56
                // — three of them stacked in one card is where that read as a
                // sparse, unfinished list. The 44pt target is grown back with
                // padding and pulled out of layout again.
                .frame(width: 46, height: 28)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .padding(.vertical, -8)
                .disabled(!isEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}

/// Canon's author link (1691:540): the same row geometry with a second line
/// under the title. `SettingsIconRow` has one label and lives in a file this
/// screen doesn't own, so the subtitle variant is built here against the same
/// constants rather than by widening a component four other screens use.
private struct SettingsLinkRow: View {
    let icon: String
    /// Bundled template asset, when the glyph is a brand mark rather than an
    /// SF Symbol.
    var assetIcon: String?
    let title: String
    let subtitle: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accentBg)
                    if let assetIcon {
                        Image(assetIcon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(AppTheme.accent)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                SettingsRowChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
