import SwiftUI

extension Notification.Name {
    static let switchToFeedWithRegionFilter = Notification.Name("switchToFeedWithRegionFilter")
    static let switchToFeedTab = Notification.Name("switchToFeedTab")
    static let feedScrollToTop = Notification.Name("feedScrollToTop")
    static let switchToTrackingTab = Notification.Name("switchToTrackingTab")
    static let openTripDetail = Notification.Name("openTripDetail")
    static let navigateToTrip = Notification.Name("navigateToTrip")
    static let dismissTripSummary = Notification.Name("dismissTripSummary")
    static let tripDeleted = Notification.Name("tripDeleted")
    static let tripRecordingEnded = Notification.Name("tripRecordingEnded")
    static let territoryRebuilt = Notification.Name("territoryRebuilt")
    static let syncPullCompleted = Notification.Name("syncPullCompleted")
    static let tripPrivacyChanged = Notification.Name("tripPrivacyChanged")
    /// Photo added or removed from a trip. Feed listens so the card's photo
    /// indicator refreshes without forcing a pull-to-refresh.
    static let tripPhotosChanged = Notification.Name("tripPhotosChanged")
    /// Server returned `USER_BANNED` on any authenticated endpoint. AuthService
    /// observes this and triggers `signOut()` — local data stays intact so the
    /// user can still view (read-only) what they already have on device.
    static let userBanned = Notification.Name("userBanned")
    /// AutoTrip recovery rewound the active trip's start to a real motion
    /// onset N minutes ago. MapViewModel observes so its `recordingStartDate`
    /// + duration timer match. Object is the new `Date`.
    static let tripStartDateBackdated = Notification.Name("tripStartDateBackdated")
    /// Location authorization flipped. Object is `Bool` — true when denied or
    /// restricted. Posted by RealGPSProvider; MapViewModel mirrors it into
    /// `locationDenied` for the Record screen.
    static let locationAuthDenied = Notification.Name("locationAuthDenied")
    /// Open the Garage: switches to the Я tab (ContentView) where ProfileView
    /// presents the Garage sheet. Posted by VehiclePickerSheet's footer.
    static let openGarage = Notification.Name("openGarage")
    /// Second phase of `.openGarage`, re-posted by ContentView after the tab
    /// switch so a freshly-mounted ProfileView actually receives it.
    static let openGarageReady = Notification.Name("openGarageReady")
}

/// Payload for `.tripPrivacyChanged` — lets the feed optimistically remove/add the
/// affected card instead of waiting for the server round-trip.
struct PrivacyChangePayload {
    let tripId: UUID
    let isPrivate: Bool
}

/// Preference carrying whether the currently-presented leaf view wants the
/// bottom CustomTabBar hidden (trip-detail screens want the bigger canvas).
/// Using a PreferenceKey keeps tab-bar control local to the view hierarchy
/// instead of threading bindings through every intermediate container.
struct HideTabBarPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        // Any descendant requesting "hide" wins — detail screens want it gone.
        value = value || nextValue()
    }
}

