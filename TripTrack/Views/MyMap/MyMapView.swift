import SwiftUI
import MapKit

/// 0.6.0 «Моя карта» — the living map of everywhere you have driven (Figma
/// page «🧭 Карта», canon note «карта v2 · Polarsteps-модель»).
///
/// One flat MapKit map, free pan and zoom, everything on it tappable, and a
/// permanent sheet that swaps its contents to whatever you touched. There is
/// no layer switcher on purpose — the note says «слоёв-переключателей нет»,
/// and depth comes from how close you are instead.
struct MyMapView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    // Singleton by design — survives tab switches (see MyMapViewModel.shared).
    @ObservedObject private var vm = MyMapViewModel.shared
    @State private var zoomLevel: MapZoomLevel = .far
    /// Wrapper rather than a retroactive `UUID: Identifiable` conformance —
    /// that one would leak app-wide from a map file.
    private struct OpenedTrip: Identifiable { let id: UUID }
    @State private var openedTrip: OpenedTrip?
    /// Lives here, not in the sheet, so the tab bar can hide under the
    /// pulled-up region list too.
    @State private var isSummaryExpanded = false
    @State private var showBetaNote = false

    /// «Есть туман или нет» is not a question a screenshot can settle by eye —
    /// a night map is dark either way. `-no-fog-veil` draws the same map
    /// without it so a test can measure the difference in luminance.
    #if DEBUG
    static let showsVeil = !ProcessInfo.processInfo.arguments.contains("-no-fog-veil")
    #else
    static let showsVeil = true
    #endif

    var body: some View {
        ZStack {
            MyMapRepresentable(
                exploration: vm.exploration,
                fog: vm.fogOverlay,
                veil: Self.showsVeil ? vm.fogVeil : nil,
                selectedRoute: vm.selectedRoute,
                selection: vm.selection,
                highlightedRegionId: vm.highlightedRegionId,
                language: lang.language,
                onZoomLevelChange: { zoomLevel = $0 },
                onSelectTrip: { vm.select(.trip($0)) },
                onSelectRoad: { vm.selectRoad($0) },
                // Auto-zoom to the region only from the country view, where
                // that IS the gesture. Down at street level a tap that misses
                // the road is a miss, and answering it by flinging the camera
                // out to the whole krai loses your place.
                onTapMap: { vm.selectRegion(at: $0, zoom: zoomLevel == .far) },
                cameraCommand: $vm.cameraCommand
            )
            .ignoresSafeArea()

            topScrim

            title

            if vm.isEmpty {
                emptyState
            }

            if vm.isLoading {
                CarLoadingView()
            }

            MyMapSheet(
                vm: vm,
                isSummaryExpanded: $isSummaryExpanded,
                onOpenTrip: { openedTrip = OpenedTrip(id: $0) },
                onShare: shareSummary
            )
        }
        // Canon frames 2–5 have no tab bar: a selected card owns the bottom
        // of the screen, and the bar sitting on top of it clipped the
        // progress row clean off.
        .hideAppTabBar(vm.selection != nil || isSummaryExpanded)
        .task {
            await vm.loadIfNeeded(tripManager: mapVM.tripManager, territory: mapVM.territoryManager)
        }
        // House dialog, never the system's (CLAUDE.md «Dialogs»). «ОК» is the
        // way out, so it rides the component's own cancel row; «Сообщить»
        // leaves the app for Telegram, which is why the component dismissing
        // itself first matters here.
        .appConfirm(
            isPresented: $showBetaNote,
            title: AppStrings.mapBetaTitle(lang.language),
            message: AppStrings.mapBetaBody(lang.language),
            actions: [
                AppDialogAction(AppStrings.mapBetaReport(lang.language)) {
                    if let url = URL(string: "https://t.me/onezee_co") {
                        UIApplication.shared.open(url)
                    }
                }
            ],
            cancelTitle: AppStrings.ok(lang.language)
        )
        .fullScreenCover(item: $openedTrip) { opened in
            NavigationStack {
                TripDetailView(
                    tripId: opened.id,
                    viewModel: TripsViewModel(tripManager: mapVM.tripManager)
                )
            }
        }
    }

    // MARK: - Chrome

    /// Status-bar legibility scrim: 110pt black@0.6 → clear.
    private var topScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 110)
            .ignoresSafeArea(edges: .top)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var title: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(AppStrings.myMapTitle(lang.language))
                    .font(.inter(22, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 1)

                // The map ships ahead of the rest of the app. Saying so where
                // it lives — rather than nowhere — is the difference between
                // «это баг?» and a bug report.
                Button {
                    Haptics.tap()
                    showBetaNote = true
                } label: {
                    Text(AppStrings.mapBetaBadge(lang.language))
                        .font(.inter(10, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map_beta_badge")
                .accessibilityLabel(AppStrings.mapBetaTitle(lang.language))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            Spacer()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            EmptyStateIllustration(name: "empty_map", size: 148)
            Text(AppStrings.emptyMapTitle(lang.language))
                .font(.inter(18, weight: .heavy))
                .foregroundStyle(.white)
            Text(AppStrings.emptyMapSubtitle(lang.language))
                .font(.inter(13))
                .foregroundStyle(Color(red: 178/255, green: 178/255, blue: 189/255))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 280)
        .allowsHitTesting(false)
    }

    // MARK: - Share

    /// Canon puts a share button on the collapsed summary. It passes on the
    /// one line the summary already states — the numbers, not a rendered
    /// poster of the map (that lives on the trip share screen).
    private func shareSummary() {
        let text = AppStrings.mapSummary(
            lang.language,
            regions: vm.exploration.regionCount,
            km: Int(vm.exploration.totalKm.rounded()),
            trips: vm.exploration.tripCount
        )
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        var controller = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        while let presented = controller?.presentedViewController { controller = presented }
        controller?.present(activity, animated: true)
    }
}

/// Figma empty-state zigzag: M1.5 21.5 L16.5 4.5 L33.5 15.5 L49.5 1.5 in a
/// 51×23 box, scaled to the frame.
struct ZigzagTrailIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 51.0, sy = rect.height / 23.0
        var p = Path()
        p.move(to: CGPoint(x: 1.5 * sx, y: 21.5 * sy))
        p.addLine(to: CGPoint(x: 16.5 * sx, y: 4.5 * sy))
        p.addLine(to: CGPoint(x: 33.5 * sx, y: 15.5 * sy))
        p.addLine(to: CGPoint(x: 49.5 * sx, y: 1.5 * sy))
        return p
    }
}
