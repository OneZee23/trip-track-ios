import SwiftUI
import CoreData

/// «Аккаунт и синхронизация» (Figma 0.6.0 frame 1, section 157:1390).
/// Presented as a sheet from the ProfileView «Аккаунт и синхронизация» row —
/// the filename and type name are kept so that entry point is untouched.
///
/// Deliberate omissions vs the Figma frame (documented forks):
/// - F14: the five static explainer info-cards are gone (Figma ground truth);
///   the legal/privacy copy survives in the GDPR enable-consent dialog.
struct CloudSyncView: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var syncQueue = SyncQueue.shared
    @ObservedObject private var auth = AuthService.shared

    @State private var showSignOutAlert = false
    /// Public trips on the server when the sign-out row was tapped. Decides
    /// which question the one dialog asks — see `signOutActions`.
    @State private var publishedAtSignOut = 0
    @State private var showEnableConfirm = false
    @State private var showBlockedList = false
    @State private var showWipeServerConfirm = false
    @State private var isWipingServer = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    /// Server refused the deletion — shown under the card rather than in a
    /// second dialog, which the sign-out bug is a reminder not to raise from
    /// inside the first one's handler.
    @State private var deleteAccountError: String?
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
                navRow(l: l)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        accountCard(c: c, l: l)

                        sectionLabel(AppStrings.sectionSyncLabel(l), topPad: 14)
                        syncCard(c: c, l: l)

                        if auth.isSignedIn {
                            sectionLabel(AppStrings.sectionPrivacyLabel(l))
                            privacyCard(c: c, l: l)

                            sectionLabel(AppStrings.sectionAccountLabel(l))
                            accountActionsCard(c: c, l: l)

                            if let deleteAccountError {
                                Text(deleteAccountError)
                                    .font(.inter(12))
                                    .foregroundStyle(AppTheme.red)
                                    .padding(.top, 8)
                                    .padding(.horizontal, 4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
            }
            // GDPR just-in-time consent — fires on the very first enable only
            // (F12: flow preserved verbatim from pre-0.6.0 CloudSyncView).
            .appConfirm(
                isPresented: $showEnableConfirm,
                title: AppStrings.syncEnableConfirmTitle(l),
                message: AppStrings.syncEnableConfirmBody(l),
                actions: [
                    AppDialogAction(AppStrings.syncEnableConfirmAction(l)) {
                        enableCloudSync()
                    }
                ]
            )
            // ONE dialog, whichever question applies — see `signOutActions`.
            .appConfirm(
                isPresented: $showSignOutAlert,
                title: publishedAtSignOut > 0
                    ? AppStrings.signOutPublishedTitle(l)
                    : AppStrings.signOutConfirmTitle(l),
                message: publishedAtSignOut > 0
                    ? AppStrings.publishedTripsSignOutMessage(l, count: publishedAtSignOut)
                    : AppStrings.signOutConfirmMessage(l),
                actions: signOutActions(l)
            )
            // Apple 5.1.1(v): the account must be closable from inside the app,
            // in as few taps as opening this screen took. One dialog, one
            // destructive answer, and copy that names everything that goes —
            // the row promises «везде», so the card has to say what that is.
            .appConfirm(
                isPresented: $showDeleteAccountConfirm,
                title: AppStrings.deleteAccountConfirmTitle(l),
                message: AppStrings.deleteAccountConfirmBody(l),
                actions: [
                    AppDialogAction(
                        AppStrings.deleteAccountConfirmAction(l),
                        kind: .destructive,
                        identifier: "account_delete_confirm"
                    ) {
                        Task { await performDeleteAccount() }
                    }
                ]
            )
            .appConfirm(
                isPresented: $showWipeServerConfirm,
                title: AppStrings.wipeServerConfirmTitle(l),
                message: AppStrings.wipeServerConfirmBody(l),
                actions: [
                    AppDialogAction(AppStrings.wipeServerConfirmAction(l), kind: .destructive) {
                        Task {
                            isWipingServer = true
                            await auth.wipeServerData()
                            isWipingServer = false
                        }
                    }
                ]
            )
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

    /// The app's own bar, not a local copy of one.
    ///
    /// This row was hand-built from a 34pt `GarageCircleNavButton` — a fainter
    /// shadow, a 15pt glyph and no 44pt hit area — under a 16pt title, inset
    /// 2pt from the top. On a sheet, whose top edge is a hard rounded boundary
    /// with UIKit's grabber over the first 10pt, those 2pt glued the chevron
    /// into the corner. `CustomNavBar` already solves that (20pt of grabber
    /// clearance, 20pt horizontal so the controls clear the curved glass) and
    /// carries the `NavCircleIcon` control every other sheet in the app uses.
    ///
    /// Still a sheet root, so the chevron still means «close»: `NavBackButton`
    /// dismisses, and at the root of this stack there is nothing to pop, so
    /// the dismissal reaches the sheet (GarageView fork precedent). The title
    /// stays optically centred by the bar's own ZStack — no phantom trailing
    /// square needed to balance it.
    private func navRow(l: LanguageManager.Language) -> some View {
        CustomNavBar(title: AppStrings.accountSyncTitle(l))
            // Presented as a sheet from the settings sheet — the bar has to
            // know, so it clears the grabber.
            .environment(\.navBarInSheet, true)
    }

    // MARK: - Section label rhythm

    /// The 4pt leading pad pushed labels past the card edge they should align
    /// with, and a flat 18pt top pad dropped the first label 4pt low — the gap
    /// under the identity card is 14, the gaps between cards are 18.
    private func sectionLabel(_ text: String, topPad: CGFloat = 18) -> some View {
        AccountSectionLabel(text: text)
            .padding(.top, topPad)
            .padding(.bottom, 8)
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
                    .font(.inter(15, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // F11: masked email; Apple-relay / legacy accounts without a
                // stored email show just «Apple ID».
                Text(appleIdSubtitle(l))
                    .font(.inter(12))
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
                            .font(.inter(13))
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

    /// Aggregate state machine — same branches as the pre-0.6.0 statusCard,
    /// including the off-but-publishing state (queue can hold ops for
    /// explicitly-public trips while global sync is OFF — edge case #3).
    private func aggregateStatusValue(_ l: LanguageManager.Language) -> String {
        // One state machine, two surfaces: the same `SyncState` drives the
        // marker on «Настройки → Аккаунт и синхронизация», which is the row
        // that opens this screen — the two must never disagree.
        SyncState.current(
            enabled: settings.cloudSyncEnabled,
            isSyncing: syncQueue.isSyncing,
            pending: syncQueue.pendingCount,
            batchProcessed: syncQueue.batchProcessed,
            batchTotal: syncQueue.batchTotal
        ).label(l)
    }

    /// Proxy binding for the native Toggle (F10): ON routes through the
    /// kept-verbatim first-enable GDPR dialog, OFF clears the queue — exact
    /// semantics of the old chip pair.
    private var cloudSyncBinding: Binding<Bool> {
        Binding(
            get: { settings.cloudSyncEnabled },
            set: { newValue in
                Haptics.tap()
                if newValue {
                    guard !settings.cloudSyncEnabled else { return }
                    // First time: confirmation dialog (GDPR just-in-time
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
                                .font(.inter(13))
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
        VStack(spacing: 0) {
            Button {
                Haptics.tap()
                // Read the count HERE, not inside the dialog's handler: it
                // decides which question the one card asks.
                publishedAtSignOut = auth.publishedTripCount()
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

            // Canon's 8pt danger break: the last row is not one more setting,
            // it is the end of the account, and it does not share a hairline
            // with the row above it.
            Rectangle()
                .fill(c.bg)
                .frame(height: 8)

            Button {
                Haptics.tap()
                showDeleteAccountConfirm = true
            } label: {
                AccountSettingsRow(
                    icon: "nosign",
                    iconColor: AppTheme.red,
                    title: AppStrings.deleteAccountTitle(l),
                    titleColor: AppTheme.red,
                    subtitle: AppStrings.deleteAccountSubtitle(l)
                ) {
                    if isDeletingAccount {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(AppTheme.red)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isDeletingAccount)
            .accessibilityIdentifier("account_delete_row")
        }
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Sign out

    /// The answers on the sign-out dialog, which is ONE dialog on purpose.
    ///
    /// It used to be two: «точно выйти?» whose confirm opened a second card
    /// asking what to do with your public trips. `.appConfirm` is a
    /// window-level cover (see `AppConfirmPresenter` for why it can't be an
    /// overlay), and presenting a second cover from the first one's handler
    /// races its dismissal — UIKit dropped it, so the second card never came
    /// up, no branch ran, and «Выйти» did nothing at all for anyone with a
    /// public trip. The count is read when the row is TAPPED and drives which
    /// question this card asks; the second question always implied the first
    /// anyway, so merging them also removes a tap.
    private func signOutActions(_ l: LanguageManager.Language) -> [AppDialogAction] {
        guard publishedAtSignOut > 0 else {
            return [
                AppDialogAction(AppStrings.signOut(l), kind: .destructive) {
                    performSignOut(hidePublic: false)
                }
            ]
        }
        return [
            AppDialogAction(AppStrings.signOutHidePublic(l), kind: .destructive) {
                performSignOut(hidePublic: true)
            },
            AppDialogAction(AppStrings.signOutKeepPublic(l), kind: .plain) {
                performSignOut(hidePublic: false)
            },
        ]
    }

    private func performSignOut(hidePublic: Bool) {
        Task {
            if hidePublic { await auth.unpublishAllPublicTrips() }
            await auth.signOut()
            dismiss()
        }
    }

    // MARK: - Delete account

    /// Server first, device second (see `AuthService.deleteAccount`). A
    /// refusal keeps the account and says so in place — the screen closes only
    /// when there is genuinely nothing left on it.
    private func performDeleteAccount() async {
        isDeletingAccount = true
        deleteAccountError = nil
        defer { isDeletingAccount = false }
        do {
            try await auth.deleteAccount()
            dismiss()
        } catch {
            deleteAccountError = AppStrings.deleteAccountFailed(lang.language)
            Haptics.error()
        }
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
