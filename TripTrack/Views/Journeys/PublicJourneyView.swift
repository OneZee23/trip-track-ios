import SwiftUI

/// Чужое публичное путешествие (0.6.8, S6) — загрузчик поверх `JourneyDetailView`.
///
/// Экран сам не рисует ничего, кроме состояния загрузки и заглушки: как
/// только `POST /social/journey` отвечает, всё содержимое рисует
/// `JourneyDetailView(social:pushPath:)` — тот же экран, что и для своего
/// путешествия, просто с другими данными и без прав на правку. Один ответ
/// (скрыли, удалили, запрос не прошёл) — одна заглушка: различать причины
/// незачем, а угадывать их означало бы иногда подтверждать существование
/// того, что владелец спрятал (см. `PublicVehicleView.unavailable`).
struct PublicJourneyView: View {
    let journeyId: UUID
    var pushPath: Binding<[ProfilePreviewDest]>?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var response: SocialJourneyResponse?
    @State private var failed = false

    private var colors: AppTheme.Colors { AppTheme.colors(for: scheme) }

    var body: some View {
        Group {
            if let response {
                JourneyDetailView(social: response, pushPath: pushPath)
            } else if failed {
                unavailable
            } else {
                ZStack {
                    colors.bg.ignoresSafeArea()
                    ProgressView()
                }
            }
        }
        .background(NavBarKiller())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: journeyId) { await load() }
        .accessibilityIdentifier("public_journey")
    }

    private var unavailable: some View {
        VStack(spacing: 18) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.text)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(AppStrings.back(lang.language))
                .accessibilityIdentifier("public_journey_back")
                Spacer()
            }
            .padding(.horizontal, 4)
            Spacer()
            Text(AppStrings.journeyUnavailable(lang.language))
                .font(.system(size: 13))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            Spacer()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.bg.ignoresSafeArea())
    }

    private func load() async {
        failed = false
        do {
            // Как у `PublicVehicleView`/`PublicProfileView`: гость читает
            // чужое публичное путешествие тоже, `requiresAuth` не заставляет
            // его входить.
            let res: SocialJourneyResponse = try await APIClient.shared.post(
                APIEndpoint.socialJourney,
                body: SocialJourneyRequest(journeyId: journeyId),
                requiresAuth: AuthService.shared.isSignedIn)
            response = res
        } catch {
            response = nil
            failed = true
        }
    }
}
