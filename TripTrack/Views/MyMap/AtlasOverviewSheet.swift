import SwiftUI

/// The three positions of the atlas sheet share one hierarchy and one search.
/// Only the handle drags; scrolling results never moves the sheet underneath.
struct AtlasOverviewSheet: View {
    @ObservedObject var vm: MyMapViewModel
    @Binding var isFull: Bool
    var availableHeight: CGFloat
    var onShare: () -> Void
    var onSettings: () -> Void
    var onExplain: () -> Void
    var onOpenTrip: (UUID) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var unit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHalf = false
    @State private var query = ""
    @State private var showsTrips = false
    @State private var searchResults = AtlasOverviewIndex.empty.search("", language: .en)
    @FocusState private var searchFocused: Bool
    @GestureState private var translation: CGFloat = 0

    private var expanded: Bool { isHalf || isFull }
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var height: CGFloat {
        if isFull { return availableHeight }
        if isHalf { return min(440, availableHeight * 0.72) }
        return min(MyMapSheet.collapsedHeight, availableHeight * 0.52)
    }

    var body: some View {
        VStack(spacing: 14) {
            handle
            if expanded {
                expandedContent
            } else {
                summary
                regionChips
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: max(180, height - translation), alignment: .top)
        .background(AtlasTheme.background, in: UnevenRoundedRectangle(
            topLeadingRadius: 28, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 28))
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: 20, y: -6)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: isHalf)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: isFull)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(expanded ? "mymap_region_list" : "mymap_summary")
        .onChange(of: isFull) { _, full in
            if !full { searchFocused = false; query = "" }
        }
        .onReceive(vm.$overview) { index in
            searchResults = index.search(query, language: lang.language)
        }
        .onChange(of: query) { _, query in
            searchResults = vm.overview.search(query, language: lang.language)
        }
        .onChange(of: lang.language) { _, language in
            searchResults = vm.overview.search(query, language: language)
        }
        .sheet(isPresented: $showsTrips) {
            tripList
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var handle: some View {
        Button { advance() } label: {
            Capsule().fill(AtlasTheme.separator)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 13, alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.mapPullHint(lang.language))
        .accessibilityIdentifier("mymap_grabber")
        .gesture(DragGesture(minimumDistance: 8)
            .updating($translation) { value, state, _ in
                state = value.translation.height * 0.28
            }
            .onEnded { value in
                let travel = value.predictedEndTranslation.height
                if travel < -45 { advance() }
                else if travel > 45 {
                    Haptics.selection()
                    if isFull { isFull = false; isHalf = true }
                    else { isHalf = false }
                }
            })
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: onExplain) {
                    HStack(spacing: 4) {
                        Text(AppStrings.atlasExplored(lang.language).uppercased(lang.language))
                            .tracking(AppType.statCaptionTracking)
                        Image(systemName: "info.circle").font(.system(size: 11))
                    }
                    .font(AppType.statCaption)
                    .foregroundStyle(AtlasTheme.secondary)
                    .frame(height: 14)
                }
                .buttonStyle(PressableCardStyle())
                Button { advance() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        ViewThatFits(in: .horizontal) {
                            distanceLine(size: 40)
                            distanceLine(size: 32)
                            distanceLine(size: 26)
                        }
                        .frame(height: 44, alignment: .bottom)
                        Text(summaryCaption)
                            .font(AppType.meta)
                            .foregroundStyle(AtlasTheme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AtlasTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AtlasTheme.accentSoft, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            }
            .buttonStyle(PressableCardStyle())
            .disabled(vm.isEmpty || vm.isFiltering)
            .accessibilityLabel(AppStrings.share(lang.language))
            .accessibilityIdentifier("mymap_share")
        }
    }

    private func distanceLine(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Measure.distance(km: vm.revealed.openedKm, unit: unit, lang: lang.language))
                .font(AppType.display(size)).tracking(-0.6)
                .monospacedDigit()
            Text(vm.period == .allTime ? AppStrings.atlasNewRoads(lang.language)
                 : AppStrings.atlasUniqueRoads(lang.language))
                .font(AppType.unit)
                .foregroundStyle(AtlasTheme.secondary)
        }
        .foregroundStyle(AtlasTheme.ink)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var summaryCaption: String {
        let distance = Measure.distance(km: vm.exploration.totalKm, unit: unit, lang: lang.language)
        var caption = distance + " " + AppStrings.atlasTotalDistanceSuffix(lang.language)
            + " · \(vm.exploration.tripCount) "
            + AppStrings.tripsGenitive(lang.language, count: vm.exploration.tripCount)
            + " · \(vm.overview.cityCount) "
            + AppStrings.citiesGenitive(lang.language, count: vm.overview.cityCount)
        // Только при выбранном периоде: без него все места свои, и «5 из 5»
        // это строка, которая ничего не сообщает.
        if vm.period != .allTime, !vm.placePins.isEmpty {
            let l = lang.language
            let inside = AtlasPlaces.inPeriodCount(vm.placePins)
            let places = "\(AppStrings.formattedCount(inside, lang: l)) \(AppStrings.nounPlaces(l, inside))"
            caption += " · " + AppStrings.atlasPlacesInPeriod(l, places: places, total: vm.placePins.count)
        }
        return caption
    }

    private var regionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(vm.journal.regions) { region in
                    Button { vm.select(.region(region.id)) } label: {
                        HStack(spacing: 8) {
                            Text(region.localizedName(lang.language)).foregroundStyle(AtlasTheme.ink)
                            Text(Measure.distance(km: region.openedKm, unit: unit, lang: lang.language))
                                .foregroundStyle(AtlasTheme.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(AtlasTheme.secondary)
                        }
                        .font(AppType.chip)
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(AtlasTheme.card, in: Capsule())
                        .overlay(Capsule().stroke(AtlasTheme.separator.opacity(0.6), lineWidth: 0.7))
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("atlas_region_\(region.id)")
                }
                if vm.journal.regions.isEmpty && vm.period == .allTime {
                    Text(AppStrings.emptyMapSubtitle(lang.language))
                        .font(AppType.meta).foregroundStyle(AtlasTheme.secondary)
                        .frame(height: 44)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.trailing, 16)
        .padding(.trailing, -16)
    }

    private var expandedContent: some View {
        let results = searchResults
        return VStack(spacing: 14) {
            if isFull {
                HStack {
                    Text(AppStrings.myMapTitle(lang.language))
                        .font(AppType.title)
                    Spacer()
                    Button { isFull = false; isHalf = false } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(AtlasTheme.separator.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("mymap_close")
                    .accessibilityLabel(AppStrings.closeSheet(lang.language))
                }
                searchField
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !hasQuery { statistics }
                    if results.isEmpty {
                        VStack(spacing: 8) {
                            Text(AppStrings.atlasSearchEmpty(lang.language))
                                .font(AppType.itemTitle)
                            Text(AppStrings.atlasSearchEmptyBody(lang.language))
                                .font(AppType.body)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(AtlasTheme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityIdentifier("atlas_search_empty")
                    }
                    if hasQuery { searchMatches(results) }
                    ForEach(results.countries) { country in
                            countryHeader(country.id, count: country.regions.count)
                            ForEach(country.regions) { region in
                                Button { Haptics.selection(); vm.select(.region(region.id)) } label: {
                                    AtlasRegionRow(region: region)
                                }
                                .buttonStyle(PressableCardStyle())
                                .accessibilityIdentifier("atlas_region_\(region.id)")
                            }
                    }
                    if isFull || hasQuery {
                        if !hasQuery && !results.cities.isEmpty {
                            Text(AppStrings.atlasCities(lang.language))
                                .atlasSectionStyle()
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                                ForEach(results.cities) { city in cityButton(city) }
                            }
                        }
                        Button(action: onSettings) {
                            Label(AppStrings.atlasSettings(lang.language), systemImage: "slider.horizontal.3")
                                .font(AppType.button)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                .padding(.horizontal, 16)
                                .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(PressableCardStyle())
                    } else {
                        Button { isFull = true } label: {
                            Label(AppStrings.atlasCityOrRegion(lang.language), systemImage: "magnifyingglass")
                                .font(AppType.itemTitle)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityIdentifier("atlas_expand_search")
                    }
                }
                .padding(.bottom, isFull ? 30 : CustomTabBar.clearance + 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(AtlasTheme.ink)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AtlasTheme.secondary)
            TextField(AppStrings.atlasCityOrRegion(lang.language), text: $query)
                .focused($searchFocused).autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("atlas_search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 36, height: 44)
                }
                .accessibilityLabel(AppStrings.cancel(lang.language))
            }
        }
        .font(.inter(16)).padding(.leading, 12).padding(.trailing, 4)
        .frame(height: 44)
        .background(AtlasTheme.separator.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statistics: some View {
        AtlasStatRow {
            AtlasStatTile(
                value: Measure.distance(km: vm.revealed.openedKm, unit: unit, lang: lang.language),
                label: vm.period == .allTime
                    ? AppStrings.atlasNewRoads(lang.language)
                    : AppStrings.atlasUniqueRoads(lang.language),
                action: onExplain)
            AtlasStatTile(
                value: Measure.distance(km: vm.exploration.totalKm, unit: unit, lang: lang.language),
                label: AppStrings.atlasTotalTravelled(lang.language),
                action: onExplain)
            if isFull {
                AtlasStatTile(
                    value: "\(vm.exploration.tripCount)",
                    label: AppStrings.tripsGenitive(lang.language, count: vm.exploration.tripCount),
                    action: { showsTrips = true })
            } else {
                AtlasStatTile(
                    value: "\(vm.overview.cityCount)",
                    label: AppStrings.citiesGenitive(lang.language, count: vm.overview.cityCount),
                    action: { isFull = true })
            }
        }
    }

    private func countryHeader(_ code: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(RegionAtlas.shared.countryName(code, lang.language) ?? code)
                .atlasSectionStyle()
            Spacer()
            Text("\(count) " + AppStrings.regionsGenitive(lang.language, count: count))
                .font(AppType.meta).foregroundStyle(AtlasTheme.secondary)
        }
    }

    private func cityButton(_ city: AtlasOverviewIndex.City) -> some View {
        Button {
            searchFocused = false
            isFull = false; isHalf = false
            vm.cameraCommand = .fit(GeoBounds(around: city.coordinate, metres: 12_000), padding: .overview)
            Haptics.selection()
        } label: {
            VStack(spacing: 3) {
                Label(city.localizedName(lang.language), systemImage: city.isVisited ? "checkmark" : "cloud")
                    .font(AppType.chip)
                if !city.isVisited {
                    Text(city.wasVisited ? AppStrings.atlasNoTripsInPeriod(lang.language)
                         : AppStrings.atlasNotVisited(lang.language))
                        .font(AppType.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(city.isVisited ? AtlasTheme.accentInk : AtlasTheme.secondary)
            .frame(maxWidth: .infinity, minHeight: city.isVisited ? 44 : 56)
            .padding(.horizontal, 8)
            .background(city.isVisited ? AtlasTheme.accentSoft : AtlasTheme.card, in: Capsule())
            .overlay {
                if !city.isVisited {
                    Capsule().strokeBorder(AtlasTheme.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("atlas_city_\(city.id)")
    }

    @ViewBuilder
    private func searchMatches(_ results: AtlasOverviewIndex.SearchResults) -> some View {
        // Group by actual visits across BOTH object types: an unopened
        // region must not precede an opened city just because it is a region.
        ForEach([true, false], id: \.self) { visited in
            ForEach(results.regions.filter { $0.isVisited == visited }) { region in
                searchRegionButton(region)
            }
            let cities = results.cities.filter { $0.isVisited == visited }
            if !cities.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(cities) { city in cityButton(city) }
                }
            }
        }
    }

    private func searchRegionButton(_ result: AtlasOverviewIndex.SearchRegion) -> some View {
        Button {
            searchFocused = false
            Haptics.selection()
            if result.isVisited {
                vm.select(.region(result.id))
            } else {
                isFull = false; isHalf = false
                vm.cameraCommand = .fit(result.region.bounds, padding: .overview)
            }
        } label: {
            if let visited = result.visited {
                AtlasRegionRow(region: visited)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "cloud")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.region.localizedName(lang.language))
                            .font(AppType.itemTitle)
                        Text(result.wasVisited ? AppStrings.atlasNoTripsInPeriod(lang.language)
                             : AppStrings.atlasNotVisited(lang.language))
                            .font(AppType.meta)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12))
                }
                .foregroundStyle(AtlasTheme.secondary)
                .padding(16)
                .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(AtlasTheme.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("atlas_region_\(result.id)")
    }

    private var tripList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(AppStrings.atlasAllTrips(lang.language)).font(AppType.sheetTitle)
                Spacer()
                Button { showsTrips = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(AppStrings.closeSheet(lang.language))
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vm.overview.tripsByDate) { trip in
                        Button {
                            showsTrips = false
                            vm.select(.trip(trip.id))
                        } label: {
                            HStack(spacing: 12) {
                                MapTripThumb(trip: trip, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language)
                                         ?? AppStrings.tripTitle(lang.language))
                                        .font(AppType.itemTitle)
                                    Text(RelativeTripDate.string(from: trip.startDate, language: lang.language)
                                         + " · " + Measure.distance(metres: trip.distance, unit: unit, lang: lang.language))
                                        .font(AppType.meta).foregroundStyle(AtlasTheme.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12))
                            }
                            .padding(12).background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            }
        }
        .padding(20).padding(.top, 12).foregroundStyle(AtlasTheme.ink)
        .background(AtlasTheme.background)
    }

    private func advance() {
        Haptics.selection()
        if isHalf { isFull = true } else { isHalf = true }
    }

}
