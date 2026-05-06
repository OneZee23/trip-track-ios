import Foundation
import CryptoKit
import Security

/// Cryptographic nonce binding for Sign In with Apple. Apple's documentation
/// requires a one-shot nonce per authorization to prevent identity-token
/// replay attacks: a leaked `identityToken` (10-min Apple lifetime) without a
/// nonce can be re-submitted to `/auth/login` to impersonate the victim
/// because the backend has no way to tell apart the legitimate login attempt
/// from the replay.
///
/// Flow:
///  1. Generate raw 32-byte nonce, hold in memory between `requestedScopes`
///     setup and `onCompletion`.
///  2. Send SHA-256(nonce) as the `request.nonce` to Apple — Apple embeds it
///     in the issued JWT's `nonce` claim.
///  3. Send the RAW nonce to our backend along with the identityToken so the
///     server can hash it and compare against the JWT claim.
///  4. After login completes, discard the nonce (one-shot).
@MainActor
enum SIWANonce {
    /// In-memory store of the nonce most recently issued to a SIWA request.
    /// Replaced on every fresh authorization start; cleared after a login
    /// attempt finishes (success or failure). Never persisted.
    private static var current: String?

    /// Generates a fresh nonce + returns the SHA-256 hash to put on the
    /// `ASAuthorizationAppleIDRequest`. The raw value is kept in memory and
    /// retrievable via `consumeRawNonce()` for the matching login call.
    static func generate() -> String {
        let raw = randomNonceString()
        current = raw
        return sha256(raw)
    }

    /// Returns and clears the raw nonce in one go. Call from
    /// `AuthService.handleAuthorization` to attach to the login request.
    /// Returns nil if no nonce was generated (e.g. legacy code path) — the
    /// backend will then refuse the login because it expects a nonce.
    static func consumeRawNonce() -> String? {
        let value = current
        current = nil
        return value
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            // SecRandomCopyBytes returning non-zero is a system-level
            // failure (CSPRNG broken). Crash-loud is correct here — silently
            // falling back to a weaker source would defeat the whole point
            // of binding nonce.
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
