import SwiftUI

/// Shown instead of the whole app when the CoreData store did not open.
///
/// The screen exists because the alternative shipped for five versions and
/// cost a real user his library: on any load error the app renamed his
/// database, deleted its journal, opened an empty one and carried on as if
/// nothing had happened. He saw a working app with two trips in it and no way
/// to know the other 107 were still on the server.
///
/// Strictly limited dependencies — `ThemeManager`, `LanguageManager`,
/// `AppStrings`, `AppTheme`, all UserDefaults-backed. Nothing here may reach
/// `SettingsManager`, `TripManager`, `GamificationManager` or
/// `TerritoryManager`: they touch CoreData, and `SettingsManager.loadSettings`
/// in particular would insert a fresh settings row into the very store we are
/// trying not to disturb.
struct StoreRecoveryView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @StateObject private var health = StoreHealth.shared

    @State private var confirmingStartFresh = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // A drive open on a bench with a screwdriver beside it and its
            // light still on. The screen says «we could not open your data,
            // and we kept your file» — a question-mark glyph says neither half
            // of that, and the half it does imply is the frightening one.
            EmptyStateIllustration(name: "empty_data", size: 176)
                .padding(.bottom, 22)

            Text(AppStrings.storeRecoveryTitle(l))
                .font(.inter(22, weight: .bold))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text(AppStrings.storeRecoveryBody(l))
                .font(.inter(15))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)

            // Always visible, never hidden behind the confirm: the app is
            // asking permission to walk away from data it could not read, so
            // it has to say up front what happens to that data.
            Text(AppStrings.storeRecoveryFileKept(l))
                .font(.inter(13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(14)
                .frame(maxWidth: .infinity)
                .surfaceCard(cornerRadius: 14)

            Spacer(minLength: 24)

            retryButton(c: c, l: l)

            if health.offersStartFresh {
                startFreshButton(c: c, l: l)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.bg.ignoresSafeArea())
        .animation(.default, value: health.offersStartFresh)
        .animation(.default, value: health.isRetrying)
        .appConfirm(
            isPresented: $confirmingStartFresh,
            title: AppStrings.storeRecoveryStartFresh(l),
            message: AppStrings.storeRecoveryStartFreshConfirm(l),
            actions: [
                AppDialogAction(
                    AppStrings.storeRecoveryStartFresh(l),
                    kind: .destructive,
                    identifier: "store_recovery_start_fresh_confirm"
                ) {
                    health.startFresh()
                }
            ]
        )
        .accessibilityIdentifier("store_recovery")
    }

    // MARK: - Buttons

    /// Disabled while the load is in flight. `loadPersistentStores` runs
    /// synchronously on the main actor, so a large store freezes this screen —
    /// without the disabled state it looks dead and invites the repeat taps
    /// that would walk the user toward the destructive button.
    private func retryButton(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            health.retry()
        } label: {
            HStack(spacing: 8) {
                if health.isRetrying {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(AppStrings.storeRecoveryRetry(l))
                    .font(.inter(16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.accent))
        }
        .buttonStyle(.plain)
        .disabled(health.isRetrying)
        .opacity(health.isRetrying ? 0.6 : 1)
        .accessibilityIdentifier("store_recovery_retry")
    }

    private func startFreshButton(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            confirmingStartFresh = true
        } label: {
            Text(AppStrings.storeRecoveryStartFresh(l))
                .font(.inter(15, weight: .medium))
                .foregroundStyle(AppTheme.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("store_recovery_start_fresh")
    }
}
