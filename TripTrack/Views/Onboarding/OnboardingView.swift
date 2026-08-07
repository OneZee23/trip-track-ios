import SwiftUI
import CoreLocation
import UserNotifications
import CoreMotion

/// 6.1.0 onboarding — 5 pages per the Figma spec (§01 · ОНБОРДИНГ):
/// Welcome (IdleRing hook) → Ценность (trip card, real trip when there is
/// one) → Гео «При использовании» → Гео «Всегда» + motion → Уведомления.
/// One permission per screen, each with a way past it: asking for three at
/// once (what the old bundled page did) trades a permanent "Don't Allow" for
/// a moment of convenience. Custom pagination dots replace
/// the system page indicator; hero badges are 96pt accent-tinted circles.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var lang: LanguageManager
    /// Newest recorded trip, when there is one. The demo card then shows a
    /// REAL drive instead of a drawn squiggle — on a re-run of the
    /// onboarding, or for anyone who recorded before signing in, seeing
    /// their own route here is the whole promise made concrete.
    @State private var realTrip: Trip?
    /// Live authorization state, re-read whenever a page appears so a
    /// permission granted in the system prompt updates this screen.
    @State private var permissionStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus
    /// Notifications already allowed (re-run of onboarding, or granted from
    /// a system prompt earlier). Same reasoning as the location pages: iOS
    /// only ever shows its prompt once, so a button that "asks" again would
    /// silently do nothing.
    @State private var notificationsGranted = false
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

                // Background location («Всегда») + motion
                autoRecordPage
                    .tag(3)

                // Notifications — its own ask (canon), and the last page
                notificationsPage
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Re-read authorization on every page change and when the app
            // comes back from the system prompt: a permission granted in
            // that alert must be reflected here without a relaunch.
            .onChange(of: currentPage) { _, _ in refreshPermissionStatus() }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )) { _ in refreshPermissionStatus() }

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
            ForEach(0..<5, id: \.self) { page in
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
                    .task { loadRealTrip() }

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
    /// Pulls the newest trip that actually has a route to draw.
    ///
    /// Goes straight to the repository rather than through `TripManager`:
    /// onboarding runs BEFORE `ContentView`, so there is no MapViewModel (and
    /// therefore no TripManager) in this environment, and spinning one up
    /// here would start the location plumbing for a card.
    private func loadRealTrip() {
        let repo = CoreDataTripRepository(persistenceController: .shared)
        let candidates = repo.fetchTrips(limit: 10, offset: 0)
        realTrip = candidates.first { $0.previewCoordinates.count > 1 }
    }

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

                if let realTrip, realTrip.previewCoordinates.count > 1 {
                    // The user's own most recent drive, drawn with the same
                    // projection + gradient the share poster uses.
                    let pts = SharePosterView.project(
                        realTrip.previewCoordinates,
                        in: CGSize(width: w, height: h),
                        inset: 18
                    )
                    SharePosterRoute(points: pts, lineWidth: 4)
                    if pts.count > 1 {
                        let mid = pts[pts.count / 2]
                        Image("PixelCar")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .position(mid)
                    }
                } else {
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

    /// «Поездка · 16 мая» with the real date when a real trip backs the card.
    private var realTripTitle: String? {
        guard let realTrip else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: lang.language == .ru ? "ru_RU" : "en_US")
        df.setLocalizedDateFormatFromTemplate("d MMMM")
        let prefix = lang.language == .ru ? "Поездка" : "Trip"
        return "\(prefix) · \(df.string(from: realTrip.startDate))"
    }

    /// RU writes decimals with a comma; the canned values already did, so the
    /// real ones must too or the card changes typography mid-flow.
    private static func number(_ value: Double, decimals: Int, isRu: Bool) -> String {
        let s = String(format: "%.\(decimals)f", value)
        return isRu ? s.replacingOccurrences(of: ".", with: ",") : s
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
        // Real numbers whenever there's a real trip behind the card; the
        // canned set only fills in for a first-ever launch, where there is
        // genuinely nothing to show.
        let metrics: [(icon: String, value: String, unit: String, color: Color, label: String)] =
            realTrip.map { trip in
                let fuel = trip.distanceKm > 0 ? trip.fuelUsed / trip.distanceKm * 100 : 0
                return [
                    ("point.topleft.down.curvedto.point.bottomright.up",
                     Self.number(trip.distanceKm, decimals: trip.distanceKm < 100 ? 1 : 0, isRu: isRu),
                     AppStrings.km(l), AppTheme.green, AppStrings.distance(l)),
                    ("clock", trip.formattedDuration, "", AppTheme.accent, AppStrings.duration(l)),
                    ("gauge", Self.number(trip.averageSpeedKmh, decimals: 0, isRu: isRu),
                     AppStrings.kmh(l), AppTheme.blue, AppStrings.onboardingStatAvg(l)),
                    ("bolt.fill", Self.number(trip.maxSpeedKmh, decimals: 0, isRu: isRu),
                     AppStrings.kmh(l), AppTheme.red, AppStrings.onboardingStatMax(l)),
                    ("drop", Self.number(fuel, decimals: 1, isRu: isRu),
                     AppStrings.unitLPer100(l), AppTheme.yellow, AppStrings.onboardingStatFuel(l)),
                    ("mountain.2", Self.number(trip.elevation, decimals: 0, isRu: isRu),
                     AppStrings.unitMeters(l), AppTheme.teal, AppStrings.onboardingStatAltitude(l)),
                ]
            } ?? [
            ("point.topleft.down.curvedto.point.bottomright.up", "246", AppStrings.km(l), AppTheme.green, AppStrings.distance(l)),
            ("clock", "2:59", "", AppTheme.accent, AppStrings.duration(l)),
            ("gauge", "82", AppStrings.kmh(l), AppTheme.blue, AppStrings.onboardingStatAvg(l)),
            ("bolt.fill", "150", AppStrings.kmh(l), AppTheme.red, AppStrings.onboardingStatMax(l)),
            ("drop", isRu ? "7,4" : "7.4", AppStrings.unitLPer100(l), AppTheme.yellow, AppStrings.onboardingStatFuel(l)),
            ("mountain.2", "340", AppStrings.unitMeters(l), AppTheme.teal, AppStrings.onboardingStatAltitude(l)),
        ]
        let hairline = Color.black.opacity(0.05)

        return VStack(alignment: .leading, spacing: 8) {
            Text(realTripTitle ?? AppStrings.onboardingMockTripTitle(lang.language))
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
                if hasLocationPermission {
                    // Already granted (re-run of onboarding, or the user
                    // allowed it from a system prompt earlier): asking again
                    // is a no-op in iOS, so the screen states the fact and
                    // the button just moves forward.
                    Text(AppStrings.onboardingAlreadyGranted(lang.language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.green)

                    primaryButton(AppStrings.onboardingContinue(lang.language)) {
                        withAnimation { currentPage = 3 }
                    }
                } else {
                    primaryButton(AppStrings.onboardingAllow(lang.language)) {
                        requestLocationAndAdvance()
                    }

                    // Nothing has to be granted here. Recording asks for what
                    // it needs at the moment it needs it, and forcing the
                    // decision before the app has shown anything is the
                    // fastest way to get a "Don't Allow" you can never undo.
                    Button {
                        Haptics.tap()
                        withAnimation { currentPage = 3 }
                    } label: {
                        Text(AppStrings.onboardingSkipForNow(lang.language))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(c.textSecondary)
                    }
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

            Text(AppStrings.onboardingBackgroundTitle(lang.language))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 49)

            // Canon copy: says exactly what breaks with «While Using», which
            // is the only argument that makes «Always» reasonable to grant.
            bodyText(AppStrings.onboardingBackgroundSub(lang.language), c)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 10) {
                if hasAlwaysPermission {
                    Text(AppStrings.onboardingAlreadyGranted(lang.language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.green)
                }

                primaryButton(
                    hasAlwaysPermission
                        ? AppStrings.onboardingContinue(lang.language)
                        : AppStrings.onboardingBackgroundAllow(lang.language)
                ) {
                    requestAlwaysAndAdvance()
                }

                Button {
                    Haptics.tap()
                    withAnimation { currentPage = 4 }
                } label: {
                    Text(AppStrings.onboardingSkipForNow(lang.language))
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

    // MARK: - Notifications Page (canon «Уведомления»)

    private var notificationsPage: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            heroBadge {
                Image(systemName: "bell.fill")
                    .font(.system(size: 38, weight: .regular))
            }

            Text(AppStrings.onboardingNotificationsTitle(lang.language))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 49)

            bodyText(AppStrings.onboardingNotificationsSub(lang.language), c)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 10) {
                if notificationsGranted {
                    Text(AppStrings.onboardingAlreadyGranted(lang.language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.green)

                    primaryButton(AppStrings.onboardingContinue(lang.language)) {
                        finishOnboarding()
                    }
                } else {
                    primaryButton(AppStrings.onboardingNotificationsEnable(lang.language)) {
                        requestNotificationsAndFinish()
                    }

                    Button {
                        Haptics.tap()
                        finishOnboarding()
                    } label: {
                        Text(AppStrings.onboardingNotNow(lang.language))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(c.textSecondary)
                    }
                }

                consentText(c)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 56)
        }
    }

    // MARK: - Consent Text (Terms + Privacy links)

    /// DOCUMENTED DEVIATION from Figma (nodes 1994:1982 / 195:1224): the
    /// caption copy here names both documents with tappable links and an
    /// explicit acceptance verb, unlike the shorter Figma caption. This is a
    /// deliberate legal improvement — do not revert to the Figma wording.
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

    private func refreshPermissionStatus() {
        permissionStatus = (locationManager ?? CLLocationManager()).authorizationStatus
        // Notification status is async-only; ask the system rather than
        // trusting a cached flag, since it can change in Settings while the
        // onboarding is on screen.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            Task { @MainActor in notificationsGranted = granted }
        }
    }

    // MARK: - Permission state

    /// Location is granted at any level (While Using or Always).
    private var hasLocationPermission: Bool {
        switch permissionStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Background recording specifically — «Always» is what auto-record needs.
    private var hasAlwaysPermission: Bool { permissionStatus == .authorizedAlways }

    // MARK: - Actions

    private func requestLocationAndAdvance() {
        let manager = CLLocationManager()
        locationManager = manager
        manager.requestWhenInUseAuthorization()
        withAnimation { currentPage = 3 }
    }

    /// «Всегда» + motion, then on to the notifications page. Motion rides
    /// along here because auto-start needs both — asking for it on a screen
    /// of its own would be a permission prompt with nothing to explain.
    private func requestAlwaysAndAdvance() {
        // The system prompt outlives this view's state, and iOS cancels a
        // pending prompt when its CLLocationManager deallocates — the
        // retainer holds it until authorization resolves. (Same invariant
        // documented in AutoRecordSettingsView.)
        let manager = locationManager ?? CLLocationManager()
        locationManager = manager
        AlwaysAuthorizationRetainer.requestAlwaysAuthorization(retaining: manager)
        MotionDetector.requestAuthorization { _ in }
        withAnimation { currentPage = 4 }
    }

    private func requestNotificationsAndFinish() {
        NotificationManager.shared.requestAuthorization { granted in
            if granted {
                Task { @MainActor in
                    PushNotificationManager.shared.registerForRemoteNotifications()
                }
            }
            Task { @MainActor in finishOnboarding() }
        }
    }

    private func finishOnboarding() {
        // Feed is home: it has other people's trips from the very first
        // launch, and recording starts by itself anyway.
        UserDefaults.standard.set(AppTab.home.rawValue, forKey: AppTab.storageKey)
        hasCompletedOnboarding = true
    }
}

/// Keeps the CLLocationManager of the final Always-authorization request
/// alive after OnboardingView is torn down.
///
/// `enableAutoRecordAndFinish()` flips `hasCompletedOnboarding` in the same
/// update cycle as `requestAlwaysAuthorization()`, destroying the view and
/// its `@State` manager — and iOS cancels a pending authorization prompt
/// when its CLLocationManager deallocates ("Must retain CLLocationManager
/// until dialog completes", AutoRecordSettingsView). There the view outlives
/// the prompt; here it cannot by design, so a static strong reference roots
/// the manager (plus this delegate) until the flow resolves, then releases
/// both.
private final class AlwaysAuthorizationRetainer: NSObject, CLLocationManagerDelegate {
    /// Strong root that keeps the retainer + manager alive past the view's
    /// deallocation. Cleared once authorization resolves.
    private static var active: AlwaysAuthorizationRetainer?

    private let manager: CLLocationManager
    /// Core Location delivers one initial callback right after the delegate
    /// is assigned; it reports the CURRENT status, not the user's answer.
    private var receivedInitialStatusCallback = false

    static func requestAlwaysAuthorization(retaining manager: CLLocationManager) {
        let retainer = AlwaysAuthorizationRetainer(manager: manager)
        active = retainer // replaces (and releases) any earlier request
        manager.delegate = retainer
        manager.requestAlwaysAuthorization()
    }

    private init(manager: CLLocationManager) {
        self.manager = manager
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        defer { receivedInitialStatusCallback = true }
        switch manager.authorizationStatus {
        case .notDetermined:
            // Full prompt pending (user swiped past the Geo page without
            // granting While-Using) — keep holding.
            break
        case .authorizedWhenInUse where !receivedInitialStatusCallback:
            // Initial status report while the Always-upgrade prompt is
            // pending — keep holding until the user answers it.
            break
        default:
            // Resolved: .authorizedAlways / .denied / .restricted, or a
            // post-prompt .authorizedWhenInUse ("Keep Only While Using").
            release()
        }
    }

    private func release() {
        manager.delegate = nil
        if Self.active === self { Self.active = nil }
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
