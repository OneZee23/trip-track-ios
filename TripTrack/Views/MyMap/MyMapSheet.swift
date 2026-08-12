import SwiftUI

/// The permanent sheet of «Моя карта» (canon: «Sheet постоянный: свёрнут =
/// сводка + шеринг; тап по объекту подменяет контент; потянуть вверх = полная
/// детализация; смахнуть вниз / ✕ = назад к сводке»).
///
/// Deliberately NOT a system `.sheet`: this screen owns a floating tab bar,
/// and the collapsed summary has to float *above* it (canon frame 1) while a
/// selected card covers it (frames 2–5). A presented sheet can do one or the
/// other, never both, and its detents fight the tab bar the whole way.
struct MyMapSheet: View {
    @ObservedObject var vm: MyMapViewModel
    /// Owned by the screen so it can hide the tab bar under the open panel.
    @Binding var isSummaryExpanded: Bool
    var onOpenTrip: (UUID) -> Void
    var onShare: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    /// `CustomTabBar` caps its pill at 380; Figma draws the collapsed card
    /// 10 pt narrower than the bar, so the card caps 10 lower.
    static let summaryMaxWidth: CGFloat = 370

    /// Grabber + title + one row per region + the bottom padding.
    static func regionListHeight(count: Int) -> CGFloat {
        50 + CGFloat(max(count, 1)) * 56 + 24
    }

