import Foundation
import AuthenticationServices
import CoreData
import UIKit
import OSLog

private let authLog = Logger(subsystem: "com.triptrack", category: "auth")

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    private(set) var userIdentifier: String?

    @Published private(set) var isAuthenticating = false
    @Published var lastAuthError: APIError?
    /// Handle to the post-sign-in sync chain (performFirstSync + profile +
    /// push + inbox). Held so signOut can cancel it — otherwise an in-flight
    /// chain from a previous account can finish AFTER a new account signs
    /// in, applying the previous account's data with the new account's
    /// tokens and creating a cross-account contamination window.
    private var postSignInSyncTask: Task<Void, Never>?

    private enum Keys {
        static let userIdentifier = "com.triptrack.auth.userIdentifier"
        static let userName = "com.triptrack.auth.userName"
        static let userEmail = "com.triptrack.auth.userEmail"
        static let identityToken = "com.triptrack.auth.identityToken"
        static let isSignedIn = "com.triptrack.auth.isSignedIn"
    }

    private init() {
        loadFromKeychain()
        // If the previous session was force-quit (instead of cleanly
        // signed out) the cached APNs token in UserDefaults survives.
        // Drop it on cold launch when we're not signed in — otherwise
        // the next sign-in could replay the stale token onto a different
        // account, briefly binding the wrong device row. The token is
        // re-issued by APNs after registerForRemoteNotifications anyway.
        if !isSignedIn {
            PushNotificationManager.shared.clearCachedToken()
        } else {
            // Already-signed-in upgrader path: SettingsManager just ran the
            // privacy-by-default migration (which only PERSISTS server-side
            // unpublish IDs — never enqueues directly). Drain them now so
            // the user doesn't need a fresh SIWA flow to strip old public
            // copies. Idempotent: removeObject after read.
            Task { @MainActor in self.drainPendingPrivateMigrationUnpublish() }
        }
        // Listen for server-reported ban. `APIClient` posts this when any
        // endpoint returns `USER_BANNED`. We sign out to drop tokens and
        // stop sync attempts — local CoreData is preserved so the user can
        // still view their own trips read-only.
        NotificationCenter.default.addObserver(
            forName: .userBanned, object: nil, queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in await self?.signOut() }
        }
    }

    // MARK: - Handle Authorization (called from SignInWithAppleButton onCompletion)

    func handleAuthorization(_ authorization: ASAuthorization) async {
        authLog.debug("handleAuthorization START")
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            authLog.debug("❌ credential cast failed, got: \(type(of: authorization.credential))")
            return
        }
        let userId = credential.user
        authLog.debug("credential.user=\(userId) tokenSize=\(credential.identityToken?.count ?? -1)")

        try? KeychainHelper.saveString(userId, for: Keys.userIdentifier)
        userIdentifier = userId

        // Name resolution order — first non-empty wins:
        //   1. Apple Sign In `fullName` — only delivered on the *very first*
        //      authorization for an Apple ID across all devices. Most
        //      authoritative when present.
        //   2. Local Keychain — preserved across re-sign-ins on this device.
        //   3. Server's `account.displayName` (set further below, after the
        //      login round-trip) — tied to the Apple ID via `appleSubject`,
        //      so a name set on a previous device with the same Apple ID
        //      flows here.
        //   4. Random road-trip-themed fallback — only when no other source
        //      had anything.
        if let fullName = credential.fullName {
            let name = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !name.isEmpty {
                try? KeychainHelper.saveString(name, for: Keys.userName)
                userName = name
            }
        }
        if userName == nil {
            userName = KeychainHelper.loadString(key: Keys.userName)
        }

        if let email = credential.email {
            try? KeychainHelper.saveString(email, for: Keys.userEmail)
            userEmail = email
        }
        if userEmail == nil {
            userEmail = KeychainHelper.loadString(key: Keys.userEmail)
        }

        guard let tokenData = credential.identityToken else {
            lastAuthError = .invalidAppleToken("nil")
            return
        }

        // Call server /auth/login
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let body = LoginRequest(
                identityToken: tokenData.base64EncodedString(),
                localUserId: SettingsManager.shared.localUserId.uuidString,
                deviceName: UIDevice.current.name,
                nonce: SIWANonce.consumeRawNonce()
            )
            let response: LoginResponse = try await APIClient.shared.post(
                APIEndpoint.login, body: body, requiresAuth: false)
            // Persist identity AND signed-in marker only AFTER /auth/login
            // succeeds. Earlier ordering wrote the marker before the network
            // call, leaving a half-registered keychain state on transient
            // login failure (marker=true, tokens=nil) that confused the
            // hydrate path on next launch.
            try? KeychainHelper.save(tokenData, for: Keys.identityToken)
            try? KeychainHelper.saveString("true", for: Keys.isSignedIn)
            TokenStore.shared.set(accessToken: response.accessToken, refreshToken: response.refreshToken)
            TokenStore.shared.setAccountId(response.account.id)
            isSignedIn = true

            // Step 3 of the resolution order — pull the server's stored name
            // when we still don't have one. Without this, signing in on a
            // fresh phone with an Apple ID that already has an account would
            // generate a random name *and clobber the server's real one*
            // through the `syncProfileToServer` call below.
            if (userName?.isEmpty ?? true), let serverName = response.account.displayName,
               !serverName.trimmingCharacters(in: .whitespaces).isEmpty {
                userName = serverName
                try? KeychainHelper.saveString(serverName, for: Keys.userName)
            }

            // Step 4 — random fallback when neither Apple, Keychain, nor the
            // server had a name. Genuine first-ever sign-in on a fresh
            // Apple ID where SIWA didn't redeliver fullName (rare but real).
            if userName == nil {
                let generated = RandomDisplayName.generate(language: LanguageManager.currentLanguage)
                try? KeychainHelper.saveString(generated, for: Keys.userName)
                userName = generated
            }

            // Sync chain runs detached so the SIWA prompt dismisses the
            // moment `isSignedIn` flips to true (was: stuck for minutes on
            // flaky RU networks while every sub-call retried). The Task
            // handle is captured so signOut can cancel it — without that,
            // a slow chain from User A could land /trips/upsert calls with
            // User A's data tagged with User B's freshly-issued token after
            // a quick sign-out + sign-in, mixing accounts.
            postSignInSyncTask?.cancel()
            postSignInSyncTask = Task { [weak self] in
                guard let self else { return }
                self.drainPendingPrivateMigrationUnpublish()
                await self.performFirstSync()
                if Task.isCancelled { return }
                await self.syncProfileToServer()
                if Task.isCancelled { return }
                PushNotificationManager.shared.registerForRemoteNotifications()
                await PushNotificationManager.shared.syncTokenToServer()
                if Task.isCancelled { return }
                await NotificationsInboxStore.shared.refresh()
            }
        } catch let e as APIError {
            lastAuthError = e
        } catch {
            lastAuthError = .transport(error.localizedDescription)
        }
    }

    // MARK: - First Sync

    private func performFirstSync() async {
        // Skip the full backfill when Cloud Sync is OFF. The privacy-first
        // model says: signing in alone doesn't mass-upload personal content;
        // the user has to explicitly opt into Cloud Sync from settings.
        // Without this guard we'd flip every entity to `.pendingUpload`,
        // enqueue them, and then the SyncEnqueuer privacy gate would deny
        // the private/vehicle/settings ones — leaving phantom pending ops
        // visible in the status sheet forever.
        // We still call runFullSync at the end so any explicitly-public
        // trips queued via the privacy-migration drain or earlier sessions
        // get pushed.
        if SettingsManager.shared.cloudSyncEnabled {
            let repo: TripRepository = CoreDataTripRepository()
            repo.markAllPendingUpload()

            for trip in repo.fetchAllTrips() {
                SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: trip.id, action: .upload))
            }
            for vehicle in SettingsManager.shared.vehicles {
                SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: vehicle.id, action: .upload))
            }
            SyncEnqueuer.enqueue(SyncOperation(
                entityType: .settings, entityId: SettingsManager.shared.localUserId, action: .upload))

            // Photos not fully on R2 yet. Mirrors the predicate in
            // `CloudSyncView.enableCloudSync`.
            let ctx = PersistenceController.shared.container.viewContext
            let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
            req.predicate = NSPredicate(format: "uploadStatus != %d", PhotoUploadStatus.uploaded.rawValue)
            if let photos = try? ctx.fetch(req) {
                for p in photos {
                    if let pid = p.id {
                        SyncEnqueuer.enqueue(SyncOperation(entityType: .photo, entityId: pid, action: .upload))
                    }
                }
            }
        }

        await SyncCoordinator.shared.runFullSync()
    }

    // MARK: - Sign Out

    /// Pre-signOut cleanup. Flips any locally-public trip that hasn't
    /// reached the server yet back to private, so the next account's
    /// `recoverPendingEntities` doesn't accidentally re-enqueue it under
    /// the wrong user. Mirror of the `unpublishAllPublicTrips` logic but
    /// for trips without a server copy (those go to private locally; no
    /// server delete needed since there's nothing to delete).
    @MainActor
    private static func demotePendingPublicTripsToPrivate() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(
            format: "isPrivate == NO AND serverCreatedAt == nil AND syncStatus == %d",
            SyncStatus.pendingUpload.rawValue
        )
        guard let entities = try? ctx.fetch(req) else { return }
        for entity in entities {
            entity.isPrivate = true
            entity.syncStatus = SyncStatus.synced.rawValue
        }
        if !entities.isEmpty {
            try? ctx.save()
            authLog.notice("demoted \(entities.count) pending-public-unsynced trip(s) to private on signOut")
        }
    }

    /// Drains the queue of `.unpublish` ops left over from the
    /// privacy-by-default migration. SettingsManager runs the migration at
    /// app launch (before SIWA can complete), so it can't enqueue from
    /// SyncEnqueuer's auth-gate; it persists the IDs in UserDefaults
    /// instead. After successful sign-in, we replay them. Idempotent —
    /// once the list is drained, the UserDefaults key is removed.
    @MainActor
    private func drainPendingPrivateMigrationUnpublish() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.array(forKey: SettingsManager.pendingPrivateMigrationUnpublishKey) as? [String],
              !raw.isEmpty else { return }
        for s in raw {
            guard let id = UUID(uuidString: s) else { continue }
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .unpublish))
        }
        defaults.removeObject(forKey: SettingsManager.pendingPrivateMigrationUnpublishKey)
        authLog.notice("drained \(raw.count) pending private-migration unpublish op(s)")
    }

    /// Number of the user's trips that currently exist on the server with
    /// `is_private = false`. Surfaces in the sign-out confirmation so the
    /// user can decide whether to take their public footprint with them.
    /// Cheap CoreData fetch — no network.
    func publishedTripCount() -> Int {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "isPrivate == NO AND serverCreatedAt != nil")
        return (try? ctx.count(for: req)) ?? 0
    }

    /// Soft-unpublish every public-and-synced trip on the way out. Sends a
    /// regular upsert with `is_private=true` instead of a hard DELETE — the
    /// trip stays on the server, just hidden from the social feed (server
    /// `is_private=true` filter), so reactions/comments survive a re-login.
    /// User wording: "Hide public and sign out". For a true wipe the user
    /// has the separate `wipeServerData` action (or Delete Account).
    /// Best-effort: failures leave the trip's privacy unchanged on the
    /// server; caller decides whether to abort sign-out.
    func unpublishAllPublicTrips() async {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "isPrivate == NO AND serverCreatedAt != nil")
        guard let entities = try? ctx.fetch(req) else { return }
        let repo: TripRepository = CoreDataTripRepository()
        for entity in entities {
            guard let id = entity.id, var trip = repo.fetchTripDetail(id: id) else { continue }
            trip.isPrivate = true
            let payload = TripSyncPayload(trip: trip, entity: entity)
            do {
                let res: TripUpsertResponse = try await APIClient.shared.post(
                    APIEndpoint.tripUpsert, body: payload)
                entity.isPrivate = true
                entity.lastModifiedAt = payload.lastModifiedAt
                repo.markSynced(tripId: id, conflictVersion: res.conflictVersion, serverCreatedAt: res.serverCreatedAt)
            } catch {
                authLog.error("soft unpublish failed for trip \(id, privacy: .public): \(String(describing: error), privacy: .public)")
                continue
            }
        }
    }

    /// Hard-wipes every server-synced trip (and via cascade, its photos in
    /// R2) belonging to the signed-in user. Caller stays signed in and
    /// keeps the local copy — every trip is flipped to private locally
    /// and its server bookkeeping cleared. Cloud Sync is forced OFF so
    /// the next sync run doesn't immediately re-upload them. User wants
    /// "clean slate on the server, account intact".
    func wipeServerData() async {
        await MainActor.run {
            SettingsManager.shared.cloudSyncEnabled = false
            SyncQueue.shared.clearAll()
        }
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "serverCreatedAt != nil")
        guard let entities = try? ctx.fetch(req) else { return }
        let repo: TripRepository = CoreDataTripRepository()
        for entity in entities {
            guard let id = entity.id else { continue }
            let body = TripDeleteRequest(id: id, conflictVersion: Int(entity.conflictVersion))
            do {
                let _: EmptyResponse = try await APIClient.shared.post(
                    APIEndpoint.tripDelete, body: body)
            } catch APIError.tripNotFound {
                // Already gone — proceed to local cleanup.
            } catch {
                authLog.error("wipeServerData failed for trip \(id, privacy: .public): \(String(describing: error), privacy: .public)")
                continue
            }
            entity.isPrivate = true
            repo.markUnpublished(tripId: id)
        }
    }

    func signOut() async {
        // Cancel any in-flight post-signin sync chain BEFORE wiping tokens.
        // If we wipe first, the chain's API calls fail with USER_NOT_AUTH,
        // forceSignOut fires, double-signOut chaos. Cancellation lets each
        // step exit cleanly via `Task.isCancelled` checks.
        // Best-effort logout — ignore error
        let _: EmptyResponse? = try? await APIClient.shared.post(APIEndpoint.logout, body: EmptyRequest())
        clearLocalIdentity()
    }

    /// Shared local cleanup invoked after both `signOut` (via `/auth/logout`)
    /// and `deleteAccount` (via `/auth/delete-account`). Centralizes the 6
    /// non-network steps that previously diverged between the two paths and
    /// silently left identity residue from the prior account on the device.
    @MainActor
    private func clearLocalIdentity() {
        // Cancel any in-flight post-sign-in chain BEFORE wiping tokens. The
        // chain holds the old account's token and would otherwise fail mid-
        // flight with USER_NOT_AUTH and trigger a second forceSignOut.
        postSignInSyncTask?.cancel()
        postSignInSyncTask = nil

        TokenStore.shared.clear()
        KeychainHelper.delete(key: Keys.identityToken)
        KeychainHelper.delete(key: Keys.isSignedIn)
        // Wipe identity-shaped Keychain entries. Without this, signing out
        // User A and signing in User B on the same physical device had
        // `loadFromKeychain` replay User A's name onto User B's account.
        KeychainHelper.delete(key: Keys.userIdentifier)
        KeychainHelper.delete(key: Keys.userName)
        KeychainHelper.delete(key: Keys.userEmail)

        isSignedIn = false
        userName = nil
        userEmail = nil
        userIdentifier = nil
        SyncQueue.shared.clearAll()
        // Drop in-app inbox state — the next account on this device should
        // not inherit the previous user's badge or notification list.
        NotificationsInboxStore.shared.clear()
        // Wipe the cached APNs device token so it isn't replayed by the
        // next account's `syncTokenToServer`.
        PushNotificationManager.shared.clearCachedToken()

        // Cross-account leak prevention for trips toggled public locally
        // but never uploaded — see `demotePendingPublicTripsToPrivate`.
        Self.demotePendingPublicTripsToPrivate()

        // Reset Cloud Sync to OFF so the next account makes its own consent
        // choice; clear the GDPR-shown marker so the dialog re-fires.
        SettingsManager.shared.cloudSyncEnabled = false
        UserDefaults.standard.set(false, forKey: "com.triptrack.sync.firstToggleShown")
    }

    /// User-set display name. Apple Sign In delivers `fullName` only on the
    /// very first authorization for a given Apple ID — re-sign-in (after
    /// account delete or token revoke) returns nil and we'd otherwise have
    /// no way to recover the name. This lets the user enter / edit their
    /// name directly in the profile, persisting to Keychain + syncing to
    /// the server so it lands on every public trip card.
    func updateUserName(_ rawName: String) async {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? KeychainHelper.saveString(trimmed, for: Keys.userName)
        userName = trimmed
        await syncProfileToServer()
    }

    // MARK: - Profile sync to server

    /// Push all mutable client-authoritative profile fields to the server so
    /// social feeds / public profile render the user correctly. Covers name,
    /// avatar, background, driver level/XP, streaks, and the active-vehicle
    /// selection for the "Your car" card on the public profile.
    /// Fire-and-forget; failure is logged but not surfaced.
    func syncProfileToServer() async {
        guard isSignedIn else { return }
        let settings = SettingsManager.shared
        // `displayName` is nil for users who signed in before SIWA returned a
        // name — pass nil (skipped in JSON via `encodeIfPresent`) instead of
        // null, otherwise the server would CLEAR a previously-stored name.
        let req = ProfileUpdateRequest(
            displayName: userName,
            avatarEmoji: settings.avatarEmoji,
            profileBackground: settings.profileBackground,
            profileLevel: settings.profileLevel,
            profileXp: settings.profileXP,
            currentStreak: settings.currentStreak,
            bestStreak: settings.bestStreak,
            activeVehicleId: settings.selectedVehicleId?.uuidString
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.profileUpdate, body: req)
            authLog.log("profile synced to server")
            // Feed cards cache `displayName` from `/social/feed`; without a
            // refresh after the profile push, an account that just got a
            // backfilled name (or renamed via long-press) keeps showing the
            // old "No name" / placeholder until the next pull-to-refresh.
            await SocialFeedStore.shared.refresh()
        } catch {
            authLog.error("profile sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete Account

    /// Deletes the account on the server (cascades DB + R2 photo cleanup),
    /// then clears tokens locally. Local CoreData (trips/vehicles/settings) is preserved —
    /// user returns to guest mode and can continue using the app offline.
    func deleteAccount() async throws {
        let _: EmptyResponse = try await APIClient.shared.post(
            APIEndpoint.deleteAccount, body: EmptyRequest())
        // Use the shared cleanup so deleteAccount and signOut leave the
        // device in identical post-state. Earlier divergence missed APNs
        // token wipe, in-flight sync cancel, NotificationsInbox clear,
        // Cloud Sync reset, GDPR-marker reset, and the cross-account
        // demote — all of which leaked into the next account's session.
        clearLocalIdentity()
        authLog.log("Account deleted, returned to guest mode")
    }

    // MARK: - Force Sign Out (sync wrapper for APIClient fallback)

    func forceSignOut() {
        Task { await signOut() }
    }

    // MARK: - Auth Status Check (called on app launch)

    func checkAuthStatus() {
        guard let userId = KeychainHelper.loadString(key: Keys.userIdentifier),
              KeychainHelper.loadString(key: Keys.isSignedIn) != nil else {
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userId) { [weak self] state, _ in
            Task { @MainActor [weak self] in
                switch state {
                case .authorized:
                    if self?.isSignedIn != true { self?.isSignedIn = true }
                case .revoked, .notFound:
                    await self?.signOut()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Private

    private func loadFromKeychain() {
        userIdentifier = KeychainHelper.loadString(key: Keys.userIdentifier)
        userName = KeychainHelper.loadString(key: Keys.userName)
        userEmail = KeychainHelper.loadString(key: Keys.userEmail)
        // Tie isSignedIn to actual token presence, not just the marker key.
        // Without this guard a stale `isSignedIn=true` marker can survive a
        // crash/wipe of the token entries → `tokenStore.accessToken == nil`
        // on every request → backend returns USER_NOT_AUTH forever, but the
        // app keeps thinking the user is logged in and never offers re-auth.
        let hasMarker = KeychainHelper.loadString(key: Keys.isSignedIn) != nil
        let hasUserId = userIdentifier != nil
        let hasTokens = TokenStore.shared.accessToken != nil && TokenStore.shared.refreshToken != nil
        isSignedIn = hasMarker && hasUserId && hasTokens
        authLog.notice("hydrate isSignedIn=\(self.isSignedIn) marker=\(hasMarker) userId=\(hasUserId) tokens=\(hasTokens)")
        if hasMarker && hasUserId && !hasTokens {
            // Marker present but tokens missing — clean up the lie so future
            // launches start in the signed-out state cleanly.
            authLog.error("inconsistent auth state: marker+userId present, tokens missing — clearing marker")
            KeychainHelper.delete(key: Keys.isSignedIn)
        }

        // Backfill for accounts created before the random-name fallback
        // existed: signed-in with no name (Apple Sign In didn't redeliver
        // it after delete-account → re-sign-in) — generate one and push to
        // the server. New accounts hit the same code in `handleAuthorization`
        // before reaching login; this branch only fires on app launch.
        if isSignedIn, (userName?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
            let generated = RandomDisplayName.generate(language: LanguageManager.currentLanguage)
            try? KeychainHelper.saveString(generated, for: Keys.userName)
            userName = generated
            Task { @MainActor in await syncProfileToServer() }
        }
    }
}
