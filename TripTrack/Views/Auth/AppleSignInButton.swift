import SwiftUI
import AuthenticationServices
import OSLog

private let appleButtonLog = Logger(subsystem: "com.triptrack", category: "signin.button")

/// Shared Sign-in-with-Apple button: one place for the nonce binding, the
/// completion chain, the cancel-1001 filter, and the in-flight visual. Both
/// sign-in surfaces (SignInPromptSheet, guest profile sync card) render this —
/// before 6.1.0 they had drifted apart (the profile copy fired its failure
/// alert even when the user cancelled the Apple dialog).
struct AppleSignInButton: View {
    var cornerRadius: CGFloat = 14
    var height: CGFloat = 50
    /// Fired when a tap begins a new authorization attempt — presenters clear
    /// their local error UI here.
    var onRequestBegan: (() -> Void)? = nil
    /// Fired exactly once, on a successful sign-in.
    var onAuthenticated: (() -> Void)? = nil
    /// Fired with localized copy on any failure except user-cancel.
    var onError: ((String) -> Void)? = nil

    @EnvironmentObject private var lang: LanguageManager
    // Singleton by design (matches ProfileView/FeedView) — the button renders
    // in hierarchies that don't inject AuthService as an environment object.
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if auth.isAuthenticating {
            loadingButton
        } else {
            signInButton
        }
    }

    private var signInButton: some View {
        SignInWithAppleButton(.signIn) { req in
            onRequestBegan?()
            req.requestedScopes = [.fullName, .email]
            // Bind the authorization to a one-shot nonce so a leaked
            // identityToken can't be replayed. Apple embeds this hash into
            // the JWT `nonce` claim; the backend compares it against the raw
            // nonce we send alongside the token at login time.
            req.nonce = SIWANonce.generate()
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                appleButtonLog.debug("✅ got credential")
                Task {
                    await auth.handleAuthorization(authorization)
                    if auth.isSignedIn {
                        onAuthenticated?()
                    } else if auth.lastAuthError != nil {
                        // Never echo `String(describing: APIError)` — for
                        // `unknownServer` it would surface server-controlled
                        // text that could leak DB/internal details.
                        onError?(AppStrings.signInPromptAppleFailed(lang.language))
                    }
                }
            case .failure(let error):
                let ns = error as NSError
                appleButtonLog.error("❌ domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
                // Code 1001 = user cancelled the Apple dialog — silent.
                if ns.code != ASAuthorizationError.canceled.rawValue {
                    onError?(AppStrings.signInPromptAppleFailed(lang.language))
                }
            }
        }
        // Borderless white style + our own stroke: the system `.whiteOutline`
        // bakes its border at the button's OWN corner radius, so re-clipping
        // to the Figma shape (r14 sheet / pill card) left the border broken
        // at the corners. Drawing the stroke over the clipped shape keeps it
        // continuous at any radius.
        .signInWithAppleButtonStyle(.white)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    scheme == .dark ? Color.white.opacity(0.14) : Color(red: 219/255, green: 219/255, blue: 224/255),
                    lineWidth: 1.2
                )
        )
    }

    /// Figma frame 125:850: black rounded button at 60% opacity with a white
    /// Apple logo, a 16pt spinner and «Входим…». Replaces the system button
    /// only while the login round-trip is already in flight, so the system
    /// button remains the sole tap target (HIG-safe). Colors invert in dark
    /// theme — Figma only drew light, and black-on-dark had no contrast.
    private var loadingButton: some View {
        let fg: Color = scheme == .dark ? .black : .white
        let bg: Color = scheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.6)
        return HStack(spacing: 10) {
            Image(systemName: "applelogo")
                .font(.system(size: 17, weight: .medium))
            ProgressView()
                .controlSize(.small)
                .tint(fg)
            Text(AppStrings.signInLoading(lang.language))
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(bg, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
