import SwiftUI
import AuthenticationServices
import OSLog

private let signInPromptLog = Logger(subsystem: "com.triptrack", category: "signin.prompt")

/// Lightweight friction-low Sign-in-with-Apple sheet, presented when a guest
/// tries to do something that needs an account (react, follow, share, sync).
/// Localized headline tells them why we're asking — generic "Sign in" prompts
/// are noticeably worse for conversion than action-specific ones.
struct SignInPromptSheet: View {
    enum Action: String, Identifiable {
        case react
        case follow
        case share
        case sync
        case publish
        case generic

        var id: String { rawValue }

        func headline(_ lang: LanguageManager.Language) -> String {
            switch self {
            case .react:    return AppStrings.signInPromptReact(lang)
            case .follow:   return AppStrings.signInPromptFollow(lang)
            case .share:    return AppStrings.signInPromptShare(lang)
            case .sync:     return AppStrings.signInPromptSync(lang)
            case .publish:  return AppStrings.signInPromptPublish(lang)
            case .generic:  return AppStrings.signInPromptGeneric(lang)
            }
        }
    }

    let action: Action
    /// Fired exactly once, on a *successful* sign-in, right before the sheet
    /// dismisses. Lets the presenter resume the action the guest originally
    /// tapped (e.g. share / react) instead of silently dropping it. Not called
    /// on cancel / "maybe later" / Apple failure.
    var onAuthenticated: (() -> Void)? = nil
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var lastError: String?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 56))
                        .foregroundStyle(AppTheme.accent)

                    Text(action.headline(lang.language))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.center)

                    Text(AppStrings.signInPromptSubtitle(lang.language))
                        .font(.system(size: 14))
                        .foregroundStyle(c.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                bulletList(c: c, isRu: isRu)
                    .padding(.horizontal, 24)

                Spacer()

                if let err = lastError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                SignInWithAppleButton(.signIn,
                    onRequest: { req in
                        req.requestedScopes = [.fullName, .email]
                        // Bind the authorization to a one-shot nonce so a
                        // leaked identityToken can't be replayed. Apple
                        // embeds this hash into the JWT `nonce` claim; the
                        // backend compares it against the raw nonce we send
                        // alongside the token at login time.
                        req.nonce = SIWANonce.generate()
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            signInPromptLog.debug("✅ got credential")
                            Task {
                                await auth.handleAuthorization(authorization)
                                if auth.isSignedIn {
                                    onAuthenticated?()
                                    dismiss()
                                }
                                else if auth.lastAuthError != nil {
                                    // Never echo `String(describing: APIError)` — for
                                    // `unknownServer` it would surface server-controlled
                                    // text that could leak DB/internal details. The
                                    // generic localized copy covers every error mode
                                    // in a way appropriate for the sign-in surface.
                                    lastError = AppStrings.signInPromptAppleFailed(lang.language)
                                }
                            }
                        case .failure(let error):
                            let ns = error as NSError
                            signInPromptLog.error("❌ domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
                            // Code 1001 = user cancelled — silent. Anything else, show.
                            if ns.code != ASAuthorizationError.canceled.rawValue {
                                lastError = AppStrings.signInPromptAppleFailed(lang.language)
                            }
                        }
                    })
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .padding(.horizontal, 24)

                Button(AppStrings.signInPromptMaybeLater(lang.language)) {
                    dismiss()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textSecondary)
                .padding(.bottom, 16)
            }
            .background(c.bg)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
        }
    }

    private func bulletList(c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            bullet(icon: "icloud.fill", color: AppTheme.blue,
                   text: AppStrings.signInPromptBulletSync(lang.language),
                   c: c)
            bullet(icon: "heart.fill", color: .red,
                   text: AppStrings.signInPromptBulletReact(lang.language),
                   c: c)
            bullet(icon: "square.and.arrow.up", color: AppTheme.accent,
                   text: AppStrings.signInPromptBulletPublish(lang.language),
                   c: c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(icon: String, color: Color, text: String, c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                // Long RU bullet ("Синхронизация на всех Ваших устройствах"
                // = 38 chars) otherwise wraps to two lines and breaks
                // vertical rhythm with the other 1-line bullets.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
