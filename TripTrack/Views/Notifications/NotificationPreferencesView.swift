import SwiftUI
import OSLog

private let prefsLog = Logger(subsystem: "com.triptrack", category: "notifications.prefs")

private struct NotificationPrefsResponse: Codable {
    let notifyReactions: Bool
    let notifyFollows: Bool
}

private struct NotificationPrefsUpdateRequest: Codable {
    let notifyReactions: Bool?
    let notifyFollows: Bool?
}

/// Account-level toggles for each notification category. Lives behind a
/// row in Profile so a user who hates push spam can mute reactions/
/// follows without nuking system-level notification permission for the
/// whole app (which would also kill local trip-start prompts).
///
/// Both toggles drive BOTH the in-app inbox row AND the APNs push, so
/// flipping one to off makes that category effectively invisible until
/// the user re-enables it.
struct NotificationPreferencesView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var notifyReactions = true
    @State private var notifyFollows = true
    @State private var isLoaded = false
    @State private var isSaving = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    intro(c: c, isRu: isRu)

                    VStack(spacing: 0) {
                        toggleRow(
                            icon: "heart.fill",
                            iconTint: .red,
                            title: isRu ? "Реакции" : "Reactions",
                            subtitle: isRu
                                ? "Когда кто-то отреагирует на Вашу публичную поездку"
                                : "When someone reacts to your public trip",
                            isOn: $notifyReactions,
                            c: c,
                        )
                        Divider().padding(.leading, 56)
                        toggleRow(
                            icon: "person.fill.checkmark",
                            iconTint: AppTheme.accent,
                            title: isRu ? "Подписки" : "Follows",
                            subtitle: isRu
                                ? "Когда кто-то подписывается на Ваш профиль"
                                : "When someone follows your profile",
                            isOn: $notifyFollows,
                            c: c,
                        )
                    }
                    .surfaceCard(cornerRadius: 14)

                    footer(c: c, isRu: isRu)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(c.bg)
            .navigationTitle(isRu ? "Уведомления" : "Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
            .task { await load() }
        }
    }

    private func intro(c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isRu ? "Что Вас уведомлять" : "What to notify you about")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(c.text)
            Text(isRu
                 ? "Здесь вы выбираете, о чём приходит уведомление — и в push'ах, и в ленте уведомлений внутри приложения. Системные настройки iOS остаются под Вашим контролем отдельно."
                 : "Pick what you want to hear about — both in push notifications and in the in-app inbox. System-level iOS notification settings remain separate.")
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
                .disabled(!isLoaded || isSaving)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    // Gate on `isLoaded` — without this, the assignment
                    // inside `load()` itself fires `.onChange` and
                    // schedules a redundant POST with values that just
                    // came back from the server.
                    guard isLoaded else { return }
                    Task { await save() }
                }
        }
        .padding(14)
    }

    private func footer(c: AppTheme.Colors, isRu: Bool) -> some View {
        Text(isRu
             ? "Уведомления, которые Вы выключите, не будут приходить ни на телефон, ни в приложение. Включить обратно можно в любой момент."
             : "Notifications you turn off won't reach your phone OR the in-app inbox. You can turn them back on any time.")
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
        isSaving = true
        defer { isSaving = false }
        do {
            let _: NotificationPrefsResponse = try await APIClient.shared.post(
                APIEndpoint.notificationPrefsUpdate,
                body: NotificationPrefsUpdateRequest(
                    notifyReactions: notifyReactions,
                    notifyFollows: notifyFollows,
                ))
        } catch {
            prefsLog.error("save failed: \(error.localizedDescription)")
        }
    }
}
