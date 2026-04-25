import SwiftUI

/// Drill-down for the "Pending: N" indicator on the profile. Lists every
/// operation currently queued or failed, names what kind of entity it is,
/// shows attempt count and last error reason for failures, and offers a
/// one-tap retry. Mirrors `SyncQueue` snapshots so it updates live as
/// `SyncCoordinator` chews through the batch.
struct SyncStatusSheetView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var syncQueue = SyncQueue.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var isRetrying = false

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
                        emptyState(c, isRu: isRu)
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
                    Text("·")
                        .foregroundStyle(c.textTertiary)
                    Text(action)
                        .font(.system(size: 13))
                        .foregroundStyle(c.textSecondary)
                    Spacer()
                    Text(idShort)
                        .font(.system(size: 11, weight: .medium).monospaced())
                        .foregroundStyle(c.textTertiary)
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

    private func emptyState(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text(AppStrings.syncStatusEmpty(lang.language))
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
