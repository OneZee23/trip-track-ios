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

    /// Approximate area of one geohash-6 tile in km².
    private static let km2PerTile: Double = 0.72

    private func statsCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let tileCount = mapVM.territoryManager.visitedTileCount
        let exploredKm2 = Int(Double(tileCount) * Self.km2PerTile)
        let cityCount = cities.count
        let regionCount = regions.count
        let topRegion = regions.sorted(by: { $0.percentage > $1.percentage }).first

        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                // Left column: explored area
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(exploredKm2)")
                            .font(.system(size: 34, weight: .heavy).monospacedDigit())
                            .foregroundStyle(AppTheme.accent)
                        Text(isRu ? "км²" : "km²")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.accent.opacity(0.7))
                    }

                    Text(isRu ? "ИССЛЕДОВАНО" : "EXPLORED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(c.textSecondary)
                        .tracking(0.5)
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
                    let km2 = Int(Double(place.tileCount) * Self.km2PerTile)
                    let targetKm2 = Int(Double(place.target) * Self.km2PerTile)
                    Text("\(km2)/\(targetKm2) \(isRu ? "км²" : "km²")")
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
