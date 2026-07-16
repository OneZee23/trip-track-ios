import SwiftUI
import CoreLocation
import CoreMotion

/// 6.1.0 onboarding — 4 pages per the Figma spec (§01 · ОНБОРДИНГ):
/// Welcome (IdleRing hook) → Ценность (mock trip card) → Гео (permission)
/// → Автозапись (Always + Motion + finish). Custom pagination dots replace
/// the system page indicator; hero badges are 96pt accent-tinted circles.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    // Initial page can be pinned via launch argument (-onboardingStartPage N)
    // so UI tests / simulator screenshot runs can open any page directly.
    @State private var currentPage = UserDefaults.standard.integer(forKey: "onboardingStartPage")
    @State private var locationManager: CLLocationManager?

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            c.bg.ignoresSafeArea()

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
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom pagination dots (Figma): inactive 7pt grey circles,
            // active 18×7 accent capsule. Overlaid so every page's own
            // bottom content keeps a stable distance from the dots.
            VStack {
                Spacer()
                paginationDots
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Shared building blocks

    private var paginationDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { page in
                Capsule()
                    .fill(page == currentPage ? AppTheme.accent : Color(red: 155/255, green: 155/255, blue: 165/255).opacity(0.4))
                    .frame(width: page == currentPage ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.25), value: currentPage)
    }

    /// 96pt hero badge: accent-tinted disc with an accent glyph.
    private func heroBadge(@ViewBuilder glyph: () -> some View) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentBg)
                .frame(width: 96, height: 96)
            glyph()
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.top, 63)
    }

    /// Primary CTA per Figma: 56pt tall, radius 14, accent fill with a
    /// subtle accent shadow.
    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppTheme.accent.opacity(0.3), radius: 3, y: 1)
        }
    }

    private func bodyText(_ text: String, _ c: AppTheme.Colors, size: CGFloat = 15) -> some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(c.textSecondary)
            .multilineTextAlignment(.center)
            // Long RU subtitles otherwise wrap to 9-10 lines on iPhone SE
            // and push buttons under the pagination dots.
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32)
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            // IdleRing hero: pale outer ring + 2pt accent ring on a peach
            // disc, pixel car centered (same art the Record screen uses).
            ZStack {
                Circle()
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
                    .frame(width: 100, height: 100)
                Circle()
                    .fill(Color(red: 245/255, green: 228/255, blue: 218/255))
                    .overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
                    .frame(width: 82, height: 82)
                Image("PixelCar")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 46, height: 46)
            }
            .padding(.top, 61)

            VStack(spacing: 2) {
                Text(AppStrings.onboardingWelcomeTitle1(lang.language))
                    .foregroundStyle(c.text)
                Text(AppStrings.onboardingWelcomeTitle2(lang.language))
                    .foregroundStyle(AppTheme.accent)
            }
            .font(.system(size: 24, weight: .heavy))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 47)

            bodyText(AppStrings.onboardingWelcomeSub(lang.language), c)
                .padding(.top, 16)

            // Privacy-first pill — trust builder before any permission
            // prompt (same pattern Signal/Proton use).
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .semibold))
                Text(AppStrings.onboardingPrivacyPill(lang.language))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(AppTheme.green)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(AppTheme.green.opacity(0.15), in: Capsule())
            .padding(.top, 28)

            Spacer()

            Text("TRIP TRACK")
                .font(.custom("PressStart2P-Regular", size: 8))
                .tracking(0.64)
                .foregroundStyle(Color(red: 155/255, green: 155/255, blue: 165/255).opacity(0.5))
                .padding(.bottom, 44)
        }
    }

    // MARK: - Value-prop Page (mock trip card)

    /// Shows what a recorded trip looks like — a static mock card with a
    /// speed-gradient route on a parchment map and a 2×3 metrics grid.
    /// Answers "what do I get?" in two seconds.
    private var valuePropPage: some View {
        let c = AppTheme.colors(for: scheme)
        // ScrollView + basedOnSize: static on tall phones, scrolls only where
        // the ~700pt content stack exceeds the screen (667pt SE class).
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroBadge {
                    // Photo-with-sparkle glyph (Figma node 229:2): memories icon.
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "photo")
                            .font(.system(size: 40, weight: .regular))
                        Image(systemName: "sparkle")
                            .font(.system(size: 14, weight: .semibold))
                            .offset(x: 8, y: -8)
                    }
                }

                Text(AppStrings.onboardingValueTitle(lang.language))
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                mockTripCard(c)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                bodyText(AppStrings.onboardingValueCaption(lang.language), c, size: 14)
                    .padding(.top, 16)
                    .padding(.bottom, 56)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Static "what your recorded trip looks like" card. Pure SwiftUI —
    /// no map tiles, no live data. Deliberately theme-independent (it is a
    /// "screenshot" of the app's light map style).
    private func mockTripCard(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return VStack(spacing: 0) {
            mockMapArea
            mockStatsArea(isRu: isRu)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
    }

    /// Parchment map: faint road curves + speed-gradient route with
    /// start/finish dots, pixel car, auto-recorded glass pill, watermark.
    private var mockMapArea: some View {
        ZStack {
            Color(red: 232/255, green: 225/255, blue: 211/255) // parchment #E8E1D3

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Faint background road network
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.35))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.55),
                               control1: CGPoint(x: w * 0.35, y: h * 0.15),
                               control2: CGPoint(x: w * 0.6, y: h * 0.75))
                    p.move(to: CGPoint(x: w * 0.25, y: 0))
                    p.addCurve(to: CGPoint(x: w * 0.45, y: h),
                               control1: CGPoint(x: w * 0.3, y: h * 0.4),
                               control2: CGPoint(x: w * 0.42, y: h * 0.6))
                }
                .stroke(Color(red: 214/255, green: 205/255, blue: 186/255), lineWidth: 3)

                // Speed-gradient route per Figma canon: line runs green →
                // yellow → red from the bottom-left start to the top-right
                // end (endpoint DOTS carry the opposite colors for contrast).
                Path { p in
                    p.move(to: CGPoint(x: w * 0.11, y: h * 0.83))
                    p.addCurve(to: CGPoint(x: w * 0.72, y: h * 0.11),
                               control1: CGPoint(x: w * 0.38, y: h * 0.95),
                               control2: CGPoint(x: w * 0.45, y: h * 0.18))
                }
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.green, AppTheme.yellow, AppTheme.red],
                        startPoint: .bottomLeading, endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )

                // Endpoint dots: red start (bottom-left), green finish
                // (top-right), both with white rings.
                mockEndpointDot(AppTheme.red)
                    .position(x: w * 0.11, y: h * 0.83)
                mockEndpointDot(AppTheme.green)
                    .position(x: w * 0.72, y: h * 0.11)

                // Pixel car riding the route
                Image("PixelCar")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-24))
                    .position(x: w * 0.5, y: h * 0.3)
            }

            VStack {
                HStack {
                    Text(AppStrings.onboardingRecordedAuto(lang.language))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.72), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Text("TRIP TRACK")
                        .font(.custom("PressStart2P-Regular", size: 7))
                        .tracking(0.56)
                        .foregroundStyle(Color(red: 155/255, green: 155/255, blue: 165/255).opacity(0.55))
                }
            }
            .padding(10)
        }
        .frame(height: 150)
    }

    private func mockEndpointDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    /// White card bottom: trip title + 2×3 metrics grid with hairline
    /// dividers. Values are static mock data (RU uses decimal comma).
    private func mockStatsArea(isRu: Bool) -> some View {
        let l = lang.language
        let metrics: [(icon: String, value: String, unit: String, color: Color, label: String)] = [
            ("point.topleft.down.curvedto.point.bottomright.up", "246", AppStrings.km(l), AppTheme.green, AppStrings.distance(l)),
            ("clock", "2:59", "", AppTheme.accent, AppStrings.duration(l)),
            ("gauge", "82", AppStrings.kmh(l), AppTheme.blue, AppStrings.onboardingStatAvg(l)),
            ("bolt.fill", "150", AppStrings.kmh(l), AppTheme.red, AppStrings.onboardingStatMax(l)),
            ("drop", isRu ? "7,4" : "7.4", AppStrings.unitLPer100(l), AppTheme.yellow, AppStrings.onboardingStatFuel(l)),
            ("mountain.2", "340", AppStrings.unitMeters(l), AppTheme.teal, AppStrings.onboardingStatAltitude(l)),
        ]
        let hairline = Color.black.opacity(0.05)

        return VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.onboardingMockTripTitle(lang.language))
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(Color(red: 30/255, green: 30/255, blue: 35/255))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            VStack(spacing: 0) {
                mockMetricsRow(Array(metrics[0..<3]), hairline: hairline)
                hairline.frame(height: 1)
                    .padding(.horizontal, 13)
                mockMetricsRow(Array(metrics[3..<6]), hairline: hairline)
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private func mockMetricsRow(
        _ row: [(icon: String, value: String, unit: String, color: Color, label: String)],
        hairline: Color
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { index, m in
                if index > 0 {
                    hairline.frame(width: 1, height: 46)
                }
                VStack(spacing: 3) {
                    Image(systemName: m.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 100/255, green: 100/255, blue: 110/255))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(m.value)
                            .font(.system(size: 17, weight: .heavy).monospacedDigit())
                            .foregroundStyle(m.color)
                        if !m.unit.isEmpty {
                            Text(m.unit)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(red: 100/255, green: 100/255, blue: 110/255))
                        }
                    }
                    Text(m.label.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.32)
                        .foregroundStyle(Color(red: 155/255, green: 155/255, blue: 165/255))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Location Permission Page

    private var locationPage: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            heroBadge {
                MapPinGlyph()
                    .frame(width: 44, height: 44)
            }

            Text(AppStrings.onboardingLocation(lang.language))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 49)

            bodyText(AppStrings.onboardingLocationSub(lang.language), c)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 12) {
                primaryButton(AppStrings.onboardingAllow(lang.language)) {
                    requestLocationAndAdvance()
                }

                // Consent stays on this screen too (product decision): the
                // FIRST system permission prompt fires here, so acceptance
                // must be shown before it — Figma shows it only on the last
                // page, which is legally weaker.
                consentText(c)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 56)
        }
    }

    // MARK: - Auto-record Page

    private var autoRecordPage: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            heroBadge {
                // Symmetric Wi-Fi fan opening up with the dot below — matches
                // the Figma broadcast glyph orientation.
                Image(systemName: "wifi")
                    .font(.system(size: 42, weight: .regular))
            }

            Text(AppStrings.onboardingAutoRecord(lang.language))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 49)

            // Copy deliberately keeps the background-location + motion
            // disclosure (user decision) — it primes the Always prompt;
            // the Figma frame carries the shortened version.
            bodyText(AppStrings.onboardingAutoRecordSub(lang.language), c)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 10) {
                primaryButton(AppStrings.onboardingAutoRecordEnable(lang.language)) {
                    enableAutoRecordAndFinish()
                }

                Button {
                    // Drop the new user directly onto the Record tab — the
                    // default Home feed is empty for a fresh install and gives
                    // no clear next action; Record shows the slide-to-start
                    // affordance immediately.
                    UserDefaults.standard.set(AppTab.record.rawValue, forKey: AppTab.storageKey)
                    hasCompletedOnboarding = true
                } label: {
                    Text(AppStrings.onboardingAutoRecordSkip(lang.language))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }

                consentText(c)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 56)
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
            .font(.system(size: 11))
            .foregroundStyle(c.textTertiary)
            .tint(AppTheme.accent)
            .multilineTextAlignment(.center)
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

        // Drop the new user directly onto the Record tab — the default Home
        // feed is empty for a fresh install and gives no clear next action;
        // Record shows the slide-to-start affordance immediately.
        UserDefaults.standard.set(AppTab.record.rawValue, forKey: AppTab.storageKey)
        hasCompletedOnboarding = true
    }
}

/// Filled teardrop map-pin with a white inner dot (Figma's Гео hero glyph —
/// no SF Symbol has this classic silhouette).
fileprivate struct MapPinGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Path { p in
                    // Teardrop: circle head + tapered point at the bottom.
                    let r = w * 0.36
                    let cx = w / 2
                    let cy = r + 1
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                             startAngle: .degrees(150), endAngle: .degrees(30),
                             clockwise: false)
                    p.addQuadCurve(to: CGPoint(x: cx, y: h - 1),
                                   control: CGPoint(x: cx + r * 0.72, y: cy + r * 1.1))
                    p.addQuadCurve(to: CGPoint(x: cx - r * cos(.pi / 6), y: cy + r * sin(.pi / 6)),
                                   control: CGPoint(x: cx - r * 0.72, y: cy + r * 1.1))
                    p.closeSubpath()
                }
                .fill()

                Circle()
                    .fill(.white)
                    .frame(width: w * 0.26, height: w * 0.26)
                    .position(x: w / 2, y: w * 0.36 + 1)
            }
        }
    }
}
