import SwiftUI
import MapKit

struct RegionsView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var visitedGeohashes: Set<String> = []
    @State private var tripPolylines: [MKPolyline] = []
    @State private var cities: [ExplorationPlace] = []
    @State private var regions: [ExplorationPlace] = []
    @State private var isMapExpanded = false
    @State private var isLoading = true

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
        ZStack {
        if isLoading {
            CarLoadingView()
        }
        ScrollView {
            VStack(spacing: 10) {
                // Fog of War map (inline, tap to expand)
                ZStack(alignment: .bottomTrailing) {
                    ScratchMapView(
                        visitedGeohashes: visitedGeohashes,
                        tripPolylines: tripPolylines,
                        isDark: mapVM.isDarkMap
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onTapGesture { toggleMap() }

                    Button { toggleMap() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "map")
                                .font(.system(size: 12, weight: .semibold))
                            Text(AppStrings.map(lang.language))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(c.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(c.border, lineWidth: 1))
                    }
                    .padding(12)
                }

                // Stats card
                statsCard(c, isRu: isRu)

                // Cities section
                if !cities.isEmpty {
                    placesSection(
                        title: isRu ? "Города" : "Cities",
                        icon: "building.2.fill",
                        places: cities,
                        c: c
                    )
                }

                // Regions section
                if !regions.isEmpty {
                    placesSection(
                        title: isRu ? "Регионы" : "Regions",
                        icon: "map.fill",
                        places: regions,
                        c: c
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
        .overlay(alignment: .bottom) {
            if mapVM.isRecording {
                RecordingBanner(
                    distance: mapVM.distance,
                    duration: mapVM.duration,
                    onTap: {
                        NotificationCenter.default.post(name: .tripSuggestionTapped, object: nil)
                    }
                )
                .padding(.bottom, tabBarHeight + 8)
            }
        }
        .opacity(isLoading ? 0 : 1)
        .task {
            mapVM.checkSunTheme()
            loadData()
            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }
        }
        .fullScreenCover(isPresented: $isMapExpanded) {
            FullscreenFogMapView(
                visitedGeohashes: visitedGeohashes,
                tripPolylines: tripPolylines,
                isDark: mapVM.isDarkMap,
                onDismiss: { isMapExpanded = false }
            )
        }
        .navigationTitle(isRu ? "Исследование" : "Exploration")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(c.bg.opacity(0.95), for: .navigationBar)
        .toolbarBackground(.automatic, for: .navigationBar)
        } // ZStack
        } // NavigationStack
    }



    // MARK: - Stats Card

    private func statsCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let tileCount = mapVM.territoryManager.visitedTileCount
        let cityCount = cities.count
        let regionCount = regions.count
        let topRegion = regions.sorted(by: { $0.percentage > $1.percentage }).first

        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                // Left column: tile count + progress bar
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(tileCount)")
                        .font(.system(size: 34, weight: .heavy).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)

                    Text(AppStrings.tilesDiscovered(lang.language))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(c.textSecondary)
                        .tracking(0.5)

                    // Accent progress bar — milestone-based
                    let nextMilestone: Int = {
                        if tileCount < 100 { return 100 }
                        if tileCount < 500 { return 500 }
                        if tileCount < 1000 { return 1000 }
                        if tileCount < 5000 { return 5000 }
                        return 10000
                    }()
                    let progressFraction = min(Double(tileCount) / Double(nextMilestone), 1.0)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(c.cardAlt)
                                .frame(height: 4)
                            Capsule()
                                .fill(AppTheme.accent)
                                .frame(width: max(4, geo.size.width * progressFraction), height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(tileCount)/\(nextMilestone)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right column: cities + regions counts
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.accent)
                        Text("\(cityCount)")
                            .font(.system(size: 18, weight: .heavy).monospacedDigit())
                            .foregroundStyle(c.text)
                        Text(isRu ? (cityCount == 1 ? "город" : "города") : (cityCount == 1 ? "City" : "Cities"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(c.textSecondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.blue)
                        Text("\(regionCount)")
                            .font(.system(size: 18, weight: .heavy).monospacedDigit())
                            .foregroundStyle(c.text)
                        Text(isRu ? (regionCount == 1 ? "регион" : "региона") : (regionCount == 1 ? "Region" : "Regions"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(c.textSecondary)
                    }
                }
            }

            // Bottom line: top region explored percentage
            if let top = topRegion {
                Text(AppStrings.exploredPercent(lang.language, percent: "\(Int(top.percentage * 100))", place: top.name))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .glassBackground(cornerRadius: 16)
    }

    // MARK: - Places Section

    private func placesSection(title: String, icon: String, places: [ExplorationPlace], c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                placeRow(place: place, c: c)

                if index < places.count - 1 {
                    Rectangle().fill(c.border).frame(height: 1).padding(.leading, 56)
                }
            }

            Spacer().frame(height: 8)
        }
        .surfaceCard(cornerRadius: 16)
    }

    private func placeRow(place: ExplorationPlace, c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru

        return HStack(spacing: 12) {
            // Left: name + subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(place.tileCount)/\(place.target) \(AppStrings.tiles(lang.language))")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)

                    Text(place.status.title(lang.language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(place.status.color)
                }
            }

            Spacer()

            // Circular progress indicator
            circularProgress(percentage: place.percentage, color: place.status.color, c: c)

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func circularProgress(percentage: Double, color: Color, c: AppTheme.Colors) -> some View {
        ZStack {
            Circle()
                .stroke(c.cardAlt, lineWidth: 3)
                .frame(width: 32, height: 32)

            Circle()
                .trim(from: 0, to: percentage)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 32, height: 32)

            Text(String(format: "%.0f", percentage * 100))
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(c.text)
        }
    }

    private func toggleMap() {
        isMapExpanded.toggle()
    }

    // MARK: - Data Loading

    private func loadData() {
        visitedGeohashes = mapVM.territoryManager.visitedGeohashes

        let trips = mapVM.tripManager.fetchTripsWithTrackPoints()
        var polylines: [MKPolyline] = []
        for trip in trips {
            let coords = trip.trackPoints.map(\.coordinate)
            guard coords.count >= 2 else { continue }
            var mutableCoords = coords
            let polyline = MKPolyline(coordinates: &mutableCoords, count: mutableCoords.count)
            polylines.append(polyline)
        }
        tripPolylines = polylines

        let exploration = mapVM.territoryManager.getExploration(from: trips)
        cities = exploration.filter { $0.type == .city }
        regions = exploration.filter { $0.type == .region }
    }

    private var tabBarHeight: CGFloat {
        let bottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
        return 54 + bottom
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 59
    }
}

#Preview {
    RegionsView()
        .preferredColorScheme(.dark)
}
