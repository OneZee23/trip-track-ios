import SwiftUI
import CoreData

/// «Аккаунт и синхронизация» (Figma 6.1.0 frame 1, section 157:1390).
/// Presented as a sheet from the ProfileView «Аккаунт и синхронизация» row —
/// the filename and type name are kept so that entry point is untouched.
///
/// Deliberate omissions vs the Figma frame (documented forks):
/// - F1: no «Удалить аккаунт» row and no 8px danger separator — user decision
///   deferred. `AuthService.deleteAccount()` and its AppStrings are preserved
///   as a code path; only this UI was removed. ⚠️ App Store 5.1.1(v) requires
///   in-app account deletion — do not ship to the store until resolved.
/// - F14: the five static explainer info-cards are gone (Figma ground truth);
///   the legal/privacy copy survives in the GDPR enable-consent alert.
struct CloudSyncView: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var syncQueue = SyncQueue.shared
    @ObservedObject private var auth = AuthService.shared

    @State private var showSignOutAlert = false
    @State private var showSignOutPublishedDialog = false
    @State private var publishedAtSignOut = 0
    @State private var showEnableConfirm = false
    @State private var showBlockedList = false
    @State private var showWipeServerConfirm = false
    @State private var isWipingServer = false
    @State private var showSyncSheet = false
    /// Count from `/social/blocked`; nil = not fetched / fetch failed —
    /// the row stays navigable either way, just without the number.
    @State private var blockedCount: Int?
    @State private var lastSyncedAt: Date?
    /// Optimistic value for the public-profile toggle while the
    /// `setPublicProfile` round-trip is in flight; nil = mirror the server.
    @State private var publicProfileDraft: Bool?
    @AppStorage("com.triptrack.sync.firstToggleShown") private var firstToggleShown = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        NavigationStack {
            VStack(spacing: 0) {
                navRow(c: c, l: l)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        accountCard(c: c, l: l)

                        sectionLabel(AppStrings.sectionSyncLabel(l))
                        syncCard(c: c, l: l)

                        if auth.isSignedIn {
                            sectionLabel(AppStrings.sectionPrivacyLabel(l))
                            privacyCard(c: c, l: l)

                            sectionLabel(AppStrings.sectionAccountLabel(l))
                            accountActionsCard(c: c, l: l)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .background(c.bg)
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("account_sync_screen")
            .navigationDestination(isPresented: $showBlockedList) {
                BlockedListView()
            }
            .sheet(isPresented: $showSyncSheet, onDismiss: {
                // A sync may have completed while the sheet was up.
                refreshLastSynced()
            }) {
                SyncStatusSheetView()
                    .environmentObject(lang)
                    .environmentObject(themeManager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(22)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
            // GDPR just-in-time consent — fires on the very first enable only
            // (F12: flow preserved verbatim from pre-6.1.0 CloudSyncView).
            .alert(
                AppStrings.syncEnableConfirmTitle(l),
                isPresented: $showEnableConfirm
            ) {
                Button(AppStrings.cancel(l), role: .cancel) {}
                Button(AppStrings.syncEnableConfirmAction(l)) {
                    enableCloudSync()
                }
            } message: {
                Text(AppStrings.syncEnableConfirmBody(l))
            }
            .alert(
                AppStrings.signOutConfirmTitle(l),
                isPresented: $showSignOutAlert
            ) {
                Button(AppStrings.cancel(l), role: .cancel) {}
                Button(AppStrings.signOut(l), role: .destructive) {
                    // Branch on whether the user has any public trips on the
                    // server. With public trips → show 3-way confirmation
                    // (hide vs keep). Without → straight sign-out.
                    let count = auth.publishedTripCount()
                    if count > 0 {
                        publishedAtSignOut = count
                        showSignOutPublishedDialog = true
                    } else {
                        Task {
                            await auth.signOut()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text(AppStrings.signOutConfirmMessage(l))
            }
            .confirmationDialog(
                AppStrings.signOutPublishedTitle(l),
                isPresented: $showSignOutPublishedDialog,
                titleVisibility: .visible
            ) {
                Button(AppStrings.signOutHidePublic(l), role: .destructive) {
                    Task {
                        await auth.unpublishAllPublicTrips()
                        await auth.signOut()
                        dismiss()
                    }
                }
                Button(AppStrings.signOutKeepPublic(l)) {
                    Task {
                        await auth.signOut()
                        dismiss()
                    }
                }
                Button(AppStrings.cancel(l), role: .cancel) {}
            } message: {
                Text(AppStrings.publishedTripsSignOutMessage(l, count: publishedAtSignOut))
            }
            .alert(
                AppStrings.wipeServerConfirmTitle(l),
                isPresented: $showWipeServerConfirm
            ) {
                Button(AppStrings.cancel(l), role: .cancel) {}
                Button(AppStrings.wipeServerConfirmAction(l), role: .destructive) {
                    Task {
                        isWipingServer = true
                        await auth.wipeServerData()
                        isWipingServer = false
                    }
                }
            } message: {
                Text(AppStrings.wipeServerConfirmBody(l))
            }
            .task {
                refreshLastSynced()
                await auth.refreshMe()
            }
            // `.onAppear` (not `.task`) on purpose: it re-fires on pop-back
            // from BlockedListView, so the count updates after an unblock.
            .onAppear {
                Task { await loadBlockedCount() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncPullCompleted)) { _ in
                refreshLastSynced()
            }
        }
    }

    // MARK: - Nav row

    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack {
            // Sheet root — the chevron acts as close (GarageView fork precedent).
            GarageCircleNavButton(systemImage: "chevron.left") { dismiss() }
                .accessibilityIdentifier("account_back")
            Spacer()
            Text(AppStrings.accountSyncTitle(l))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
            Spacer()
            // Trailing spacer keeps the title optically centered.
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
        .padding(.horizontal, 14)
    }

    // MARK: - Section label rhythm

    private func sectionLabel(_ text: String) -> some View {
        AccountSectionLabel(text: text)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .padding(.leading, 4)
    }

    // MARK: - Account card (117:1412)

    private func accountCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(c.cardAlt)
                .frame(width: 48, height: 48)
                .overlay { Text(settings.avatarEmoji).font(.system(size: 24)) }

            VStack(alignment: .leading, spacing: 2) {
                Text(auth.userName ?? AppStrings.profile(l))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // F11: masked email; Apple-relay / legacy accounts without a
                // stored email show just «Apple ID».
                Text(appleIdSubtitle(l))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("account_identity_card")
    }

    private func appleIdSubtitle(_ l: LanguageManager.Language) -> String {
        guard let email = auth.userEmail,
              !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            return AppStrings.accountAppleIdOnly(l)
        }
        return AppStrings.accountAppleIdLine(l, email: AccountFormat.maskedEmail(email))
    }

    // MARK: - СИНХРОНИЗАЦИЯ card

    private func syncCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            AccountSettingsRow(
                icon: "globe",
                title: AppStrings.cloudSyncTitle(l),
                subtitle: cloudSyncSubtitle(l),
                showsDivider: true
            ) {
                Toggle(AppStrings.cloudSyncTitle(l), isOn: cloudSyncBinding)
                    .labelsHidden()
                    .tint(AppTheme.accent)
                    .accessibilityIdentifier("sync_cloud_toggle")
            }

            Button {
                Haptics.tap()
                showSyncSheet = true
            } label: {
                AccountSettingsRow(
                    icon: "point.topleft.down.curvedto.point.bottomright.up",
                    title: AppStrings.syncPerItemStatus(l)
                ) {
                    HStack(spacing: 6) {
                        Text(aggregateStatusValue(l))
                            .font(.system(size: 13))
                            .foregroundStyle(c.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sync_status_row")
        }
        .surfaceCard(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.2), value: syncQueue.isSyncing)
        .animation(.easeInOut(duration: 0.2), value: syncQueue.pendingCount)
        .animation(.easeInOut(duration: 0.2), value: settings.cloudSyncEnabled)
    }

    /// F13: «Обновлено N назад» from the per-account LastSyncedAtStore; falls
    /// back to plain on/off state copy when the account never synced (or guest).
    private func cloudSyncSubtitle(_ l: LanguageManager.Language) -> String {
        if let last = lastSyncedAt {
            return AppStrings.syncUpdatedAgo(l, RelativeTripDate.string(from: last, language: l))
        }
        return settings.cloudSyncEnabled
            ? AppStrings.syncStateOn(l)
            : AppStrings.syncStateOff(l)
    }

    /// Aggregate state machine — same branches as the pre-6.1.0 statusCard,
    /// including the off-but-publishing state (queue can hold ops for
    /// explicitly-public trips while global sync is OFF — edge case #3).
    private func aggregateStatusValue(_ l: LanguageManager.Language) -> String {
        if !settings.cloudSyncEnabled {
            return syncQueue.pendingCount > 0
                ? AppStrings.syncOffPublishing(l, count: syncQueue.pendingCount)
                : AppStrings.syncOffState(l)
        }
        if syncQueue.isSyncing {
            return syncQueue.batchTotal > 0
                ? AppStrings.syncingProgress(l, done: syncQueue.batchProcessed, total: syncQueue.batchTotal)
                : AppStrings.syncingNow(l)
        }
        if syncQueue.pendingCount > 0 {
            return AppStrings.syncQueuedCount(l, count: syncQueue.pendingCount)
        }
        return AppStrings.syncAllDone(l)
    }

    /// Proxy binding for the native Toggle (F10): ON routes through the
    /// kept-verbatim first-enable GDPR alert, OFF clears the queue — exact
    /// semantics of the old chip pair.
    private var cloudSyncBinding: Binding<Bool> {
        Binding(
            get: { settings.cloudSyncEnabled },
            set: { newValue in
                Haptics.tap()
                if newValue {
                    guard !settings.cloudSyncEnabled else { return }
                    // First time: confirmation alert (GDPR just-in-time
                    // consent pattern). Subsequent toggles go straight through.
                    if !firstToggleShown {
                        showEnableConfirm = true
                    } else {
                        enableCloudSync()
                    }
                } else if settings.cloudSyncEnabled {
                    settings.cloudSyncEnabled = false
                    SyncQueue.shared.clearAll()
                }
            }
        )
    }

    private func enableCloudSync() {
        settings.cloudSyncEnabled = true
        firstToggleShown = true
        Task { @MainActor in
            let repo: TripRepository = CoreDataTripRepository()
            // Full mirror on the explicit user opt-in (the GDPR copy promises
            // "re-enabling uploads everything"). This re-marks EVERYTHING
            // pendingUpload and enqueues it — which is data-loss-safe (a private
            // trip or vehicle edited while Cloud Sync was OFF kept syncStatus
            // .synced and would be MISSED by a pendingUpload-only filter). It is
            // no longer heavy: payloads build off the main actor (uploadTrip →
            // fetchTripSyncPayloadAsync) and the server no-ops identical
            // re-uploads (TripsService.upsert short-circuit), so re-mirroring
            // already-synced rows is cheap instead of a destructive rewrite.
            repo.markAllPendingUpload()
            for trip in repo.fetchAllTrips() {
                SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: trip.id, action: .upload))
            }
            for vehicle in settings.vehicles {
                SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: vehicle.id, action: .upload))
            }
            SyncEnqueuer.enqueue(SyncOperation(
                entityType: .settings, entityId: settings.localUserId, action: .upload))

            // Photos are gated by their own `uploadStatus` (separate from
            // `syncStatus`). Enqueue every photo that isn't already fully on
            // R2 — `localOnly` (never uploaded), `uploading`
            // (thumb sent, original stuck on cellular), and `failed` (prior
            // attempt errored). `APISyncTransport.uploadPhoto` is idempotent
            // — it skips thumb/original parts that already have a key.
            let ctx = PersistenceController.shared.container.viewContext
            let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
            req.predicate = NSPredicate(
                format: "uploadStatus != %d", PhotoUploadStatus.uploaded.rawValue)
            if let photos = try? ctx.fetch(req) {
                for p in photos {
                    if let pid = p.id {
                        SyncEnqueuer.enqueue(SyncOperation(
                            entityType: .photo, entityId: pid, action: .upload))
                    }
                }
            }

            await SyncCoordinator.shared.runFullSync()
        }
    }

    // MARK: - ПРИВАТНОСТЬ card

    private func privacyCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            // F2 gating: rendered ONLY after a successful /auth/me — against
            // deployed prod without the endpoint an ungated toggle would
            // fake-succeed (old server silently drops unknown DTO fields).
            // Note: isPublic=false hides the PROFILE (server 404s it); public
            // trips still appear in the feed — matches current server
            // semantics, feed filtering is deliberately NOT extended here.
            if auth.isPublicProfile != nil {
                AccountSettingsRow(
                    icon: "lock.fill",
                    title: AppStrings.publicProfileTitle(l),
                    subtitle: AppStrings.publicProfileSubtitle(l),
                    showsDivider: true
                ) {
                    Toggle(AppStrings.publicProfileTitle(l), isOn: publicProfileBinding)
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        .accessibilityIdentifier("privacy_public_toggle")
                }
            }

            Button {
                Haptics.tap()
                showBlockedList = true
            } label: {
                AccountSettingsRow(
                    icon: "nosign",
                    title: AppStrings.blockedUsersShort(l)
                ) {
                    HStack(spacing: 6) {
                        if let count = blockedCount {
                            Text("\(count)")
                                .font(.system(size: 13))
                                .foregroundStyle(c.textSecondary)
                                .monospacedDigit()
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("privacy_blocked_row")
        }
        .surfaceCard(cornerRadius: 16)
    }

    /// Optimistic toggle with revert: flips immediately, sends the
    /// isPublic-only payload, and snaps back (+ error haptic) on failure.
    private var publicProfileBinding: Binding<Bool> {
        Binding(
            get: { publicProfileDraft ?? auth.isPublicProfile ?? true },
            set: { newValue in
                Haptics.tap()
                publicProfileDraft = newValue
                Task {
                    let ok = await auth.setPublicProfile(newValue)
                    if !ok { Haptics.error() }
                    // Success → auth.isPublicProfile == newValue already;
                    // failure → dropping the draft reverts the toggle.
                    publicProfileDraft = nil
                }
            }
        )
    }

    // MARK: - АККАУНТ card

    private func accountActionsCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // F1: no «Удалить аккаунт» row and no 8px danger separator here —
        // the card ends after clear-server with normal r16 corners.
        VStack(spacing: 0) {
            Button {
                Haptics.tap()
                showSignOutAlert = true
            } label: {
                AccountSettingsRow(
                    icon: "arrow.down.to.line",  // "saved to device" metaphor
                    title: AppStrings.signOut(l),
                    subtitle: AppStrings.signOutSubtitle(l),
                    showsDivider: true
                ) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account_signout_row")

            Button {
                Haptics.tap()
                showWipeServerConfirm = true
            } label: {
                AccountSettingsRow(
                    icon: "exclamationmark.triangle",
                    iconColor: AppTheme.red,
                    title: isWipingServer
                        ? AppStrings.clearServerInProgress(l)
                        : AppStrings.clearServerTitle(l),
                    titleColor: AppTheme.red,
                    subtitle: AppStrings.clearServerSubtitle(l)
                ) {
                    if isWipingServer {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(AppTheme.red)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isWipingServer)
            .accessibilityIdentifier("account_clear_server_row")
        }
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Data

    private func refreshLastSynced() {
        // Per-account timestamp; guest / never-synced → nil (no crash when
        // TokenStore.accountId is nil — subtitle falls back to state copy).
        lastSyncedAt = TokenStore.shared.accountId
            .flatMap { LastSyncedAtStore.get(accountId: $0) }
    }

    private func loadBlockedCount() async {
        guard auth.isSignedIn else { return }
        do {
            let res: SocialBlockedListResponse = try await APIClient.shared.post(
                APIEndpoint.socialBlocked, body: EmptyRequest())
            blockedCount = res.users.count
        } catch {
            // Fetch failure → row stays navigable, count stays hidden.
        }
    }
}
