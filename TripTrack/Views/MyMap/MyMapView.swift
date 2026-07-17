import SwiftUI
import MapKit

/// 6.1.0 «Моя карта» — the unified memory map under the Maps tab (Figma
/// section 04). Replaces the fog-of-war RegionsView. Night map with amber
/// territory glow + speed-gradient routes, floating chrome (title, dark-glass
/// segment, expand button), and a zoom-morphing stats plate.
struct MyMapView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    // Singleton by design — survives tab switches (see MyMapViewModel.shared).
    @ObservedObject private var vm = MyMapViewModel.shared
    @State private var mode: MyMapMode = .all
    @State private var showFullscreen = false
    @State private var cameraRegion: MKCoordinateRegion?
    /// Camera returned from the fullscreen cover, applied once by the main
    /// map (distinct from `cameraRegion`, which tracks the map's own state).
    @State private var handoffRegion: MKCoordinateRegion?

    var body: some View {
        ZStack {
            MyMapRepresentable(
                glow: vm.glow,
                routeSegments: vm.routeSegments,
                cityDots: vm.cityDots,
                mode: mode,
                onCameraSettled: { region in
                    cameraRegion = region
                    vm.resolveFocusedRegion(for: region)
                },
                handoffRegion: handoffRegion
            )
            .ignoresSafeArea()

            topScrim

            chrome

            if vm.isEmpty {
                emptyState
            }

            if vm.isLoading {
                CarLoadingView()
            }
        }
        .task {
            await vm.loadIfNeeded(tripManager: mapVM.tripManager, territory: mapVM.territoryManager)
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            MyMapFullscreenView(
                vm: vm,
                mode: mode,
                initialRegion: cameraRegion,
                onDismiss: { region in handoffRegion = region }
            )
            .environmentObject(lang)
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

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(AppStrings.myMapTitle(lang.language))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 1)
                Spacer()
                Button {
                    showFullscreen = true
                    Haptics.tap()
                } label: {
                    ExpandBracketsIcon()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mymap_expand")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            MapSegmentControl(mode: $mode)
                // The pill's material must resolve DARK over the night map
                // regardless of the system theme (Figma: dark glass).
                .environment(\.colorScheme, .dark)
                .padding(.top, 10)

            Spacer()

            if !vm.isEmpty && !vm.isLoading {
                statsPlate
                    .padding(.horizontal, 16)
                    // Clear the floating tab bar (74pt pill + 14pt gap).
                    .padding(.bottom, 102)
            }
        }
    }

    // MARK: - Stats plate (absolute ↔ region morph)

    @ViewBuilder
    private var statsPlate: some View {
        Group {
            if let region = vm.focusedRegion {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        Circle().fill(AppTheme.accent).frame(width: 9, height: 9)
                        Text(region.name)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Color(red: 30/255, green: 30/255, blue: 35/255))
                            .lineLimit(1)
                    }
                    HStack(spacing: 0) {
                        plateColumn(value: Self.groupedNumber(region.km2, lang.language),
                                    label: AppStrings.km2Short(lang.language))
                        divider
                        plateColumn(value: "\(region.cityCount)",
                                    label: AppStrings.citiesGenitive(lang.language, count: region.cityCount))
                        divider
                        plateColumn(value: "\(region.tripCount)",
                                    label: AppStrings.tripsGenitive(lang.language, count: region.tripCount))
                    }
                }
            } else {
                HStack(spacing: 0) {
                    plateColumn(value: Self.groupedNumber(vm.totalKm2, lang.language),
                                label: AppStrings.km2ExploredLabel(lang.language))
                    divider
                    plateColumn(value: "\(vm.regionCount)",
                                label: AppStrings.regionsGenitive(lang.language, count: vm.regionCount))
                    divider
                    plateColumn(value: "\(vm.cityCount)",
                                label: AppStrings.citiesGenitive(lang.language, count: vm.cityCount))
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        .animation(.easeInOut(duration: 0.2), value: vm.focusedRegion)
    }

    private var divider: some View {
        // Fixed height — an unconstrained Rectangle is greedy vertically and
        // would balloon the plate to fill the whole screen. Opacity per the
        // Figma mock's clearly visible hairlines (~#707071 on the white card).
        Rectangle()
            .fill(.black.opacity(0.45))
            .frame(width: 1, height: 36)
    }

    private func plateColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color(red: 30/255, green: 30/255, blue: 35/255))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 100/255, green: 100/255, blue: 110/255))
        }
        .frame(maxWidth: .infinity)
    }

    /// «2 430» — locale-aware grouping (RU uses a space). Formatters are
    /// static (never rebuild formatters per body pass).
    private static let ruFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "; return f
    }()
    private static let enFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","; return f
    }()
    static func groupedNumber(_ value: Int, _ lang: LanguageManager.Language) -> String {
        let formatter = lang == .ru ? ruFormatter : enFormatter
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZigzagTrailIcon()
                .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 48, height: 20)
            Text(AppStrings.emptyMapTitle(lang.language))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
            Text(AppStrings.emptyMapSubtitle(lang.language))
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 178/255, green: 178/255, blue: 189/255))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 280)
    }
}

/// Figma expand icon: four corner brackets.
struct ExpandBracketsIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let arm = w * 0.36
            Path { p in
                p.move(to: CGPoint(x: 0, y: arm)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: arm, y: 0))
                p.move(to: CGPoint(x: w - arm, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: arm))
                p.move(to: CGPoint(x: w, y: h - arm)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - arm, y: h))
                p.move(to: CGPoint(x: arm, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - arm))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
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
