import SwiftUI

struct CloudSyncView: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var syncQueue = SyncQueue.shared
    @ObservedObject private var auth = AuthService.shared

    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showEnableConfirm = false
    @State private var showBlockedList = false
    @AppStorage("com.triptrack.sync.firstToggleShown") private var firstToggleShown = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Hero icon + state
                    heroSection(c, isRu: isRu)

                    // ON/OFF toggle (pill style matching theme/language cards)
                    toggleCard(c, isRu: isRu)

                    // Current status card
                    statusCard(c, isRu: isRu)

                    // What gets synced
                    infoCard(
                        icon: "arrow.up.arrow.down.circle.fill",
                        iconColor: AppTheme.blue,
                        title: isRu ? "Что синхронизируется" : "What is synced",
                        body: isRu
                            ? "Поездки, транспорт, статистика, настройки и фото."
                            : "Trips, vehicles, stats, settings, and photos.",
                        c: c
                    )

                    infoCard(
                        icon: "photo.on.rectangle.angled",
                        iconColor: AppTheme.accent,
                        title: isRu ? "Фото" : "Photos",
                        body: isRu
                            ? "Миниатюры уезжают на сервер сразу. Оригиналы — только по Wi-Fi, чтобы экономить мобильный трафик."
                            : "Thumbnails upload instantly. Originals upload on Wi-Fi only to save mobile data.",
                        c: c
                    )

                    infoCard(
                        icon: "externaldrive.fill.badge.icloud",
                        iconColor: AppTheme.blue,
                        title: isRu ? "Где хранится" : "Where it's stored",
                        body: isRu
                            ? "Данные — на сервере TripTrack. Фото — в объектном хранилище Cloudflare R2 с ограниченным доступом."
                            : "Data on TripTrack server. Photos in Cloudflare R2 object storage with access-limited URLs.",
                        c: c
                    )

                    infoCard(
                        icon: "lock.shield.fill",
                        iconColor: .green,
                        title: isRu ? "Приватность" : "Privacy",
                        body: isRu
                            ? "Аккаунт привязан к Apple ID. Только Вы видите свои поездки, если не сделаете их публичными."
                            : "Account tied to your Apple ID. Only you see your trips unless you make them public.",
                        c: c
                    )

                    infoCard(
                        icon: "icloud.slash",
                        iconColor: c.textTertiary,
                        title: isRu ? "Если выключить" : "If disabled",
                        body: isRu
                            ? "Новые изменения останутся только на этом устройстве. При повторном включении — все накопленные данные уедут на сервер пачкой."
                            : "New changes stay on this device only. Re-enabling uploads everything accumulated in one batch.",
                        c: c
                    )

                    if auth.isSignedIn {
                        blockedEntry(c, isRu: isRu)
                        accountActions(c, isRu: isRu)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationDestination(isPresented: $showBlockedList) {
                BlockedListView()
            }
            .alert(
                isRu ? "Включить синхронизацию?" : "Turn on cloud sync?",
                isPresented: $showEnableConfirm
            ) {
                Button(isRu ? "Отмена" : "Cancel", role: .cancel) {}
                Button(isRu ? "Включить" : "Turn on") {
                    enableCloudSync()
                }
            } message: {
                Text(isRu
                     ? "Ваши поездки, фото (с удалёнными метаданными), автомобили и настройки будут загружены на наш сервер в ЕС и доступны на других Ваших устройствах. Вы можете отключить в любой момент. Подробнее — в Политике конфиденциальности."
                     : "Your trips, photos (with metadata stripped), vehicles, and settings will be uploaded to our EU server so you can access them on your other devices. You can turn this off anytime. See our Privacy Policy for details.")
            }
            .alert(
                AppStrings.signOutConfirmTitle(lang.language),
                isPresented: $showSignOutAlert
            ) {
                Button(AppStrings.cancel(lang.language), role: .cancel) {}
                Button(AppStrings.signOut(lang.language), role: .destructive) {
                    Task {
                        await auth.signOut()
                        dismiss()
                    }
                }
            } message: {
                Text(AppStrings.signOutConfirmMessage(lang.language))
            }
            .alert(
                AppStrings.deleteAccountConfirmTitle(lang.language),
                isPresented: $showDeleteAccountAlert
            ) {
                Button(AppStrings.cancel(lang.language), role: .cancel) {}
                Button(AppStrings.deleteAccount(lang.language), role: .destructive) {
                    Task { await performDeleteAccount() }
                }
            } message: {
                Text(AppStrings.deleteAccountConfirmMessage(lang.language))
            }
            .alert(
                AppStrings.deleteAccountFailed(lang.language),
                isPresented: Binding(
                    get: { deleteAccountError != nil },
                    set: { if !$0 { deleteAccountError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountError ?? "")
            }
            .background(c.bg)
            .navigationTitle(isRu ? "Синхронизация" : "Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
        }
    }

    // MARK: - Sections

    private func heroSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: settings.cloudSyncEnabled ? "icloud.fill" : "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(settings.cloudSyncEnabled ? AppTheme.blue : c.textTertiary)
            Text(settings.cloudSyncEnabled
                 ? (isRu ? "Синхронизация включена" : "Sync is on")
                 : (isRu ? "Синхронизация выключена" : "Sync is off"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(c.text)
            Text(settings.cloudSyncEnabled
                 ? (isRu ? "Данные доступны на всех Ваших устройствах" : "Data available on all your devices")
                 : (isRu ? "Данные только на этом устройстве" : "Data stays on this device"))
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func toggleCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 8) {
            syncChip(
                label: isRu ? "Выключить" : "Off",
                icon: "icloud.slash",
                isActive: !settings.cloudSyncEnabled,
                c: c
            ) {
                if settings.cloudSyncEnabled {
                    settings.cloudSyncEnabled = false
                    SyncQueue.shared.clearAll()
                }
            }

            syncChip(
                label: isRu ? "Включить" : "On",
                icon: "icloud.fill",
                isActive: settings.cloudSyncEnabled,
                c: c
            ) {
                if !settings.cloudSyncEnabled {
                    // First time: show confirmation sheet (GDPR just-in-time consent pattern).
                    // Subsequent toggles go through without interruption.
                    if !firstToggleShown {
                        showEnableConfirm = true
                    } else {
                        enableCloudSync()
                    }
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    private func enableCloudSync() {
        settings.cloudSyncEnabled = true
        firstToggleShown = true
        Task { @MainActor in
            let repo: TripRepository = CoreDataTripRepository()
            repo.markAllPendingUpload()
            for trip in repo.fetchAllTrips() {
                SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: trip.id, action: .upload))
            }
            for vehicle in settings.vehicles {
                SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: vehicle.id, action: .upload))
            }
            SyncEnqueuer.enqueue(SyncOperation(
                entityType: .settings, entityId: settings.localUserId, action: .upload))
            await SyncCoordinator.shared.runFullSync()
        }
    }

    private func syncChip(label: String, icon: String, isActive: Bool, c: AppTheme.Colors, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isActive ? .white : c.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? AppTheme.accent : c.cardAlt)
            )
        }
        .buttonStyle(.plain)
    }

    private func statusCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 12) {
            if !settings.cloudSyncEnabled {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(c.textTertiary)
                Text(isRu ? "Выключено" : "Disabled")
                    .foregroundStyle(c.textSecondary)
            } else if syncQueue.isSyncing {
                ProgressView()
                    .scaleEffect(0.75)
                if syncQueue.batchTotal > 0 {
                    Text((isRu ? "Синхронизация… " : "Syncing… ") + "\(syncQueue.batchProcessed)/\(syncQueue.batchTotal)")
                        .foregroundStyle(c.text)
                        .monospacedDigit()
                } else {
                    Text(isRu ? "Синхронизация…" : "Syncing…")
                        .foregroundStyle(c.text)
                }
            } else if syncQueue.pendingCount > 0 {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text((isRu ? "В очереди: " : "Pending: ") + "\(syncQueue.pendingCount)")
                    .foregroundStyle(c.text)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                Text(isRu ? "Всё синхронизировано" : "Everything up to date")
                    .foregroundStyle(c.text)
            }
            Spacer()
        }
        .font(.system(size: 14, weight: .medium))
        .padding(14)
        .surfaceCard(cornerRadius: 14)
        .animation(.easeInOut(duration: 0.2), value: syncQueue.isSyncing)
        .animation(.easeInOut(duration: 0.2), value: syncQueue.pendingCount)
        .animation(.easeInOut(duration: 0.2), value: settings.cloudSyncEnabled)
    }

    // MARK: - Blocked users entry

    private func blockedEntry(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            showBlockedList = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.slash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 24, alignment: .center)
                Text(isRu ? "Заблокированные пользователи" : "Blocked users")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Account actions (sign out + delete)

    private func accountActions(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                showSignOutAlert = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 24, alignment: .center)
                    Text(AppStrings.signOut(lang.language))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                    Spacer()
                }
                .padding(14)
                .surfaceCard(cornerRadius: 14)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                showDeleteAccountAlert = true
            } label: {
                HStack(spacing: 12) {
                    if isDeletingAccount {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.red)
                            .frame(width: 24, alignment: .center)
                        Text(isRu ? "Удаление…" : "Deleting…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 24, alignment: .center)
                        Text(AppStrings.deleteAccount(lang.language))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
                .padding(14)
                .surfaceCard(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .disabled(isDeletingAccount)
        }
    }

    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await auth.deleteAccount()
            dismiss()
        } catch let e as APIError {
            deleteAccountError = String(describing: e)
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }

    private func infoCard(icon: String, iconColor: Color, title: String, body: String, c: AppTheme.Colors) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .center)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }
}
