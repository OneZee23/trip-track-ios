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

/// «Синхронизация» per-item status sheet (Figma 6.1.0 frame 2). Presented
/// from TWO places — the ProfileView sync pill and the CloudSyncView status
/// row — so it stays standalone-presentable and carries its own presentation
/// styling (detents / grabber / r22 corners) in addition to the call sites'.
/// Category card feeds from the real `SyncCountSnapshot`; below it the live
/// queue/failed sections appear when something is actually in flight.
struct SyncStatusSheetView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var syncQueue = SyncQueue.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var isRetrying = false
    @State private var snapshot: SyncCountSnapshot = .empty
    @State private var lastSyncedAt: Date?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let isRu = l == .ru
        let pending = syncQueue.pending
        let failed = syncQueue.failed

        VStack(spacing: 0) {
            header(c, l: l)

            ScrollView {
                VStack(spacing: 14) {
                    categoryCard(c, l: l)

                    footerRow(c, l: l)

                    if let op = syncQueue.currentOperation {
                        nowSection(op, c: c, isRu: isRu)
                    }

                    if !pending.isEmpty {
                        section(
                            title: AppStrings.syncStatusPendingHeader(l) + "  \(pending.count)",
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
                            title: AppStrings.syncStatusFailedHeader(l) + "  \(failed.count)",
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg)
        // Applied here (not only at call sites) so BOTH presenters — the
        // ProfileView pill and the CloudSyncView status row — get the same
        // sheet chrome without touching ProfileView.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
        .accessibilityIdentifier("sync_status_sheet")
        .task {
            loadSnapshot()
            refreshLastSynced()
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncPullCompleted)) { _ in
            loadSnapshot()
            refreshLastSynced()
        }
        .onChange(of: syncQueue.isSyncing) { _, syncing in
            // Sync just finished — counts may have changed.
            if !syncing {
                loadSnapshot()
                refreshLastSynced()
            }
        }
    }

    // MARK: - Header

    private func header(_ c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack {
            Text(AppStrings.syncSheetTitle(l))
                .font(.system(size: 17, weight: .heavy))
                .tracking(-0.2)
                .foregroundStyle(c.text)
            Spacer()
            SheetCloseButton()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Category card (frame 2)

    private func categoryCard(_ c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // No «Достижения» row (F4): achievements are not a synced entity —
        // level/XP ride `profile-update` and there is no per-item sync state
        // to report. The Figma «12/12» would be fabricated data.
        VStack(spacing: 0) {
            categoryRow(
                icon: "flag",
                label: AppStrings.tripsTab(l),
                synced: snapshot.tripsSynced,
                total: snapshot.tripsSynced + snapshot.tripsPending,
                failedCount: 0,
                showsDivider: true,
                a11yId: "sync_row_trips",
                c: c, l: l
            )
            categoryRow(
                icon: "camera",
                label: AppStrings.photos(l),
                synced: snapshot.photosUploaded,
                total: snapshot.photosUploaded + snapshot.photosPartial
                    + snapshot.photosLocal + snapshot.photosFailed,
                failedCount: snapshot.photosFailed,
                showsDivider: true,
                a11yId: "sync_row_photos",
                c: c, l: l
            )
            profileRow(c, l: l)
            categoryRow(
                icon: "car",
                label: AppStrings.garage(l),
                synced: snapshot.vehiclesSynced,
                total: snapshot.vehiclesSynced + snapshot.vehiclesPending,
                failedCount: 0,
                showsDivider: false,
                a11yId: "sync_row_garage",
                c: c, l: l
            )
        }
        .surfaceCard(cornerRadius: 16)
    }

    private func categoryRow(
        icon: String,
        label: String,
        synced: Int,
        total: Int,
        failedCount: Int,
        showsDivider: Bool,
        a11yId: String,
        c: AppTheme.Colors,
        l: LanguageManager.Language
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 24, alignment: .center)

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)

                Spacer(minLength: 8)

                counterText(synced: synced, total: total, failedCount: failedCount, c: c, l: l)

                if total == 0 || synced >= total {
                    checkmark
                } else {
                    progressCapsule(fraction: total > 0 ? Double(synced) / Double(total) : 0, c: c)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)

            if showsDivider {
                Rectangle()
                    .fill(c.border)
                    .frame(height: 1)
                    .padding(.leading, 50) // 14 + 24 icon slot + 12 gap
            }
        }
        .accessibilityIdentifier(a11yId)
    }

    /// «Профиль» — the settings-entity sync state (row named per Figma).
    /// No counter by design: there is exactly one profile row per user.
    private func profileRow(_ c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person")
                    .font(.system(size: 17))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 24, alignment: .center)

                Text(AppStrings.profile(l))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)

                Spacer(minLength: 8)

                if !snapshot.settingsExists {
                    Text("—")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                } else if snapshot.settingsSynced {
                    checkmark
                } else {
                    // Pending dot — an upload is queued for the profile.
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 6, height: 6)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)

            Rectangle()
                .fill(c.border)
                .frame(height: 1)
                .padding(.leading, 50)
        }
        .accessibilityIdentifier("sync_row_profile")
    }

    private func counterText(
        synced: Int, total: Int, failedCount: Int,
        c: AppTheme.Colors, l: LanguageManager.Language
    ) -> Text {
        let base = Text("\(synced) / \(total)")
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(c.textTertiary)
        guard failedCount > 0 else { return base }
        // F8: failed portion surfaces as a red counter suffix; details live
        // in the failed-ops list below the card.
        return base + Text(" · " + AppStrings.syncFailedCount(l, count: failedCount))
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(AppTheme.red)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(AppTheme.green)
            .frame(width: 24, height: 24)
    }

    private func progressCapsule(fraction: Double, c: AppTheme.Colors) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(c.cardAlt)
                .frame(width: 44, height: 6)
            Capsule()
                .fill(AppTheme.accent)
                .frame(width: max(4, 44 * min(1, max(0, fraction))), height: 6)
        }
    }

    // MARK: - Footer (last sync)

    @ViewBuilder
    private func footerRow(_ c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if let last = lastSyncedAt {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                Text(AppStrings.syncLastAt(l, RelativeTripDate.string(from: last, language: l)))
                    .font(.system(size: 13))
            }
            .foregroundStyle(c.textTertiary)
            .frame(maxWidth: .infinity)
        }
    }

    private func refreshLastSynced() {
        lastSyncedAt = TokenStore.shared.accountId
            .flatMap { LastSyncedAtStore.get(accountId: $0) }
    }

    // MARK: - Live queue sections (logic untouched)

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
                    .fill(isFailed ? AppTheme.red.opacity(0.15) : (highlight ? AppTheme.accent.opacity(0.18) : c.cardAlt))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName(op.entityType))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isFailed ? AppTheme.red : (highlight ? AppTheme.accent : c.textSecondary))
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
                        .foregroundStyle(AppTheme.red.opacity(0.85))
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
        .accessibilityIdentifier("sync_retry_button")
    }

    // MARK: - Counts (data layer untouched)

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
