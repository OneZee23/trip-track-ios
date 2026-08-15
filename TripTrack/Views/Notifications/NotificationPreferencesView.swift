import SwiftUI
import OSLog

private let prefsLog = Logger(subsystem: "com.triptrack", category: "notifications.prefs")

private struct NotificationPrefsResponse: Codable {
    let notifyReactions: Bool
    let notifyFollows: Bool
    /// Optional: the deployed backend predates feat/trip-comments and does
    /// not return this key yet — a non-optional Bool would fail the whole
    /// decode against prod. Missing = server default (true).
    let notifyComments: Bool?
    let notifyWeeklyRecap: Bool
    /// Fix 6: same optional-for-backward-compat treatment as
    /// `notifyComments` above — the deployed backend predates
    /// feat/trip-companions on some environments.
    let notifyCompanions: Bool?
}

private struct NotificationPrefsUpdateRequest: Codable {
    let notifyReactions: Bool?
    let notifyFollows: Bool?
    let notifyComments: Bool?
    let notifyWeeklyRecap: Bool?
    let notifyCompanions: Bool?
}

/// Account-level toggles for each notification category. Lives behind a
/// row in Profile so a user who hates push spam can mute reactions/
/// follows without nuking system-level notification permission for the
/// whole app (which would also kill local trip-start prompts).
///
/// Each toggle drives BOTH the in-app inbox row AND the APNs push, so
/// flipping one to off makes that category effectively invisible until
/// the user re-enables it.
struct NotificationPreferencesView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var notifyReactions = true
    @State private var notifyFollows = true
    @State private var notifyComments = true
    @State private var notifyWeeklyRecap = true
    /// Fix 6: the server has had `notifyCompanions` since the
    /// trip-companions rollout, but this screen never offered a switch for
    /// it — every other category has one.
    @State private var notifyCompanions = true
    @State private var isLoaded = false
    /// Debounced save. Flipping several switches in a row (or one switch
    /// twice) collapses into a single POST carrying the final state.
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let lng = lang.language

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    intro(c: c, lng: lng)

                    VStack(spacing: 0) {
                        toggleRow(
                            icon: "heart.fill",
                            iconTint: .red,
                            title: AppStrings.chipReactions(lng),
                            subtitle: AppStrings.notificationPreferencesWhenSomeoneReacts(lng),
                            isOn: $notifyReactions,
                            c: c,
                        )
                        Divider().padding(.leading, 56)
                        toggleRow(
                            icon: "person.fill.checkmark",
                            iconTint: AppTheme.accent,
                            title: AppStrings.chipFollows(lng),
                            subtitle: AppStrings.notificationPreferencesWhenSomeoneFollows(lng),
                            isOn: $notifyFollows,
                            c: c,
                        )
                        Divider().padding(.leading, 56)
                        toggleRow(
                            icon: "text.bubble.fill",
                            iconTint: AppTheme.green,
                            title: AppStrings.notificationPreferencesComments(lng),
                            subtitle: AppStrings.notificationPreferencesWhenSomeoneComments(lng),
                            isOn: $notifyComments,
                            c: c,
                        )
                        Divider().padding(.leading, 56)
                        toggleRow(
                            icon: "calendar.badge.clock",
                            iconTint: AppTheme.blue,
                            title: AppStrings.notificationPreferencesWeeklyRecap(lng),
                            subtitle: AppStrings.notificationPreferencesEveryMondayHow(lng),
                            isOn: $notifyWeeklyRecap,
                            c: c,
                        )
                        Divider().padding(.leading, 56)
                        toggleRow(
                            icon: "person.2.fill",
                            iconTint: AppTheme.purple,
                            title: AppStrings.notifyCompanionsTitle(lang.language),
                            subtitle: AppStrings.notifyCompanionsSubtitle(lang.language),
                            isOn: $notifyCompanions,
                            c: c,
                        )
                    }
                    .surfaceCard(cornerRadius: 14)

                    footer(c: c, lng: lng)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(c.bg)
            .navigationTitle(AppStrings.settingsNotifications(lng))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
            .task { await load() }
        }
    }

    private func intro(c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppStrings.notificationPreferencesWhatToNotify(lng))
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(c.text)
            Text(AppStrings.notificationPreferencesPickWhatYou(lng))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleRow(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        c: AppTheme.Colors,
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Toggle — pinned via fixedSize so the subtitle below can wrap
            // freely without dragging the switch around.
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.accent)
                // Only the initial load gates interaction. It used to also
                // disable on `isSaving`, which flipped every switch into
                // and out of the disabled style around each POST — a full
                // re-render of the card on every tap, which is what made
                // the sheet twitch.
                .disabled(!isLoaded)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    // Gate on `isLoaded` — without this, the assignment
                    // inside `load()` itself fires `.onChange` and
                    // schedules a redundant POST with values that just
                    // came back from the server.
                    guard isLoaded else { return }
                    saveTask?.cancel()
                    saveTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !Task.isCancelled else { return }
                        await save()
                    }
                }
        }
        .padding(14)
    }

    private func footer(c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        Text(AppStrings.notificationPreferencesNotificationsYouTurn(lng))
            .font(.system(size: 11))
            .foregroundStyle(c.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func load() async {
        guard !isLoaded else { return }
        do {
            let res: NotificationPrefsResponse = try await APIClient.shared.post(
                APIEndpoint.notificationPrefsGet, body: EmptyRequest())
            notifyReactions = res.notifyReactions
            notifyFollows = res.notifyFollows
            notifyComments = res.notifyComments ?? true
            notifyWeeklyRecap = res.notifyWeeklyRecap
            notifyCompanions = res.notifyCompanions ?? true
            isLoaded = true
        } catch {
            prefsLog.error("load failed: \(error.localizedDescription)")
            // Optimistic default — leave toggles ON so the UI doesn't
            // look broken on a load failure. Save will reconcile when
            // the network is healthy again.
            isLoaded = true
        }
    }

    private func save() async {
        guard isLoaded else { return }
        do {
            let _: NotificationPrefsResponse = try await APIClient.shared.post(
                APIEndpoint.notificationPrefsUpdate,
                body: NotificationPrefsUpdateRequest(
                    notifyReactions: notifyReactions,
                    notifyFollows: notifyFollows,
                    // Ignored (not 400'd) by the pre-comments backend: its
                    // ValidationPipe runs without forbidNonWhitelisted, so
                    // sending the key early is safe.
                    notifyComments: notifyComments,
                    notifyWeeklyRecap: notifyWeeklyRecap,
                    notifyCompanions: notifyCompanions,
                ))
        } catch {
            prefsLog.error("save failed: \(error.localizedDescription)")
        }
    }
}
