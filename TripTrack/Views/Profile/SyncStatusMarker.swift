import SwiftUI

/// What synchronisation is doing right now, in one word and one colour.
///
/// This used to be a grey line on the «Я» tab, directly under the name — the
/// second thing on the screen, permanently reading «Синхронизация выключена» to
/// everyone who never turned it on, and unactionable where it stood (the switch
/// is two taps away, inside Настройки). It now rides the row that OPENS that
/// switch: «Настройки → Аккаунт и синхронизация» answers the question at a
/// glance and is already on the way to doing something about the answer.
///
/// The state machine is shared with `CloudSyncView`'s own status row so the two
/// surfaces can't drift — including the off-but-publishing case, where the queue
/// still holds operations for explicitly-public trips while global sync is off.
enum SyncState: Equatable {
    case off
    case offPublishing(Int)
    case syncing(done: Int, total: Int)
    case queued(Int)
    case done

    static func current(
        enabled: Bool,
        isSyncing: Bool,
        pending: Int,
        batchProcessed: Int,
        batchTotal: Int
    ) -> SyncState {
        guard enabled else {
            return pending > 0 ? .offPublishing(pending) : .off
        }
        if isSyncing {
            return .syncing(done: batchProcessed, total: batchTotal)
        }
        return pending > 0 ? .queued(pending) : .done
    }

    func label(_ l: LanguageManager.Language) -> String {
        switch self {
        case .off:
            return AppStrings.syncOffState(l)
        case .offPublishing(let count):
            return AppStrings.syncOffPublishing(l, count: count)
        case .syncing(let done, let total):
            return total > 0
                ? AppStrings.syncingProgress(l, done: done, total: total)
                : AppStrings.syncingNow(l)
        case .queued(let count):
            return AppStrings.syncQueuedCount(l, count: count)
        case .done:
            return AppStrings.syncAllDone(l)
        }
    }

    /// The row version. «Аккаунт и синхронизация» is a long title in RU, and
    /// the full sentence («Синхронизация выключена», «Всё синхронизировано»)
    /// squeezed it into «Аккаунт и синхрониз…». Next to a coloured dot, one
    /// word is enough; the full wording still heads the screen the row opens.
    func shortLabel(_ l: LanguageManager.Language) -> String {
        switch self {
        case .off:
            return l == .ru ? "Выкл." : "Off"
        case .offPublishing(let count), .queued(let count):
            return AppStrings.syncQueuedCount(l, count: count)
        case .syncing(let done, let total):
            return total > 0 ? "\(done)/\(total)" : (l == .ru ? "…" : "…")
        case .done:
            return l == .ru ? "Готово" : "Synced"
        }
    }

    var tint: Color {
        switch self {
        case .off:            return AppTheme.textTertiary
        case .offPublishing:  return .orange
        case .syncing:        return AppTheme.accent
        case .queued:         return .orange
        case .done:           return .green
        }
    }
}

/// Dot + word, sized to sit in the trailing slot of a `SettingsIconRow`.
struct SyncStatusMarker: View {
    let state: SyncState
    let language: LanguageManager.Language

    var body: some View {
        HStack(spacing: 6) {
            if case .syncing = state {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(state.tint)
                    .frame(width: 7, height: 7)
            }

            Text(state.shortLabel(language))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                // The row's title yields first: «Аккаунт и синхронизация» can
                // scale down, «синхронизация… 12/40» cannot say less.
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings_sync_marker")
    }
}
