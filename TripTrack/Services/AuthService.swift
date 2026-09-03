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
    /// Server `account.isPublic` («Публичный профиль»). `nil` = unknown —
    /// either not fetched yet or the deployed server lacks `/auth/me`
    /// (capability gate: the privacy toggle in CloudSyncView renders ONLY
    /// when this is non-nil, because an old server silently ignores unknown
    /// profile-update fields and the toggle would fake-succeed).
    @Published private(set) var isPublicProfile: Bool?
    /// Пер-блочная видимость публичного профиля (0.6.3). `nil` — сервер ещё не
    /// ответил или не умеет этих флагов; UI тогда рисует «всё открыто», как и
    /// ведёт себя такой сервер на самом деле.
    @Published private(set) var visibility: ProfileVisibilityFlags?
    /// Поколение на каждый блок видимости — см. `setVisibility`.
    private var visibilityGeneration: [ProfileVisibilityBlock: Int] = [:]
    /// Последний запрос по каждому блоку. Два быстрых переключения одного
    /// тумблера иначе уходят параллельно, и сервер может обработать их в
    /// обратном порядке — экран показал бы «скрыто», а блок остался публичным.
    private var visibilityInFlight: [ProfileVisibilityBlock: Task<Void, Never>] = [:]
    private(set) var userIdentifier: String?

    /// True when the server definitively rejected our refresh token and the
    /// session needs a fresh SIWA sign-in. Unlike a sign-out, ALL local
    /// state survives (trips, pending sync ops, Cloud Sync consent, display
    /// name) — the user chose nothing; the session just died under them.
    /// Persisted to Keychain so a relaunch still shows the re-login prompt.
    /// Cleared by the next successful sign-in or an explicit sign-out.
    @Published private(set) var needsReauth: Bool = false

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
        static let sessionExpired = "com.triptrack.auth.sessionExpired"
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
            authLog.notice("[auth.signout_trigger] reason=user_banned_notification")
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

        // A DIFFERENT Apple ID than the one whose state this device
        // preserved (soft expiry keeps queue/consent/identity) must not
        // inherit any of it — purge BEFORE adopting the new identity.
        prepareForIdentity(userId)

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
            // Clamp to what the server will accept. `displayName` is capped at
            // 30 there and the pipe rejects the WHOLE request on overflow —
            // with the launch retry in place an over-long Apple name would
            // mean a refused push on every cold start, forever.
            let name = ContentFilter.clampedDisplayName(
                [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " "))
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
            // New session begins — kill any in-flight refresh / recovery
            // loop of the previous (dead) session BEFORE storing the new
            // pair, so a stale result can't clobber it.
            APIClient.shared.sessionBoundaryCrossed()
            TokenStore.shared.set(accessToken: response.accessToken, refreshToken: response.refreshToken)
            TokenStore.shared.setAccountId(response.account.id)
            isSignedIn = true
            // A fresh session settles any earlier soft expiry.
            KeychainHelper.delete(key: Keys.sessionExpired)
            needsReauth = false
            // Stamp anon account id on Sentry scope — group events per
            // user without revealing identity (no email, no name).
            SentryService.setAccount(id: response.account.id.uuidString)

            // Read back the account's website-globe opt-in so the toggle
            // reflects the server on a fresh install / new device. Seed BEFORE
            // the syncProfileToServer chain below so it echoes the same value
            // back (no-op) instead of overwriting the server with the local
            // default. Absent (older server) → leave the local mirror as-is.
            if let optIn = response.account.showOnPublicMap {
                SettingsManager.shared.showOnPublicMap = optIn
            }

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
            // Full mirror (data-loss-safe): re-mark everything pendingUpload and
            // enqueue. A pendingUpload-only filter would miss private trips /
            // vehicles edited while Cloud Sync was OFF (they stay .synced). Now
            // cheap: off-main payload build + server no-op on identical upserts.
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

    /// Re-entrancy guard for the signout path. Without it a dead session
    /// self-amplifies: /auth/logout itself fails USER_NOT_AUTH → APIClient
    /// calls forceSignOut → new signOut → new logout → … a tight network
    /// loop (observed at ~15 rps against a backend that doesn't know the
    /// device's tokens, e.g. local dev with prod tokens in Keychain).
    private var signOutInProgress = false

    func signOut() async {
        guard !signOutInProgress else {
            authLog.notice("[auth.signout.skip] reason=already_in_progress")
            return
        }
        signOutInProgress = true
        defer { signOutInProgress = false }
        authLog.notice("[auth.signout.start]")
        // Cancel any in-flight post-signin sync chain BEFORE wiping tokens.
        // If we wipe first, the chain's API calls fail with USER_NOT_AUTH,
        // forceSignOut fires, double-signOut chaos. Cancellation lets each
        // step exit cleanly via `Task.isCancelled` checks.
        // Best-effort logout — ignore error. Skipped entirely when there is
        // no access token: an unauthenticated logout can only produce
        // USER_NOT_AUTH and re-trigger the forceSignOut cascade.
        if TokenStore.shared.accessToken != nil {
            let _: EmptyResponse? = try? await APIClient.shared.post(APIEndpoint.logout, body: EmptyRequest())
        }
        clearLocalIdentity()
        authLog.notice("[auth.signout.done]")
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
        // Kill the old session's in-flight refresh + recovery loop so a
        // stale result can't land on whatever session comes next.
        APIClient.shared.sessionBoundaryCrossed()

        TokenStore.shared.clear()
        KeychainHelper.delete(key: Keys.identityToken)
        KeychainHelper.delete(key: Keys.isSignedIn)
        // A deliberate sign-out settles any pending soft expiry — the user
        // should not land on a "session expired" prompt they didn't cause.
        KeychainHelper.delete(key: Keys.sessionExpired)
        needsReauth = false
        // The Apple user id goes too — a real sign-out drops the identity
        // entirely (name/email are wiped inside purgeAccountScopedState).
        KeychainHelper.delete(key: Keys.userIdentifier)

        isSignedIn = false
        // Identity-shaped state (name/email keychain + memory) and the
        // account-scoped caches share cleanup with the cross-account
        // sign-in path — see purgeAccountScopedState.
        SentryService.setAccount(id: nil)
        userIdentifier = nil
        purgeAccountScopedState()
    }

    /// Everything on this device that belongs to the ACCOUNT rather than the
    /// device: pending sync ops, Cloud Sync consent, display identity,
    /// social/inbox/companions caches, APNs token, pending-public trips.
    /// Called from `clearLocalIdentity` (sign-out / delete) and from
    /// `prepareForIdentity` when a DIFFERENT Apple ID signs in after a soft
    /// session expiry — which preserves all of this for the SAME user, so a
    /// different user must not inherit it.
    @MainActor
    private func purgeAccountScopedState() {
        // Wipe identity-shaped Keychain entries. Without this, signing out
        // User A and signing in User B on the same physical device had
        // `loadFromKeychain` replay User A's name onto User B's account.
        KeychainHelper.delete(key: Keys.userName)
        KeychainHelper.delete(key: Keys.userEmail)
        userName = nil
        userEmail = nil
        // The next Apple ID on this phone has pushed nothing yet. Leaving the
        // previous account's «confirmed» behind would swallow its first push
        // and leave it nameless — the very failure this latch exists to catch.
        ProfileSyncLatch.reset()
        // Следующий Apple ID на этом телефоне — другой человек с другим
        // публичным профилем; он тоже имеет право узнать, что о нём видно.
        VisibilityNoticeLatch.reset()
        // Server-flag mirror back to "unknown" — the next account must not
        // inherit the previous account's privacy-toggle state, and the gate
        // re-verifies endpoint availability via refreshMe() after sign-in.
        isPublicProfile = nil
        visibility = nil
        // Reset the website-globe opt-in mirror so account A's toggle doesn't
        // visually leak onto account B on the same device before B's login
        // read-back seeds the real value. (Server state is per-account; this is
        // only the local UI mirror.)
        SettingsManager.shared.showOnPublicMap = false
        SyncQueue.shared.clearAll()
        // Drop in-app inbox state — the next account on this device should
        // not inherit the previous user's badge or notification list.
        NotificationsInboxStore.shared.clear()
        // Drop the cached social feed too. Sign-out happens on the Me tab
        // where FeedView is unmounted (its `.onChange(of: auth.isSignedIn)`
        // never fires), and `loadIfNeeded` no-ops inside the 15-minute
        // freshness window — without this a signed-out guest kept the
        // follow-personalized feed with stale `myReaction` highlights, and
        // their own trips rendered as strangers' cards.
        SocialFeedStore.shared.clear()
        SocialFeedStore.following.clear()
        // Companions are per-account by definition — without this, the next
        // account signing in on this device would see the previous
        // account's cached roster/candidates/"со мной" list until each
        // screen happened to re-fetch.
        CompanionsStore.shared.clear()
        // `CompanionsStore.clear()` only wipes IN-MEMORY state — the
        // on-device cache (`TripEntity.companionsJSON`, written by
        // `TripRepository.updateCompanions` every time this device
        // successfully loads a roster for one of its own trips) survives a
        // sign-out because local trips are device-scoped, not
        // account-scoped (see `clearCompanionsCache`'s doc comment). Without
        // this, the next account signing in on this device would see the
        // PREVIOUS account's cached roster on any trip whose detail screen
        // they open, until that trip happened to re-fetch.
        CoreDataTripRepository().clearCompanionsCache()
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

    /// Cross-account guard for sign-in. Soft session expiry deliberately
    /// preserves the previous user's sync queue, Cloud Sync consent, and
    /// identity so the SAME user re-signing in loses nothing — but that
    /// makes it load-bearing to purge all of it when a DIFFERENT Apple ID
    /// signs in on this device, or user B would inherit user A's pending
    /// uploads, consent, and display name. No-op when the identity matches
    /// or nothing was preserved.
    func prepareForIdentity(_ userId: String) {
        let previous = userIdentifier ?? KeychainHelper.loadString(key: Keys.userIdentifier)
        guard let previous, previous != userId else { return }
        authLog.notice("[auth.cross_account] purging state of previous identity before sign-in")
        postSignInSyncTask?.cancel()
        postSignInSyncTask = nil
        purgeAccountScopedState()
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
    func syncProfileToServer(refreshFeedAfter: Bool = true) async {
        guard isSignedIn else { return }
        let settings = SettingsManager.shared
        // `displayName` is nil for users who signed in before SIWA returned a
        // name — pass nil (skipped in JSON via `encodeIfPresent`) instead of
        // null, otherwise the server would CLEAR a previously-stored name.
        // Use the in-app language override (LanguageManager) rather
        // than re-parsing Locale here — the user might be on an English
        // OS but have set RU manually inside TripTrack, and we want
        // their weekly-recap push to match what they see in the app.
        let preferredLanguage = LanguageManager.currentLanguage.rawValue

        let req = ProfileUpdateRequest(
            displayName: userName,
            avatarEmoji: settings.avatarEmoji,
            profileBackground: settings.profileBackground,
            profileLevel: settings.profileLevel,
            profileXp: settings.profileXP,
            currentStreak: settings.currentStreak,
            bestStreak: settings.bestStreak,
            activeVehicleId: settings.selectedVehicleId?.uuidString,
            language: preferredLanguage,
            showOnPublicMap: settings.showOnPublicMap
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.profileUpdate, body: req)
            // Only record against a session that is still ours. A sign-out
            // that lands while this is in flight has already cleared the
            // latch; writing "confirmed" afterwards would suppress the NEXT
            // account's first push and leave IT nameless.
            if isSignedIn { ProfileSyncLatch.markConfirmed() }
            authLog.log("profile synced to server")
            // Feed cards cache `displayName` from `/social/feed`; without a
            // refresh after the profile push, an account that just got a
            // backfilled name (or renamed via long-press) keeps showing the
            // old "No name" / placeholder until the next pull-to-refresh.
            // Skipped for pushes that don't touch feed-visible fields (e.g. the
            // globe opt-in, which only affects the website /public/map).
            if refreshFeedAfter {
                await SocialFeedStore.shared.refresh()
            }
        } catch {
            // Reopen the latch so the next launch retries. The server
            // validates the DTO as a whole, so a single unhappy field (an
            // over-long Apple name, a future field) rejects the name too —
            // and without this the rejection was permanent. Scoped to a live
            // session for the same reason as the success branch.
            if isSignedIn { ProfileSyncLatch.markUnconfirmed() }
            authLog.error("profile sync failed: \(error.localizedDescription)")
        }
    }

    /// Launch backfill for a name the server never acknowledged. Pushes the
    /// NAME ALONE — see `ProfileUpdateRequest.nameOnly`: the rest of
    /// `syncProfileToServer`'s payload mirrors THIS device, and a second phone
    /// opened for the first time after an update would otherwise roll the
    /// account back to its stale mirror (name, globe opt-in, level, streaks).
    ///
    /// Deliberately does NOT refresh the social feed afterwards: this runs
    /// from `loadFromKeychain`, i.e. cold launch, before the feed has loaded
    /// at all — a refresh here only cancels and duplicates that first fetch.
    private func pushDisplayNameToServer() async {
        guard isSignedIn else { return }
        let name = (userName ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.profileUpdate, body: ProfileUpdateRequest.nameOnly(name))
            if isSignedIn { ProfileSyncLatch.markConfirmed() }
            authLog.log("display name backfilled to server")
        } catch {
            if isSignedIn { ProfileSyncLatch.markUnconfirmed() }
            authLog.error("display name backfill failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Account visibility (/auth/me)

    /// Reads the account snapshot from `POST /auth/me`. Success seeds
    /// `isPublicProfile` (and backfills the Keychain email when Apple never
    /// redelivered it). ANY failure — route missing on old prod, network,
    /// decode — leaves `isPublicProfile` untouched and never throws to the
    /// UI: the account page simply hides the privacy toggle (F2 gating).
    /// Bumped by every explicit `setPublicProfile` write. Snapshot reads
    /// (`refreshMe`) capture it before the request and apply the response
    /// only if no write happened meanwhile — otherwise a slow /auth/me
    /// response taken BEFORE the toggle would visibly revert it. Same guard
    /// serializes two rapid toggle flips (the stale one's success write is
    /// dropped; the server processed them in send order).
    private var publicProfileGeneration = 0

    func refreshMe() async {
        guard isSignedIn else { return }
        let gen = publicProfileGeneration
        // Снимок поколений ПО БЛОКАМ. `setVisibility` намеренно не трогает
        // общий счётчик (иначе он отменял бы запись «Публичного профиля»), так
        // что от устаревшего ответа блоки надо защищать отдельно: иначе
        // тумблер, переключённый во время этого запроса, отскочит назад, хотя
        // сервер сохранил новое значение.
        let blockGens = visibilityGeneration
        do {
            let res: MeResponse = try await APIClient.shared.post(
                APIEndpoint.authMe, body: EmptyRequest())
            if gen == publicProfileGeneration {
                isPublicProfile = res.isPublic
                // nil, если сервер не знает этих флагов — тумблеры тогда
                // остаются неактивными, а не притворяются работающими.
                let fresh = ProfileVisibilityFlags(res)
                visibility = Self.merged(
                    incoming: fresh, current: visibility,
                    generationsAtRequest: blockGens, generationsNow: visibilityGeneration)
            }
            if userEmail == nil, let email = res.email,
               !email.trimmingCharacters(in: .whitespaces).isEmpty {
                try? KeychainHelper.saveString(email, for: Keys.userEmail)
                userEmail = email
            }
        } catch {
            authLog.error("refreshMe failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Явный пуш одного тумблера видимости (0.6.3).
    ///
    /// Payload несёт РОВНО одно поле — как и `setPublicProfile`. Причина та же:
    /// сервер валидирует DTO целиком, и лишнее поле в этом же запросе уронило
    /// бы вместе с собой всё остальное. Возвращает false, чтобы UI откатил
    /// оптимистично переключённый тумблер.
    /// Слить ответ `/auth/me` с локальным зеркалом, не затирая блоки, по
    /// которым за время запроса прошла запись.
    ///
    /// Ответ мог уйти ДО того, как человек тронул тумблер: он вернётся со
    /// старым значением и, если применить его целиком, снимет только что
    /// сохранённое. Побитовое сравнение поколений оставляет такие блоки как
    /// есть, а остальные обновляет.
    nonisolated static func merged(
        incoming: ProfileVisibilityFlags?,
        current: ProfileVisibilityFlags?,
        generationsAtRequest: [ProfileVisibilityBlock: Int],
        generationsNow: [ProfileVisibilityBlock: Int]
    ) -> ProfileVisibilityFlags? {
        guard let incoming else { return current }
        guard let current else { return incoming }
        var result = incoming
        for block in ProfileVisibilityBlock.allCases
        where generationsAtRequest[block] != generationsNow[block] {
            result.set(block, current.value(block))
        }
        return result
    }

    /// Переключить видимость блока.
    ///
    /// Запросы ПО ОДНОМУ блоку выстраиваются в цепочку: два быстрых нажатия на
    /// один тумблер иначе уходят параллельно, сервер вправе обработать их в
    /// обратном порядке, и экран показал бы «скрыто», пока блок остаётся
    /// публичным. Разные блоки по-прежнему идут независимо.
    func setVisibility(_ block: ProfileVisibilityBlock, _ isOn: Bool) async -> Bool {
        let previous = visibilityInFlight[block]
        let work = Task<Bool, Never> { [weak self] in
            await previous?.value
            guard let self else { return false }
            return await self.performSetVisibility(block, isOn)
        }
        visibilityInFlight[block] = Task { _ = await work.value }
        return await work.value
    }

    private func performSetVisibility(_ block: ProfileVisibilityBlock, _ isOn: Bool) async -> Bool {
        var req = ProfileUpdateRequest(
            displayName: nil, avatarEmoji: nil, profileBackground: nil,
            profileLevel: nil, profileXp: nil, currentStreak: nil,
            bestStreak: nil, activeVehicleId: nil, language: nil,
            showOnPublicMap: nil)
        switch block {
        case .counters: req.countersPublic = isOn
        case .stats: req.statsPublic = isOn
        case .map: req.mapPublic = isOn
        case .achievements: req.achievementsPublic = isOn
        }
        // Поколение НА БЛОК, а не одно на все четыре: с общим счётчиком
        // быстрое переключение второго тумблера отменяло бы запись первого —
        // сервер сохранил, зеркало не обновилось, переключатель отскочил.
        //
        // Общий `publicProfileGeneration` здесь НЕ трогаем: он принадлежит
        // тумблеру «Публичный профиль», и его инкремент отсюда отменял бы
        // запись того, ни в чём не повинного, запроса.
        visibilityGeneration[block, default: 0] += 1
        let blockGen = visibilityGeneration[block]
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.profileUpdate, body: req)
            guard blockGen == visibilityGeneration[block] else { return true }
            var current = visibility ?? .open
            current.set(block, isOn)
            visibility = current
            authLog.log("visibility \(String(describing: block)) set to \(isOn)")
            return true
        } catch {
            authLog.error("setVisibility failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Explicit toggle push — the ONLY code path that sends `isPublic` to the
    /// server (see the `ProfileUpdateRequest.isPublic` doc: `syncProfileToServer`
    /// must never include it). Payload carries nothing but `isPublic`, so a
    /// concurrent profile sync can't be clobbered either way.
    /// Returns false on failure so the UI can revert the optimistic toggle.
    func setPublicProfile(_ isPublic: Bool) async -> Bool {
        var req = ProfileUpdateRequest(
            displayName: nil,
            avatarEmoji: nil,
            profileBackground: nil,
            profileLevel: nil,
            profileXp: nil,
            currentStreak: nil,
            bestStreak: nil,
            activeVehicleId: nil,
            language: nil,
            showOnPublicMap: nil
        )
        req.isPublic = isPublic
        publicProfileGeneration += 1
        let gen = publicProfileGeneration
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.profileUpdate, body: req)
            if gen == publicProfileGeneration {
                isPublicProfile = isPublic
            }
            authLog.log("public profile set to \(isPublic)")
            return true
        } catch {
            authLog.error("setPublicProfile failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - Delete Account

    /// Deletes the account on the server (cascades DB + R2 photo cleanup),
    /// then clears tokens locally. Local CoreData (trips/vehicles/settings) is preserved —
    /// user returns to guest mode and can continue using the app offline.
    /// Closes the account for good — server first, then this device.
    ///
    /// Apple 5.1.1(v) requires an in-app path that deletes the ACCOUNT and its
    /// server-side data; our own rule adds the second half, because the row
    /// that calls this says «безвозвратно, везде» and a promise printed on a
    /// destructive button has to be literally true. `wipeLocalData` is the
    /// switch for that half — see `LocalDataWipe` for exactly what goes.
    ///
    /// The server call comes FIRST and is allowed to throw: erasing the phone
    /// and then failing to reach the server would leave the account alive with
    /// no copy of anything left to try again from.
    func deleteAccount(wipeLocalData: Bool = true) async throws {
        let _: EmptyResponse = try await APIClient.shared.post(
            APIEndpoint.deleteAccount, body: EmptyRequest())
        if wipeLocalData { LocalDataWipe.run() }
        // Use the shared cleanup so deleteAccount and signOut leave the
        // device in identical post-state. Earlier divergence missed APNs
        // token wipe, in-flight sync cancel, NotificationsInbox clear,
        // Cloud Sync reset, GDPR-marker reset, and the cross-account
        // demote — all of which leaked into the next account's session.
        clearLocalIdentity()
        authLog.log("Account deleted, returned to guest mode")
    }

    // MARK: - Session Expiry (called by APIClient when the session is dead)

    /// SOFT expiry for a definitively dead session (refresh token rejected).
    /// Replaces the old destructive `forceSignOut`, which ran the full
    /// sign-out cascade: it cleared the sync queue, demoted pending trips,
    /// disabled Cloud Sync, and wiped the display name — so a session that
    /// died through no fault of the user (the 2026-08-23 lost-rotation
    /// incident) also stranded their freshly-recorded trip on the phone.
    ///
    /// This path drops ONLY what is already dead — the token pair and the
    /// signed-in marker — and raises `needsReauth` so the UI offers a
    /// re-login. Everything else (CoreData, pending sync ops, Cloud Sync
    /// consent, identity for SIWA prefill, feeds, notifications) survives:
    /// after the next sign-in `performFirstSync` re-uploads whatever the
    /// dead session failed to push.
    func sessionExpired() {
        // Once already expired (or mid-signout) there is nothing to do —
        // repeated triggers arrive in bursts when several in-flight calls
        // fail together (the incident log shows three within one second).
        guard isSignedIn || TokenStore.shared.accessToken != nil, !signOutInProgress else {
            authLog.notice("[auth.session_expired.skip] reason=already_expired_or_signing_out")
            return
        }
        authLog.error("[auth.session_expired] keeping local data, requesting re-login")
        // Cancel the post-sign-in chain for the same reason signOut does:
        // its calls would fail with USER_NOT_AUTH and re-trigger this path.
        postSignInSyncTask?.cancel()
        postSignInSyncTask = nil
        // Kill in-flight refresh + armed recovery of the dead session so a
        // stale result can't resurrect or re-expire a future session.
        APIClient.shared.sessionBoundaryCrossed()

        TokenStore.shared.clear()
        KeychainHelper.delete(key: Keys.isSignedIn)
        try? KeychainHelper.saveString("true", for: Keys.sessionExpired)

        isSignedIn = false
        needsReauth = true
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
                    authLog.notice("[auth.credential_state] state=authorized")
                    // CONFIRM a session, never create one: the SIWA
                    // credential being fine says nothing about the server
                    // session. If a soft expiry landed while this async
                    // callback was in flight (marker gone, tokens cleared,
                    // needsReauth up), resurrecting isSignedIn here would
                    // hide the re-login card and re-open the sync gate with
                    // no tokens to sync with.
                    let sessionStillLive = self?.needsReauth != true
                        && KeychainHelper.loadString(key: Keys.isSignedIn) != nil
                        && TokenStore.shared.accessToken != nil
                    if sessionStillLive, self?.isSignedIn != true { self?.isSignedIn = true }
                    if sessionStillLive, let accountId = TokenStore.shared.accountId {
                        SentryService.setAccount(id: accountId.uuidString)
                    }
                case .revoked:
                    authLog.notice("[auth.signout_trigger] reason=apple_credential_revoked")
                    await self?.signOut()
                case .notFound:
                    // .notFound is NOT a reliable revocation signal — it can
                    // surface transiently (Apple ID server unreachable, or right
                    // after install before the credential propagates). Only sign
                    // out if we also lack valid tokens; otherwise keep the
                    // session. Cleanup of a genuinely dead-but-token-present
                    // session is best-effort and deferred: the next authed
                    // request that hits a confirmed USER_NOT_AUTH after refresh
                    // force-signs-out (APIClient). On the common launch path the
                    // feed's authed load triggers this; in the rare corner where
                    // no authed call is made (lands on a non-feed tab, no sync,
                    // notifications off) it simply waits for the next one. This
                    // removes a spurious cold-launch logout vector while keeping
                    // .revoked as the authoritative immediate-signout signal.
                    let hasTokens = TokenStore.shared.accessToken != nil
                        && TokenStore.shared.refreshToken != nil
                    if hasTokens {
                        authLog.notice("[auth.credential_state] state=notFound but tokens present — keeping session")
                    } else {
                        authLog.notice("[auth.signout_trigger] reason=apple_credential_not_found_no_tokens")
                        await self?.signOut()
                    }
                default:
                    authLog.notice("[auth.credential_state] state=undef_\(state.rawValue, privacy: .public)")
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
        // Restore a soft session expiry across relaunches: the flag is set by
        // sessionExpired() and cleared by the next sign-in or sign-out.
        needsReauth = !isSignedIn && hasUserId
            && KeychainHelper.loadString(key: Keys.sessionExpired) != nil
        authLog.notice("hydrate isSignedIn=\(self.isSignedIn) marker=\(hasMarker) userId=\(hasUserId) tokens=\(hasTokens) needsReauth=\(self.needsReauth)")
        if hasMarker && hasUserId && !hasTokens {
            // Marker present but tokens missing — the session died without
            // going through sessionExpired() (crash mid-signout, keychain
            // partial wipe). Convert the lie into the same soft-expiry state
            // instead of silently degrading to guest: data is intact, the
            // user just needs a fresh sign-in.
            authLog.error("inconsistent auth state: marker+userId present, tokens missing — converting to soft expiry")
            KeychainHelper.delete(key: Keys.isSignedIn)
            try? KeychainHelper.saveString("true", for: Keys.sessionExpired)
            needsReauth = true
        }
        if isSignedIn {
            // A live session means any stale expiry flag is a leftover.
            KeychainHelper.delete(key: Keys.sessionExpired)
            needsReauth = false
        }

        // Two reasons to push the profile on launch, and the second one is why
        // this branch got rewritten:
        //
        //  - No name anywhere. Apple Sign In delivers `fullName` only on the
        //    very first authorization, so a re-sign-in after delete-account
        //    arrives without one — generate it here. New accounts hit the same
        //    code in `handleAuthorization` before reaching login.
        //  - A name on this phone that the SERVER never acknowledged. The push
        //    is fire-and-forget and the server validates the whole DTO, so one
        //    rejected field takes the name down with it. That used to be
        //    permanent: the old gate asked only whether the Keychain had a
        //    name, and for exactly these users it did. See `ProfileSyncLatch`.
        //
        // Deferred to the next runloop tick so the @Published `userName`
        // write doesn't happen inside the `.shared` lazy-init path that
        // SwiftUI triggers from the first body that reads
        // `@ObservedObject auth = AuthService.shared` — synchronous writes
        // there cause an AttributeGraph cycle on cold launch.
        if ProfileSyncLatch.needsPush(isSignedIn: isSignedIn, localName: userName) {
            let generated = (userName?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                ? RandomDisplayName.generate(language: LanguageManager.currentLanguage)
                : nil
            if let generated {
                try? KeychainHelper.saveString(generated, for: Keys.userName)
            }
            // Wrapping the @Published `userName` write in a fresh
            // `Task { @MainActor ... }` escapes the synchronous lazy-
            // init call chain that SwiftUI triggers when the first
            // body reads `@ObservedObject auth = AuthService.shared`.
            // The Task hop alone is sufficient — the body runs on a
            // new continuation, not on the init's call stack — so no
            // AttributeGraph cycle. Per CLAUDE.md we use `Task @MainActor`
            // rather than DispatchQueue.main.async.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let generated { self.userName = generated }
                await self.pushDisplayNameToServer()
            }
        }
    }
}
