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
                    welcomePage
                        .tag(0)

                    valuePropPage
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

    // MARK: - Welcome Page (with privacy pill)

    private var welcomePage: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 24) {
            Spacer()

            Image(systemName: "car.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)

            Text(AppStrings.onboardingWelcome(lang.language))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(AppStrings.onboardingWelcomeSub(lang.language))
                .font(.system(size: 16))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                // Long RU subtitles (210-char auto-record copy) otherwise
                // wrap to 9-10 lines on iPhone SE and push buttons under
                // the page-indicator dots. `minimumScaleFactor(0.9)` plus
                // a fixed-size cap keeps the bottom CTA stack visible.
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            // Privacy-first pill — visual reinforcement of the subtitle.
            // Same pattern Signal/Proton use to build trust before permission
            // prompts; sells the differentiator without slowing the flow.
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(AppStrings.onboardingPrivacyPill(lang.language))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.15), in: Capsule())

            Spacer()
            Spacer()
        }
    }

    // MARK: - Value-prop Page (mock trip card)

    /// Replaces the generic "Record your trips" copy page with a visual
    /// preview of what a recorded trip looks like — a mini-map with a
    /// hand-drawn route + stat row. Reading the icon-text-icon-text
    /// pattern of every other onboarding flow tells the user nothing
    /// about the end state. Showing a fake card answers "what do I
    /// get?" in two seconds.
    private var valuePropPage: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 24) {
            Spacer()
            Text(AppStrings.onboardingRecord(lang.language))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            mockTripCard(c)
                .padding(.horizontal, 28)

            Text(AppStrings.onboardingRecordSub(lang.language))
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    /// Hand-drawn "what your recorded trip looks like" card. Pure
    /// SwiftUI — no map tile fetches, no live data. Static SVG-ish
    /// preview keeps the bundle small and the launch fast.
    private func mockTripCard(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return VStack(spacing: 0) {
            // Mock map area with curved route
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [Color(white: 0.16), Color(white: 0.10)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 140)

                // Route stroke
                GeometryReader { geo in
                    Path { p in
                        let w = geo.size.width
                        let h = geo.size.height
                        p.move(to: CGPoint(x: w * 0.15, y: h * 0.75))
                        p.addCurve(
                            to: CGPoint(x: w * 0.85, y: h * 0.25),
                            control1: CGPoint(x: w * 0.30, y: h * 0.20),
                            control2: CGPoint(x: w * 0.55, y: h * 0.85),
                        )
                    }
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: AppTheme.accent.opacity(0.6), radius: 8)

                    // Start + finish dots
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .position(x: geo.size.width * 0.15, y: geo.size.height * 0.75)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .position(x: geo.size.width * 0.85, y: geo.size.height * 0.25)
                }
                .frame(height: 140)
            }

            // Stat strip
            HStack(spacing: 0) {
                mockStat(value: "42", unit: isRu ? "км" : "km", color: AppTheme.green)
                Divider().frame(height: 28).background(c.border)
                mockStat(value: "1:18", unit: "", color: AppTheme.accent)
                Divider().frame(height: 28).background(c.border)
                mockStat(value: "68", unit: isRu ? "км/ч" : "km/h", color: AppTheme.blue)
            }
            .padding(.vertical, 14)
            .background(Color(white: 0.12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(c.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
    }

    private func mockStat(value: String, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(color)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
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
                // Long RU subtitles (210-char auto-record copy) otherwise
                // wrap to 9-10 lines on iPhone SE and push buttons under
                // the page-indicator dots. `minimumScaleFactor(0.9)` plus
                // a fixed-size cap keeps the bottom CTA stack visible.
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
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

                consentText(c)
                    .padding(.top, 4)
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
                // Long RU subtitles (210-char auto-record copy) otherwise
                // wrap to 9-10 lines on iPhone SE and push buttons under
                // the page-indicator dots. `minimumScaleFactor(0.9)` plus
                // a fixed-size cap keeps the bottom CTA stack visible.
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
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
                    // Drop the new user directly onto the Tracking tab — index 1
        // matches `ContentView.selectedTab`. The default 0 (Feed) is
        // empty for a fresh install and gives no clear next action;
        // Tracking shows the slide-to-start affordance immediately.
        UserDefaults.standard.set(1, forKey: "selectedTab")
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
        let text = AppStrings.onboardingConsentMarkdown(
            lang.language,
            termsURL: termsURL,
            privacyURL: privacyURL
        )
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
                // Long RU subtitles (210-char auto-record copy) otherwise
                // wrap to 9-10 lines on iPhone SE and push buttons under
                // the page-indicator dots. `minimumScaleFactor(0.9)` plus
                // a fixed-size cap keeps the bottom CTA stack visible.
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
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

        // Request Notification permission. If granted, also kick off APNs
        // registration so we can receive remote pushes (reactions, follows)
        // once the user signs in. Token sync to server is gated on sign-in
        // inside `PushNotificationManager`.
        NotificationManager.shared.requestAuthorization { granted in
            if granted {
                Task { @MainActor in
                    PushNotificationManager.shared.registerForRemoteNotifications()
                }
            }
        }

        // Enable auto-record by default
        SettingsManager.shared.autoRecordMode = .remind

        // Drop the new user directly onto the Tracking tab — index 1
        // matches `ContentView.selectedTab`. The default 0 (Feed) is
        // empty for a fresh install and gives no clear next action;
        // Tracking shows the slide-to-start affordance immediately.
        UserDefaults.standard.set(1, forKey: "selectedTab")
        hasCompletedOnboarding = true
    }
}