    @State private var isExpanded = false
    @State private var showAllTrips = false
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if vm.selection == nil {
                    if isSummaryExpanded {
                        regionListPanel(maxHeight: geo.size.height, safeBottom: geo.safeAreaInsets.bottom)
                            .transition(.move(edge: .bottom))
                    } else {
                        summaryCard
                            .padding(.horizontal, 16)
                            // Clear the floating tab bar (74 pt pill + 14 pt gap).
                            .padding(.bottom, 102)
                            .transition(.opacity)
                    }
                } else {
                    detailPanel(maxHeight: geo.size.height, safeBottom: geo.safeAreaInsets.bottom)
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.snappy(duration: 0.28), value: vm.selection)
        .animation(.snappy(duration: 0.28), value: isExpanded)
        .animation(.snappy(duration: 0.28), value: isSummaryExpanded)
        .onChange(of: vm.selection) { _, _ in
            isExpanded = false
            isSummaryExpanded = false
            showAllTrips = false
        }
    }

    // MARK: - Summary, pulled up

    /// The collapsed summary carries a grabber in the canon frame, and a
    /// grabber that does nothing is a lie. Pulling it up lists every region
    /// you have opened — the same «полная детализация» rule the object cards
    /// follow, applied to the summary's own subject.
    private func regionListPanel(maxHeight: CGFloat, safeBottom: CGFloat) -> some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            grabber(c)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .updating($drag) { value, state, _ in
                            state = min(value.translation.height, 0)
                        }
                        .onEnded { value in
                            if value.translation.height > 60 {
                                Haptics.tap()
                                isSummaryExpanded = false
                            }
                        }
                )

            HStack(spacing: 8) {
                Text(AppStrings.mapSummary(
                    lang.language,
                    regions: vm.exploration.regionCount,
                    km: Int(vm.exploration.totalKm.rounded()),
                    trips: vm.exploration.tripCount
                ))
                .font(.inter(15, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(vm.exploration.regions) { region in
                        Button {
                            Haptics.tap()
                            vm.select(.region(region.id))
                        } label: {
                            regionRow(region, c)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 20 + safeBottom)
            }
        }
        .frame(maxWidth: .infinity)
        // Sized to what is in it. A fixed 520 meant three regions floated at
        // the top of a panel that was mostly empty white.
        .frame(height: max(180, min(Self.regionListHeight(count: vm.exploration.regionCount) + safeBottom,
                                    min(520, maxHeight * 0.7) + safeBottom) - drag))
        .background(c.bg, in: UnevenRoundedRectangle(
            topLeadingRadius: 22, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous
        ))
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                isSummaryExpanded = false
            } label: {
                NavCircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.top, 14)
            .accessibilityIdentifier("mymap_close")
        }
        .shadow(color: .black.opacity(0.25), radius: 18, y: -4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mymap_region_list")
    }

    private func regionRow(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Text(RegionAtlas.flag(for: region.countryCode))
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(region.localizedName(lang.language))
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Text(regionRowSubtitle(region))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(percentText(region.progress))
                .font(.inter(12, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func regionRowSubtitle(_ region: MapRegionStat) -> String {
        let km = "\(AppStrings.groupedNumber(Int(region.km.rounded()), lang.language)) \(lang.language == .ru ? "км" : "km")"
        let trips = "\(region.tripCount) \(AppStrings.tripsGenitive(lang.language, count: region.tripCount))"
        guard region.totalCities > 0 else { return "\(km) · \(trips)" }
        let cities = AppStrings.mapCitiesOfTotal(
            lang.language, opened: region.visitedCityCount, total: region.totalCities)
        return "\(km) · \(trips) · \(cities) \(AppStrings.citiesGenitive(lang.language, count: region.totalCities))"
    }

    // MARK: - Collapsed summary

    /// Figma `sheet-collapsed` (1114:250): 328 wide inside a 360 frame, 64
    /// tall, grabber centred on the CARD, text and share button on one row
    /// below it.
    ///
    /// Two things were off. The grabber sat in a column with the text, so it
    /// was centred over the text rather than the card and read as nudged left.
    /// And the card had no width cap while the tab bar has one at 380 — on a
    /// Pro Max that made the card 408 against the bar's 380, so the thing meant
    /// to be 10 pt NARROWER than the bar came out 28 pt wider. Hence the cap
    /// below: 370 keeps the Figma relationship at every screen size.
    private var summaryCard: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            Capsule()
                .fill(c.textTertiary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack(spacing: 6) {
                Text(AppStrings.mapSummary(
                    lang.language,
                    regions: vm.exploration.regionCount,
                    km: Int(vm.exploration.totalKm.rounded()),
                    trips: vm.exploration.tripCount
                ))
                .font(.inter(14, weight: .semibold))
                .foregroundStyle(vm.isEmpty ? c.textTertiary : c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

                // A grabber alone was not saying «there is more up here» —
                // «совсем не очевидно, что эту панель надо тянуть наверх».
                if !vm.isEmpty {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(c.textTertiary)
                }

                Spacer(minLength: 8)

                if !vm.isEmpty {
                    Button {
                        Haptics.tap()
                        onShare()
                    } label: {
                        // The iOS share glyph, not a bare arrow: nothing about
                        // «↑» said what the button did until you pressed it.
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 32, height: 32)
                            .background(AppTheme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.share(lang.language))
                    .accessibilityIdentifier("mymap_share")
                }
            }
            .frame(height: 32)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: Self.summaryMaxWidth)
        .background(c.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { expandSummary() }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in if value.translation.height < -40 { expandSummary() } }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mymap_summary")
    }

    /// Nothing to list when you have not driven anywhere yet — the empty
    /// state already says so on the map itself.
    ///
    /// With a single region the list was a one-row copy of the line you just
    /// tapped, under half a screen of nothing. Go straight to that region's
    /// card, which is what you were reaching for anyway.
    private func expandSummary() {
        guard !vm.exploration.regions.isEmpty else { return }
        Haptics.selection()
        if vm.exploration.regions.count == 1, let only = vm.exploration.regions.first {
            vm.select(.region(only.id))
        } else {
            isSummaryExpanded = true
        }
    }

    // MARK: - Selected object

    private func detailPanel(maxHeight: CGFloat, safeBottom: CGFloat) -> some View {
        let c = AppTheme.colors(for: scheme)
        let target = (isExpanded ? min(expandedHeight, maxHeight * 0.86) : baseHeight) + safeBottom
        return VStack(spacing: 0) {
            grabber(c).gesture(dragGesture)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let trip = vm.selectedTrip {
                        tripCard(trip, c)
                    } else if let road = vm.selectedRoad {
                        roadCard(road, c)
                    } else if let locked = vm.selectedLockedRegion {
                        lockedCard(locked, c)
                    } else if let region = vm.selectedRegion {
                        regionCard(region, c)
                    }
                }
                .padding(.bottom, 20 + safeBottom)
            }
            .scrollDisabled(!isExpanded)
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(120, target - drag))
        .background(c.bg, in: UnevenRoundedRectangle(
            topLeadingRadius: 22, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous
        ))
        .overlay(alignment: .topTrailing) { closeButton(c) }
        .shadow(color: .black.opacity(0.25), radius: 18, y: -4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(panelIdentifier)
    }

    /// The drag handle, and the ONLY thing that drags.
    ///
    /// The gesture used to sit on the whole panel, where it swallowed the
    /// scroll of the list underneath: a region with forty-four trips opened a
    /// card whose contents could not be reached at all. A grabber-only handle
    /// is also what every sheet on iOS does.
    private func grabber(_ c: AppTheme.Colors) -> some View {
        Capsule()
            .fill(c.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .accessibilityIdentifier("mymap_grabber")
    }

    /// Lets the UI tour assert which card is up without reading its copy.
    private var panelIdentifier: String {
        if vm.selectedTrip != nil { return "mymap_trip_card" }
        if vm.selectedRoad != nil { return "mymap_road_card" }
        if vm.selectedLockedRegion != nil { return "mymap_locked_card" }
        return "mymap_region_card"
    }

    private var baseHeight: CGFloat {
        if vm.selectedTrip != nil { return 176 }
        // Header plus three rows — enough to read as a list worth pulling up.
        if vm.selectedRoad != nil { return 260 }
        if vm.selectedLockedRegion != nil { return 178 }
        return 214
    }

    /// The region card and the road list are the two with more underneath.
    private var canExpand: Bool { vm.selectedRegion != nil || vm.selectedRoad != nil }

    private var expandedHeight: CGFloat { canExpand ? 560 : baseHeight }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($drag) { value, state, _ in
                // Rubber-band past the ends instead of tearing the panel off.
                let raw = -value.translation.height
                if isExpanded { state = min(raw, 0) * 0.6 } else { state = max(raw, 0) * 0.6 }
                state = -state
            }
            .onEnded { value in
                let dy = value.translation.height
                if dy < -50, canExpand, !isExpanded {
                    Haptics.selection()
                    isExpanded = true
                } else if dy > 60 {
                    Haptics.tap()
                    if isExpanded { isExpanded = false } else { vm.select(nil) }
                }
            }
    }

    private func closeButton(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            vm.select(nil)
        } label: {
            NavCircleIcon(systemImage: "xmark")
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 14)
        .accessibilityIdentifier("mymap_close")
        .accessibilityLabel(AppStrings.closeSheet(lang.language))
    }

    // MARK: - Region

    @ViewBuilder
    private func regionCard(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        regionHeader(region, c)

        HStack(spacing: 0) {
            statColumn(AppStrings.groupedNumber(Int(region.km.rounded()), lang.language),
                       AppStrings.mapKmDriven(lang.language), c)
            statColumn("\(region.tripCount)",
                       AppStrings.tripsGenitive(lang.language, count: region.tripCount), c)
            statColumn(region.totalCities > 0
                       ? AppStrings.mapCitiesOfTotal(lang.language,
                                                     opened: region.visitedCityCount,
                                                     total: region.totalCities)
                       : "—",
                       AppStrings.citiesGenitive(lang.language, count: region.totalCities), c)
        }
        .padding(.top, 16)

        progressBar(region, c)
            .padding(.horizontal, 16)
            .padding(.top, 18)

        if isExpanded {
            citiesSection(region, c)
            tripsSection(region, c)
        } else {
            Text(AppStrings.mapPullHint(lang.language))
                .font(.inter(12))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
    }

    private func regionHeader(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(RegionAtlas.flag(for: region.countryCode))
                .font(.system(size: 17))
            Text(region.localizedName(lang.language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func statColumn(_ value: String, _ label: String, _ c: AppTheme.Colors) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.inter(11))
                .foregroundStyle(c.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressBar(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        let value = region.progress
        return VStack(spacing: 8) {
            HStack {
                Text(AppStrings.mapRoadsProgress(lang.language))
                    .font(.inter(11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                Spacer()
                Text(AppStrings.mapRoadsValue(
                    lang.language, km: region.openedRoadKm, percent: percentText(value)))
                    .font(.inter(11, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.cardAlt)
                    Capsule().fill(AppTheme.accent)
                        .frame(width: max(6, geo.size.width * value))
                }
            }
            .frame(height: 6)
        }
    }

    /// «<1%» rather than «0%»: you HAVE been there, and the card saying zero
    /// after a real trip reads as a bug.
    private func percentText(_ value: Double) -> String {
        let percent = value * 100
        if percent > 0 && percent < 1 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }

    // MARK: - Region · expanded

    @ViewBuilder
    private func citiesSection(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        sectionTitle(AppStrings.mapCitiesSection(
            lang.language, opened: region.visitedCityCount, total: region.totalCities), c)

        ForEach(region.cities) { city in
            HStack(spacing: 12) {
                Text(city.localizedName(lang.language))
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                CoverageRing(value: city.coverage)
                    .frame(width: 22, height: 22)
                Text(percentText(city.coverage))
                    .font(.inter(12, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }

        ForEach(lockedCities(region), id: \.self) { name in
            HStack {
                Text(name)
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(AppStrings.mapCityLocked(lang.language))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }

    /// The biggest cities you have NOT opened — the ones worth driving to.
    private func lockedCities(_ region: MapRegionStat) -> [String] {
        let opened = Set(region.cities.map(\.name))
        return RegionAtlas.shared.cities(in: region.id)
            .filter { !opened.contains($0.name) }
            .prefix(4)
            .map { $0.localizedName(lang.language) }
    }

    @ViewBuilder
    private func tripsSection(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        let trips = region.tripIds.compactMap { vm.exploration.trip(id: $0) }
            .sorted { $0.startDate > $1.startDate }

        // «Все N» rides the section heading rather than sitting under the
        // last row: at the bottom of a scrolling card it was below the fold
        // and nobody saw it. Beside the heading it is where the eye already
        // is when it reads «ПОЕЗДКИ ЗДЕСЬ · 60».
        sectionTitle(
            AppStrings.mapTripsSection(lang.language, count: trips.count), c,
            action: trips.count > 4 && !showAllTrips
                ? (AppStrings.mapSeeAll(lang.language, count: trips.count), { showAllTrips = true })
                : nil
        )

        ForEach(showAllTrips ? trips : Array(trips.prefix(4))) { trip in
            Button {
                Haptics.tap()
                vm.select(.trip(trip.id))
            } label: {
                tripRow(trip, c)
            }
            .buttonStyle(.plain)
        }
    }

    private func tripRow(_ trip: MapTripPin, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            MapTripThumb(trip: trip, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language)
                     ?? (lang.language == .ru ? "Поездка" : "Trip"))
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Text(tripSubtitle(trip))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func tripSubtitle(_ trip: MapTripPin) -> String {
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        let km = String(format: lang.language == .ru ? "%.1f км" : "%.1f km", trip.distanceKm)
            .replacingOccurrences(of: ".", with: lang.language == .ru ? "," : ".")
        return "\(when) · \(km)"
    }

    private func sectionTitle(
        _ text: String,
        _ c: AppTheme.Colors,
        action: (title: String, run: () -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.inter(11, weight: .bold))
                .foregroundStyle(c.textTertiary)
            Spacer(minLength: 8)
            if let action {
                Button {
                    Haptics.tap()
                    action.run()
                } label: {
                    HStack(spacing: 3) {
                        Text(action.title)
                            .font(.inter(13, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.accent)
                    // A comfortable target without pushing the heading around.
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mymap_see_all")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    // MARK: - Road

    /// Tap a road you drive every day and you should get every trip that used
    /// it, not whichever one happened to be nearest. Without this the map felt
    /// like it held four trips: the photo-pins, and nothing else reachable.
    @ViewBuilder
    private func roadCard(_ trips: [MapTripPin], _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(AppStrings.mapRoadTrips(lang.language, count: trips.count))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)

        ForEach(isExpanded ? trips : Array(trips.prefix(2))) { trip in
            Button {
                Haptics.tap()
                vm.select(.trip(trip.id))
            } label: {
                tripRow(trip, c)
            }
            .buttonStyle(.plain)
        }

        if !isExpanded, trips.count > 2 {
            Text(AppStrings.mapRoadPullHint(lang.language))
                .font(.inter(12))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }

    // MARK: - Trip

    @ViewBuilder
    private func tripCard(_ trip: MapTripPin, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            MapTripThumb(trip: trip, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language)
                     ?? (lang.language == .ru ? "Поездка" : "Trip"))
                    .font(.inter(16, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Text(tripHeadline(trip))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
                Text(tripSpeeds(trip))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)

        Button {
            Haptics.action()
            onOpenTrip(trip.id)
        } label: {
            Text(AppStrings.mapOpenTrip(lang.language))
                .font(.inter(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .accessibilityIdentifier("mymap_open_trip")
    }

    private func tripHeadline(_ trip: MapTripPin) -> String {
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        let km = String(format: lang.language == .ru ? "%.0f км" : "%.0f km", trip.distanceKm)
        let time = Trip.formattedTimeHuman(trip.duration, lang: lang.language)
        return "\(when) · \(km) · \(time)"
    }

    private func tripSpeeds(_ trip: MapTripPin) -> String {
        let unit = lang.language == .ru ? "км/ч" : "km/h"
        let avg = lang.language == .ru ? "ср." : "avg"
        let max = lang.language == .ru ? "макс." : "max"
        return "\(avg) \(Int(trip.avgSpeedKmh.rounded())) \(unit) · \(max) \(Int(trip.maxSpeedKmh.rounded())) \(unit)"
    }

    // MARK: - Locked region

    @ViewBuilder
    private func lockedCard(_ region: RegionAtlas.Region, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(region.localizedName(lang.language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(AppStrings.mapRegionLocked(lang.language))
                .font(.inter(11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(c.cardAlt, in: Capsule())
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)

        Text(AppStrings.mapLockedStats(
            lang.language, totalCities: RegionAtlas.shared.cities(in: region.id).count))
            .font(.inter(14))
            .foregroundStyle(c.textSecondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)

        if let trace = vm.nearestTrace(to: region) {
            Text(AppStrings.mapLockedTeaser(
                lang.language,
                km: trace.distanceKm,
                bearing: AppStrings.mapBearing(lang.language, trace.bearing),
                city: trace.cityName,
                when: trace.date.map { AppStrings.monthYear(lang.language, $0) }
            ))
            .font(.inter(12))
            .foregroundStyle(c.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

// MARK: - Pieces

/// Canon `city-row` ring: a dashed track with the covered arc drawn over it.
struct CoverageRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.accent.opacity(0.25),
                        style: StrokeStyle(lineWidth: 2, dash: [2.5, 2.5]))
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Trip thumbnail: the photo if there is one, otherwise the route drawn from
/// the trip's own preview polyline — never a generic icon, since the shape of
/// the road is the thing you actually recognise.
struct MapTripThumb: View {
    let trip: MapTripPin
    var size: CGFloat = 40

    @Environment(\.colorScheme) private var scheme
    @State private var photo: UIImage?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(c.cardAlt)
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else if trip.route.count > 1 {
                    GeometryReader { geo in
                        SharePosterRoute(
                            points: SharePosterView.project(trip.route, in: geo.size, inset: 8),
                            lineWidth: size * 0.075
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .frame(width: size, height: size)
            .task(id: trip.photoFilename) {
                guard let filename = trip.photoFilename else { return }
                photo = await PhotoStorageService.loadThumbnail(filename: filename, maxSize: size * 3)
            }
    }
}
