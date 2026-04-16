import Foundation
import AuthenticationServices

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    private(set) var userIdentifier: String?

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

    func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        let userId = credential.user

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

        if let tokenData = credential.identityToken {
            try? KeychainHelper.save(tokenData, for: Keys.identityToken)
        }

        try? KeychainHelper.saveString("true", for: Keys.isSignedIn)
        isSignedIn = true
    }

    // MARK: - Sign Out

    func signOut() {
        KeychainHelper.delete(key: Keys.identityToken)
        KeychainHelper.delete(key: Keys.isSignedIn)
        // Keep userIdentifier, userName, userEmail in Keychain for re-sign-in

        isSignedIn = false
        userName = nil
        userEmail = nil
        userIdentifier = nil
        SyncQueue.shared.clearAll()
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
                    self?.signOut()
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