extension View {
    /// Signal to the root container that this view (and while it's on-screen)
    /// prefers the CustomTabBar to be hidden. Use with `.onPreferenceChange`
    /// on the container or let `ContentView` handle it via its existing wiring.
    func hideAppTabBar(_ hide: Bool = true) -> some View {
        preference(key: HideTabBarPreferenceKey.self, value: hide)
    }
}

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    /// Selected tab is `@AppStorage`-backed so onboarding can hand the
    /// user directly into the Record tab — landing on the empty feed
    /// after a fresh install gives no obvious next step, whereas Record
    /// shows the slide-to-start affordance.
    @AppStorage(AppTab.storageKey) private var selectedTab: AppTab = .home
    @State private var hideTabBar = false
    @Environment(\.colorScheme) private var systemScheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: systemScheme)
        return ZStack(alignment: .bottom) {
            // Paint the theme background across the entire window, including
            // below the bottom safe area. Previously the feed's own black bg
            // only extended to the safe-area edge, so the strip around the
            // home indicator fell through to the system window color and
            // read as an out-of-place slab on devices with a chin (iPhone
            // 12, etc.). Painting bg here keeps the screen visually whole.
            c.bg.ignoresSafeArea()

            switch selectedTab {
            case .home:
                FeedView(tripManager: mapVM.tripManager, selectedTab: $selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .maps:
                MyMapView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .record:
                TrackingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.colorScheme, mapVM.isDarkMap ? .dark : systemScheme)
            case .groups:
                GroupsComingSoonView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .profile:
                ProfileView(hostedInTab: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Custom glass tab bar — hidden on Record tab, and also while any
            // descendant trip-detail view declared `.hideAppTabBar()`.
            if selectedTab != .record && !hideTabBar {
                CustomTabBar(selectedTab: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(HideTabBarPreferenceKey.self) { newValue in
            // No-op when the value didn't actually change — without this
            // guard, the preference write fires every body pass even when
            // the descendant's reported value is identical, producing the
            // 3× `AttributeGraph: cycle detected` at cold launch (one per
            // nested view boundary: ContentView → NavStack → FeedView).
            guard newValue != hideTabBar else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                hideTabBar = newValue
            }
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(edges: .bottom)
        .environmentObject(mapVM)
        // Force-quit recovery prompt — presented from the root so it fires on
        // launch regardless of the active tab (Figma 505:119).
        .sheet(isPresented: $mapVM.showRecoveryPrompt) {
            RecoveryPromptSheet()
                .environmentObject(mapVM)
                .environmentObject(lang)
        }
        // Trip summary — root-level for the same reason: «Завершить и
        // сохранить» in the recovery prompt finishes a trip from ANY tab;
        // TrackingView only exists while .record is selected.
        .sheet(item: $mapVM.lastCompletedTrip) { trip in
            TripCompleteSummaryView(
                trip: trip,
                completionData: mapVM.lastCompletionData,
                onPhotoSaved: { image in
                    _ = mapVM.tripManager.addPhoto(to: trip.id, image: image)
                },
                onDone: { dismissSummary() }
            )
            .environmentObject(lang)
            .environmentObject(mapVM)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $mapVM.showBadgeCelebration) {
            BadgeCelebrationView(
                badges: mapVM.pendingBadges,
                onDismiss: {
                    mapVM.pendingBadges = []
                    mapVM.showBadgeCelebration = false
                    // Show trip summary after celebration (if there's a pending trip)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        mapVM.showPendingSummary()
                    }
                }
            )
            .environmentObject(lang)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToFeedWithRegionFilter)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = .home
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToFeedTab)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = .home
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTrackingTab)) { _ in
            selectedTab = .record
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGarage)) { _ in
            // Two-phase: switch the tab, then re-post once ProfileView has
            // mounted its listener — a one-shot notification consumed before
            // the view exists would be lost (same pattern as .openTripDetail).
            selectedTab = .profile
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                NotificationCenter.default.post(name: .openGarageReady, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTripDetail)) { notification in
            if let tripId = notification.object as? UUID {
                // Switch to feed tab and navigate to trip detail
                selectedTab = .home
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    NotificationCenter.default.post(name: .navigateToTrip, object: tripId)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissTripSummary)) { _ in
            // Dismiss any showing summary/celebration when deep-linking to trip detail
            mapVM.lastCompletedTrip = nil
            mapVM.showBadgeCelebration = false
            mapVM.pendingBadges = []
        }
        .onAppear {
            StartupTrace.mark("ContentView ready (tab=\(selectedTab.rawValue))")
            // Clean up demo trip for users who onboarded before 0.1.1
            mapVM.tripManager.deleteDemoTripIfNeeded()
            // Configure auto-trip detection
            AutoTripService.shared.configure(mapViewModel: mapVM)
            AutoTripService.shared.startIfNeeded()
        }
    }

    private func dismissSummary() {
        mapVM.lastCompletedTrip = nil
        // Post-completion is the right emotional moment to ask for a
        // rating — the user just finished a trip, sees their stats,
        // and dismisses with a sense of accomplishment. Delay so the
        // sheet dismiss animation lands before the system prompt
        // pops up (otherwise they overlap on iOS 17+). All guards
        // (trip count, launch count, cooldown) live inside the
        // service — this call is a fire-and-forget hint.
        let tripCount = mapVM.tripManager.fetchTripCount()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            RatingPromptService.requestReviewIfReady(tripCount: tripCount)
        }
    }
}

#Preview {
    ContentView()
}
