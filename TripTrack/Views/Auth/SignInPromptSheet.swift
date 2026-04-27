import SwiftUI
import AuthenticationServices

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
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

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

                SignInWithAppleButton(.signIn,
                    onRequest: { req in req.requestedScopes = [.fullName, .email] },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            Task {
                                await auth.handleAuthorization(authorization)
                                if auth.isSignedIn { dismiss() }
                            }
                        case .failure:
                            break
                        }
                    })
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .padding(.horizontal, 24)

                Button(isRu ? "Не сейчас" : "Maybe later") {
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
                   text: isRu ? "Синхронизация на всех Ваших устройствах" : "Sync across your devices",
                   c: c)
            bullet(icon: "heart.fill", color: .red,
                   text: isRu ? "Реакции и подписки" : "React and follow people",
                   c: c)
            bullet(icon: "square.and.arrow.up", color: AppTheme.accent,
                   text: isRu ? "Публикация поездок и шеринг" : "Publish your trips and share",
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
        }
    }
}
