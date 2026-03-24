import SwiftUI
import CoreLocation

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @State private var currentPage = 0
    @State private var locationManager: CLLocationManager?

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            c.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    onboardingPage(
                        icon: "car.fill",
                        title: AppStrings.onboardingWelcome(lang.language),
                        subtitle: AppStrings.onboardingWelcomeSub(lang.language)
                    )
                    .tag(0)

                    onboardingPage(
                        icon: "location.fill",
                        title: AppStrings.onboardingRecord(lang.language),
                        subtitle: AppStrings.onboardingRecordSub(lang.language)
                    )
                    .tag(1)

                    // Final page with CTA — location permission
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 64))
                            .foregroundStyle(AppTheme.accent)

                        Text(AppStrings.onboardingLocation(lang.language))
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(c.text)
                            .multilineTextAlignment(.center)

                        Text(AppStrings.onboardingLocationSub(lang.language))
                            .font(.system(size: 16))
                            .foregroundStyle(c.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Spacer()

                        Button {
                            completeOnboarding()
                        } label: {
                            Text(AppStrings.onboardingGo(lang.language))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 48)
                    }
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
    }

    private func onboardingPage(icon: String, title: String, subtitle: String) -> some View {
        let c = AppTheme.colors(for: scheme)

        return VStack(spacing: 24) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)

            Text(title)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private func completeOnboarding() {
        // Request location permission — keep manager alive in @State so iOS shows the dialog
        let manager = CLLocationManager()
        locationManager = manager
        manager.requestWhenInUseAuthorization()

        // Flag for demo trip creation when ContentView loads
        UserDefaults.standard.set(true, forKey: "needsDemoTrip")
        hasCompletedOnboarding = true
    }
}
