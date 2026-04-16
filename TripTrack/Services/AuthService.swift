// TripTrack/Services/AuthService.swift
import Foundation
import AuthenticationServices

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    @Published private(set) var userIdentifier: String?

    // Keychain keys
    private enum Keys {
        static let userIdentifier = "com.triptrack.auth.userIdentifier"
        static let userName = "com.triptrack.auth.userName"
        static let userEmail = "com.triptrack.auth.userEmail"
        static let identityToken = "com.triptrack.auth.identityToken"
        static let isSignedIn = "com.triptrack.auth.isSignedIn"
    }

    private override init() {
        super.init()
        loadFromKeychain()
    }

    // MARK: - Sign In

    func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    // MARK: - Sign Out

    func signOut() {
        // Remove session-related keys only
        KeychainHelper.delete(key: Keys.identityToken)
        KeychainHelper.delete(key: Keys.isSignedIn)
        // Keep: userIdentifier, userName, userEmail (for re-sign-in)

        isSignedIn = false
        SyncQueue.shared.clearAll()
    }

    // MARK: - Auth Status Check (called on app launch)

    func checkAuthStatus() {
        guard let userId = KeychainHelper.loadString(key: Keys.userIdentifier),
              KeychainHelper.loadString(key: Keys.isSignedIn) != nil else {
            isSignedIn = false
            return
        }

        // Verify with Apple that credentials haven't been revoked
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userId) { [weak self] state, _ in
            Task { @MainActor [weak self] in
                switch state {
                case .authorized:
                    self?.isSignedIn = true
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

    private func handleSuccessfulAuth(credential: ASAuthorizationAppleIDCredential) {
        let userId = credential.user

        // Save userIdentifier always
        try? KeychainHelper.saveString(userId, for: Keys.userIdentifier)
        userIdentifier = userId

        // Name and email only come on first sign-in.
        // If Apple sends them, save. Otherwise keep existing Keychain values.
        if let fullName = credential.fullName {
            let name = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !name.isEmpty {
                try? KeychainHelper.saveString(name, for: Keys.userName)
                userName = name
            }
        }

        if let email = credential.email {
            try? KeychainHelper.saveString(email, for: Keys.userEmail)
            userEmail = email
        } else if userName == nil {
            // Restore from keychain on re-sign-in
            userName = KeychainHelper.loadString(key: Keys.userName)
            userEmail = KeychainHelper.loadString(key: Keys.userEmail)
        }

        // Save identity token for future backend
        if let tokenData = credential.identityToken {
            try? KeychainHelper.save(tokenData, for: Keys.identityToken)
        }

        // Mark session active
        try? KeychainHelper.saveString("true", for: Keys.isSignedIn)
        isSignedIn = true
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        Task { @MainActor in
            handleSuccessfulAuth(credential: credential)
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        #if DEBUG
        print("Sign in with Apple failed: \(error.localizedDescription)")
        #endif
    }
}
