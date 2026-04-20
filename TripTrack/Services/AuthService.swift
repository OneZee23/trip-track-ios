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

        // Name and email only come on first sign-in.
        // On re-sign-in, restore from Keychain.
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
            await performFirstSync()
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

        // Photos that are pending upload (never sent to R2)
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "uploadStatus == %d", PhotoUploadStatus.localOnly.rawValue)
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

        // Reset all local entities so next sign-in re-pushes
        let repo: TripRepository = CoreDataTripRepository()
        repo.markAllPendingUpload()
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
    }
}
