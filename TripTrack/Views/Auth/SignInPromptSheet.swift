import SwiftUI

/// Sign-in bottom sheet (Figma 124:837 default / 125:850 loading / 126:863
/// error). Presented when a guest tries to do something that needs an account
/// (react, follow, share, sync). Localized headline tells them why we're
/// asking — generic "Sign in" prompts are noticeably worse for conversion
/// than action-specific ones. The grabber and the X are the guest affordance;
/// there is no "maybe later" button. All presentation chrome lives HERE so
/// the five call sites stay one-liners.
struct SignInPromptSheet: View {
    enum Action: String, Identifiable {
        case react
        case comment
        case follow
        case share
        case sync
        case publish
        case generic

        var id: String { rawValue }

        func headline(_ lang: LanguageManager.Language) -> String {
            switch self {
            case .react:    return AppStrings.signInPromptReact(lang)
            case .comment:  return AppStrings.signInPromptComment(lang)
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
    /// on cancel / close / Apple failure.
    var onAuthenticated: (() -> Void)? = nil
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            // Custom grabber — the system indicator is hidden because Figma
            // draws its own (34×5, 18%) inside the sheet. `primary` keeps it
            // visible on the dark theme background.
            Capsule()
                .fill(.primary.opacity(0.18))
                .frame(width: 34, height: 5)
                .padding(.top, 8)

            // The header zone is deliberately tall (Figma: X center ~73pt
            // below the sheet top, ring top ~131) — the content block is
            // bottom-weighted, not squeezed under the grabber.
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                // Dimmed while authenticating (Figma 125:850) but NOT
                // disabled: login can take minutes on flaky networks and the
                // sheet must never trap the user. Dismissal doesn't cancel
                // the request — on success the presenter still resumes.
                .opacity(auth.isAuthenticating ? 0.4 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 44)

            VStack(spacing: 0) {
                SignInIdleRing()
                    .padding(.top, 40)

                Text(action.headline(lang.language))
                    .font(.system(size: 21, weight: .heavy))
                    .kerning(-0.21)
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)

                Text(AppStrings.signInPromptSubtitle(lang.language))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                AppleSignInButton(
                    cornerRadius: 14,
                    height: 50,
                    onRequestBegan: { showError = false },
                    onAuthenticated: {
                        onAuthenticated?()
                        dismiss()
                    },
                    onError: { _ in
                        showError = true
                        // Consume the service-level error so presenters with
                        // their own `lastAuthError`-driven alerts don't fire a
                        // second error surface after the sheet closes.
                        auth.lastAuthError = nil
                    }
                )
                .padding(.top, 22)

                footerZone(c)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .background(c.bg)
        .presentationDetents([.height(473)])
        .presentationCornerRadius(22)
        .presentationDragIndicator(.hidden)
    }

    /// Default state: legal footnote with the orange tappable «условиями».
    /// Loading: same footnote without the link tint (Figma 125:850).
    /// Error: red warning row — the Apple button itself is the retry CTA.
    @ViewBuilder
    private func footerZone(_ c: AppTheme.Colors) -> some View {
        if showError {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                Text(AppStrings.signInErrorRetry(lang.language))
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(AppTheme.red)
            .multilineTextAlignment(.center)
        } else {
            Text(.init(AppStrings.signInLegalMarkdown(
                lang.language,
                termsURL: AppConfig.termsURL(lang.language).absoluteString
            )))
            .font(.system(size: 11))
            .foregroundStyle(c.textTertiary)
            .tint(auth.isAuthenticating ? c.textTertiary : AppTheme.accent)
            .multilineTextAlignment(.center)
        }
    }
}

/// Figma component 114:151: pale outer ring + accent inner ring around the
/// pixel-art car. Sibling of the onboarding Welcome hero (which uses a peach
/// disc fill instead of the translucent accent one — deliberately separate).
fileprivate struct SignInIdleRing: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.accent.opacity(0.25), lineWidth: 2)
                .frame(width: 98, height: 98)
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.18))
                Circle()
                    .stroke(AppTheme.accent, lineWidth: 2.5)
                Image("PixelCar")
                    .resizable()
                    .frame(width: 46, height: 46)
            }
            .frame(width: 82, height: 82)
            .opacity(0.85)
        }
        .frame(width: 100, height: 100)
    }
}
