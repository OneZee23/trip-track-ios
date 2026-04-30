import SwiftUI
import CoreData

/// Counts of every entity type by their cloud-sync state. Computed from
/// CoreData on sheet open + `.syncPullCompleted`, so the user can see what's
/// actually in the cloud vs what's still local — even when nothing is
/// actively in flight.
struct SyncCountSnapshot {
    var tripsSynced: Int = 0
    var tripsPending: Int = 0
    var vehiclesSynced: Int = 0
    var vehiclesPending: Int = 0
    var photosUploaded: Int = 0      // both thumb + original on R2
    var photosPartial: Int = 0       // thumb only — typically waiting for Wi-Fi
    var photosLocal: Int = 0         // never uploaded
    var photosFailed: Int = 0
    var settingsSynced: Bool = false
    var settingsExists: Bool = false

    static let empty = SyncCountSnapshot()
}

/// Drill-down for the sync status pill on the profile. Always shows a
/// per-entity counts card so "everything is synced" still has a story to
/// tell ("28 trips, 45 photos, 1 vehicle on the cloud"). Below it: live
/// queue/failed sections when there's actually something in flight.
struct SyncStatusSheetView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var syncQueue = SyncQueue.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var isRetrying = false
    @State private var snapshot: SyncCountSnapshot = .empty

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru
        let pending = syncQueue.pending
        let failed = syncQueue.failed
        let isEmpty = pending.isEmpty && failed.isEmpty && syncQueue.currentOperation == nil

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard(c, isRu: isRu)

                    countsCard(c, isRu: isRu)

                    if let op = syncQueue.currentOperation {
                        nowSection(op, c: c, isRu: isRu)
                    }

                    if !pending.isEmpty {
                        section(
                            title: AppStrings.syncStatusPendingHeader(lang.language) + "  \(pending.count)",
                            c: c
                        ) {
                            VStack(spacing: 8) {
                                ForEach(pending) { op in
                                    operationRow(op, isFailed: false, c: c, isRu: isRu)
                                }
                            }
                        }
                    }

                    if !failed.isEmpty {
                        section(
                            title: AppStrings.syncStatusFailedHeader(lang.language) + "  \(failed.count)",
                            c: c
                        ) {
                            VStack(spacing: 8) {
                                ForEach(failed) { op in
                                    operationRow(op, isFailed: true, c: c, isRu: isRu)
                                }
                            }
                        }

                        retryButton(c, isRu: isRu)
                    }

                    if isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.green)
                            Text(AppStrings.syncStatusEmpty(lang.language))
                                .font(.system(size: 13))
                                .foregroundStyle(c.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(c.bg)
            .navigationTitle(AppStrings.syncStatusTitle(lang.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
            .task { loadSnapshot() }
            .onReceive(NotificationCenter.default.publisher(for: .syncPullCompleted)) { _ in
                loadSnapshot()
            }
            .onChange(of: syncQueue.isSyncing) { _, syncing in
                // Sync just finished — counts may have changed.
                if !syncing { loadSnapshot() }
            }
        }
    }

    // MARK: - Sections

    private func summaryCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 12) {
            if !settings.cloudSyncEnabled {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(c.textTertiary)
                Text(isRu ? "Синхронизация выключена" : "Sync is off")
                    .foregroundStyle(c.textSecondary)
            } else if syncQueue.isSyncing {
                ProgressView().scaleEffect(0.75)
                let total = syncQueue.batchTotal
                let done = syncQueue.batchProcessed
                Text(total > 0
                     ? (isRu ? "Синхронизация… \(done)/\(total)" : "Syncing… \(done)/\(total)")
                     : (isRu ? "Синхронизация…" : "Syncing…"))
                    .foregroundStyle(c.text)
                    .monospacedDigit()
            } else if syncQueue.pendingCount > 0 {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text((isRu ? "Ожидают: " : "Waiting: ") + "\(syncQueue.pendingCount)")
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
    }

    private func nowSection(_ op: SyncOperation, c: AppTheme.Colors, isRu: Bool) -> some View {
        section(title: AppStrings.syncStatusNowLabel(lang.language), c: c) {
            operationRow(op, isFailed: false, c: c, isRu: isRu, highlight: true)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        c: AppTheme.Colors,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .tracking(0.5)
                .foregroundStyle(c.textTertiary)
                .padding(.leading, 4)
            content()
        }
    }

    private func operationRow(
        _ op: SyncOperation,
        isFailed: Bool,
        c: AppTheme.Colors,
        isRu: Bool,
        highlight: Bool = false
    ) -> some View {
        let entity = AppStrings.entityLabel(op.entityType.rawValue, lang.language)
        let action = AppStrings.actionLabel(op.action.rawValue, lang.language)
        let idShort = op.entityId.uuidString.prefix(8).lowercased()

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isFailed ? Color.red.opacity(0.15) : (highlight ? AppTheme.accent.opacity(0.18) : c.cardAlt))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName(op.entityType))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isFailed ? .red : (highlight ? AppTheme.accent : c.textSecondary))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entity)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(c.textTertiary)
                    Text(action)
                        .font(.system(size: 13))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    // ID is the least informative chunk — let it truncate before entity/action labels
                    Text(idShort)
                        .font(.system(size: 11, weight: .medium).monospaced())
                        .foregroundStyle(c.textTertiary)
                        .layoutPriority(-1)
                }
                if op.retryCount > 0 || isFailed {
                    Text(AppStrings.syncAttemptsLabel(max(op.retryCount, 1), lang.language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                }
                if let err = op.lastError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .surfaceCard(cornerRadius: 12)
    }

    private func iconName(_ type: SyncOperation.EntityType) -> String {
        switch type {
        case .trip:     return "flag.fill"
        case .vehicle:  return "car.fill"
        case .photo:    return "photo.fill"
        case .settings: return "gearshape.fill"
        }
    }

    private func retryButton(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            isRetrying = true
            Task {
                await syncQueue.retryFailedNow()
                isRetrying = false
            }
        } label: {
            HStack(spacing: 8) {
                if isRetrying {
                    ProgressView().scaleEffect(0.7).tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(AppStrings.syncStatusRetry(lang.language))
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(AppTheme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRetrying)
        .padding(.top, 4)
    }

    // MARK: - Counts

    private func countsCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 0) {
            countsRow(
                icon: "flag.fill", iconColor: AppTheme.blue,
                title: isRu ? "Поездки" : "Trips",
                summary: tripsSummary(isRu: isRu),
                c: c, showsDivider: true
            )
            countsRow(
                icon: "car.fill", iconColor: .green,
                title: isRu ? "Машины" : "Vehicles",
                summary: vehiclesSummary(isRu: isRu),
                c: c, showsDivider: true
            )
            countsRow(
                icon: "photo.fill", iconColor: AppTheme.accent,
                title: isRu ? "Фото" : "Photos",
                summary: photosSummary(isRu: isRu),
                c: c, showsDivider: true
            )
            countsRow(
                icon: "gearshape.fill", iconColor: c.textSecondary,
                title: isRu ? "Настройки" : "Settings",
                summary: settingsSummary(isRu: isRu),
                c: c, showsDivider: false
            )
        }
        .surfaceCard(cornerRadius: 14)
    }

    private func countsRow(
        icon: String, iconColor: Color,
        title: String, summary: String,
        c: AppTheme.Colors, showsDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, alignment: .center)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer()
                // Long summaries ("X в облаке · Y в очереди") wrap to a 2nd line and shrink slightly before clipping
                Text(summary)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            if showsDivider {
                Divider()
                    .background(c.cardAlt)
                    .padding(.leading, 48)
            }
        }
    }

    private func tripsSummary(isRu: Bool) -> String {
        let s = snapshot
        if s.tripsPending > 0 {
            return isRu
                ? "\(s.tripsSynced) в облаке · \(s.tripsPending) в очереди"
                : "\(s.tripsSynced) in cloud · \(s.tripsPending) pending"
        }
        return isRu ? "\(s.tripsSynced) в облаке" : "\(s.tripsSynced) in cloud"
    }

    private func vehiclesSummary(isRu: Bool) -> String {
        let s = snapshot
        if s.vehiclesPending > 0 {
            return isRu
                ? "\(s.vehiclesSynced) в облаке · \(s.vehiclesPending) в очереди"
                : "\(s.vehiclesSynced) in cloud · \(s.vehiclesPending) pending"
        }
        return isRu ? "\(s.vehiclesSynced) в облаке" : "\(s.vehiclesSynced) in cloud"
    }

    private func photosSummary(isRu: Bool) -> String {
        let s = snapshot
        var parts: [String] = []
        parts.append(isRu ? "\(s.photosUploaded) загружено" : "\(s.photosUploaded) uploaded")
        if s.photosPartial > 0 {
            parts.append(isRu
                ? "\(s.photosPartial) ждут Wi-Fi"
                : "\(s.photosPartial) awaiting Wi-Fi")
        }
        if s.photosLocal > 0 {
            parts.append(isRu
                ? "\(s.photosLocal) только локально"
                : "\(s.photosLocal) local only")
        }
        if s.photosFailed > 0 {
            parts.append(isRu
                ? "\(s.photosFailed) ошибка"
                : "\(s.photosFailed) failed")
        }
        return parts.joined(separator: " · ")
    }

    private func settingsSummary(isRu: Bool) -> String {
        if !snapshot.settingsExists {
            return isRu ? "—" : "—"
        }
        return snapshot.settingsSynced
            ? (isRu ? "синхронизировано" : "synced")
            : (isRu ? "в очереди" : "pending")
    }

    private func loadSnapshot() {
        let ctx = PersistenceController.shared.container.viewContext
        ctx.perform {
            var s = SyncCountSnapshot.empty

            s.tripsSynced    = countEntity(TripEntity.self, ctx: ctx, syncStatus: SyncStatus.synced.rawValue)
            s.tripsPending   = countEntity(TripEntity.self, ctx: ctx, syncStatus: SyncStatus.pendingUpload.rawValue)
            s.vehiclesSynced = countEntity(VehicleEntity.self, ctx: ctx, syncStatus: SyncStatus.synced.rawValue)
            s.vehiclesPending = countEntity(VehicleEntity.self, ctx: ctx, syncStatus: SyncStatus.pendingUpload.rawValue)

            // Photos use a separate enum (PhotoUploadStatus), not SyncStatus.
            s.photosUploaded = countPhoto(ctx: ctx, status: PhotoUploadStatus.uploaded.rawValue)
            s.photosPartial  = countPhoto(ctx: ctx, status: PhotoUploadStatus.uploading.rawValue)
            s.photosLocal    = countPhoto(ctx: ctx, status: PhotoUploadStatus.localOnly.rawValue)
            s.photosFailed   = countPhoto(ctx: ctx, status: PhotoUploadStatus.failed.rawValue)

            // Settings: there is at most one row per local user.
            let settingsReq: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
            settingsReq.fetchLimit = 1
            if let row = try? ctx.fetch(settingsReq).first {
                s.settingsExists = true
                s.settingsSynced = row.syncStatus == SyncStatus.synced.rawValue
            }

            DispatchQueue.main.async { self.snapshot = s }
        }
    }
}

// MARK: - CoreData count helpers

private func countEntity<T: NSManagedObject>(
    _ type: T.Type, ctx: NSManagedObjectContext, syncStatus: Int16
) -> Int {
    let req = NSFetchRequest<T>(entityName: String(describing: type))
    req.predicate = NSPredicate(format: "syncStatus == %d", syncStatus)
    req.includesSubentities = false
    return (try? ctx.count(for: req)) ?? 0
}

private func countPhoto(ctx: NSManagedObjectContext, status: Int16) -> Int {
    let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
    req.predicate = NSPredicate(format: "uploadStatus == %d", status)
    return (try? ctx.count(for: req)) ?? 0
}
