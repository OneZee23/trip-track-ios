import SwiftUI
import CoreLocation
import CoreMotion

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

                    // Location permission page
                    locationPage
                        .tag(2)

                    // Auto-record page (Always location + Motion)
                    autoRecordPage
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
    }

    // MARK: - Location Permission Page

    private var locationPage: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 24) {
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
                requestLocationAndAdvance()
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
    }

    // MARK: - Auto-record Page

    private var autoRecordPage: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)

            Text(AppStrings.onboardingAutoRecord(lang.language))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(AppStrings.onboardingAutoRecordSub(lang.language))
                .font(.system(size: 16))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    enableAutoRecordAndFinish()
                } label: {
                    Text(AppStrings.onboardingAutoRecordEnable(lang.language))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    hasCompletedOnboarding = true
                } label: {
                    Text(AppStrings.onboardingAutoRecordSkip(lang.language))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }

                consentText(c)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Consent Text (Terms + Privacy links)

    private func consentText(_ c: AppTheme.Colors) -> some View {
        let termsURL = AppConfig.termsURL(lang.language).absoluteString
        let privacyURL = AppConfig.privacyPolicyURL(lang.language).absoluteString
        let text = "\(AppStrings.onboardingConsent(lang.language)) [\(AppStrings.termsOfService(lang.language))](\(termsURL)) \(AppStrings.and(lang.language)) [\(AppStrings.privacyPolicy(lang.language))](\(privacyURL))"
        return Text(.init(text))
            .font(.system(size: 12))
            .foregroundStyle(c.textTertiary)
            .tint(AppTheme.accent)
            .multilineTextAlignment(.center)
    }

    // MARK: - Reusable Page Template

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

    // MARK: - Actions

    private func requestLocationAndAdvance() {
        let manager = CLLocationManager()
        locationManager = manager
        manager.requestWhenInUseAuthorization()
        withAnimation { currentPage = 3 }
    }

    private func enableAutoRecordAndFinish() {
        // Request Always location (escalates from While Using)
        let manager = locationManager ?? CLLocationManager()
        locationManager = manager
        manager.requestAlwaysAuthorization()

        // Request Motion permission
        MotionDetector.requestAuthorization { _ in }

        // Request Notification permission
        NotificationManager.shared.requestAuthorization { _ in }

        // Enable auto-record by default
        SettingsManager.shared.autoRecordMode = .remind

        hasCompletedOnboarding = true
    }
}
