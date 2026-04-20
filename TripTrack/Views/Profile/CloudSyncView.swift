import SwiftUI

struct CloudSyncView: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var syncQueue = SyncQueue.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationView {
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
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
                    settings.cloudSyncEnabled = true
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
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
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
