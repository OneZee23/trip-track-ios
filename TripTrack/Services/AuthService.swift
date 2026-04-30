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

    private enum Keys {
        static let userIdentifier = "com.triptrack.auth.userIdentifier"
        static let userName = "com.triptrack.auth.userName"
        static let userEmail = "com.triptrack.auth.userEmail"
        static let identityToken = "com.triptrack.auth.identityToken"
        static let isSignedIn = "com.triptrack.auth.isSignedIn"
    }

    private init() {
        loadFromKeychain()
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
        try? KeychainHelper.save(tokenData, for: Keys.identityToken)
        try? KeychainHelper.saveString("true", for: Keys.isSignedIn)

        // Call server /auth/login
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let body = LoginRequest(
                identityToken: tokenData.base64EncodedString(),
                localUserId: SettingsManager.shared.localUserId.uuidString,
                deviceName: UIDevice.current.name
            )
            let response: LoginResponse = try await APIClient.shared.post(
                APIEndpoint.login, body: body, requiresAuth: false)
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

            await performFirstSync()
            await syncProfileToServer()
            // If APNs already handed us a token (likely — onboarding registers
            // before sign-in), push it now so backend can dispatch reactions /
            // follow notifications to this device. Re-registering here also
            // covers the case where the user signed out, came back, and the
            // existing cached token is still valid.
            PushNotificationManager.shared.registerForRemoteNotifications()
            await PushNotificationManager.shared.syncTokenToServer()
            // Pull the inbox once so the badge is accurate the first time
            // the user looks at Profile after signing in.
            await NotificationsInboxStore.shared.refresh()
        } catch let e as APIError {
            lastAuthError = e
        } catch {
            lastAuthError = .transport(error.localizedDescription)
        }
    }

    // MARK: - First Sync

    private func performFirstSync() async {
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

        // Photos that aren't fully on R2 yet — `localOnly` (never uploaded),
        // `uploading` (thumb sent but original stuck behind a Wi-Fi gate),
        // and `failed` (previous attempt errored). Mirrors the predicate in
        // `CloudSyncView.enableCloudSync` so first-sign-in and toggle-on
        // paths backfill the same set.
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

        await SyncCoordinator.shared.runFullSync()
    }

    // MARK: - Sign Out

    func signOut() async {
        // Best-effort logout — ignore error
        let _: EmptyResponse? = try? await APIClient.shared.post(APIEndpoint.logout, body: EmptyRequest())
        TokenStore.shared.clear()
        KeychainHelper.delete(key: Keys.identityToken)
        KeychainHelper.delete(key: Keys.isSignedIn)

        isSignedIn = false
        userName = nil
        userEmail = nil
        userIdentifier = nil
        SyncQueue.shared.clearAll()
        // Drop in-app inbox state — the next account that signs in on
        // this device should not inherit the previous user's badge or
        // notification list.
        NotificationsInboxStore.shared.clear()
        // Wipe the cached APNs device token. The server already cleared
        // the row inside `/auth/logout`, but the local UserDefaults copy
        // would otherwise resurface in `syncTokenToServer` and re-bind
        // the token to whatever account signs in next.
        PushNotificationManager.shared.clearCachedToken()

        // Reset all local entities so next sign-in re-pushes
        let repo: TripRepository = CoreDataTripRepository()
        repo.markAllPendingUpload()
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

        TokenStore.shared.clear()
        KeychainHelper.delete(key: Keys.identityToken)
        KeychainHelper.delete(key: Keys.isSignedIn)
        KeychainHelper.delete(key: Keys.userIdentifier)
        KeychainHelper.delete(key: Keys.userName)
        KeychainHelper.delete(key: Keys.userEmail)

        isSignedIn = false
        userName = nil
        userEmail = nil
        userIdentifier = nil
        SyncQueue.shared.clearAll()

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
        isSignedIn = KeychainHelper.loadString(key: Keys.isSignedIn) != nil && userIdentifier != nil

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
