import SwiftUI

/// Карточка выбранного на карте объекта: поездка, дорога, находка.
///
/// **Сводки и региона здесь больше нет.** С 27 сентября и то и другое живёт в
/// нижнем слоте «Атласа» (`AtlasSheet`): пока на одном экране стояли две
/// разные шторки — эта с радиусом 28 и своей пружиной и новая с радиусом 24 и
/// своей, — переход между ними читался как «открылась какая-то другая
/// модалка», а заголовок региона висел отдельным слоем поверх статус-бара.
/// Ведёшь сюда ещё один объект — сначала спроси, не место ли ему в слоте.
struct MyMapSheet: View {
    @ObservedObject var vm: MyMapViewModel
    var onOpenTrip: (UUID) -> Void
    /// Тап по печати в журнале. Замыканием, а не `vm.select` прямо здесь:
    /// в волне 4 у находки появится своя карточка, и меняться должен один
    /// вызов на экране, а не строка внутри списка.
    var onOpenDiscovery: (UUID) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit

    /// Full-width sheet, aligned to the map attribution at the 16 pt inset.
    static let summaryMaxWidth: CGFloat = .infinity

    /// HTML A1: 166 pt content plus the tab bar clearance = 278 pt.
    static let collapsedCardHeight: CGFloat = 166

    /// HTML A1 measures the sheet and its own bar from the physical bottom.
    /// Use the same height for MapKit attribution, without querying UIWindow
    /// while SwiftUI is building the map's view graph.
    static let collapsedHeight = collapsedCardHeight + CustomTabBar.clearance + 2

    @State private var isExpanded = false
    /// Высота содержимого свёрнутой карточки, измеренная на прошлом кадре.
    ///
    /// Свёрнутая карточка региона стояла на литерале 350 pt, а её содержимое
    /// (три плитки + города + подсказка) занимает около 260 — под «Потяни
    /// вверх» оставалось двести точек пустоты, и владелец увидел ровно её
    /// 26 сентября. Теперь карточка облегает содержимое; литерал остался
    /// только как ответ до первого замера.
    @State private var measuredContentHeight: CGFloat = 0
    /// То же для раскрытой: у неё содержимое другое (список поездок), и
    /// одним числом эти два состояния не описать.
    @State private var measuredExpandedHeight: CGFloat = 0
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                detailPanel(maxHeight: geo.size.height, safeBottom: geo.safeAreaInsets.bottom)
                    .transition(.move(edge: .bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.snappy(duration: 0.28), value: vm.selection)
        .animation(.snappy(duration: 0.28), value: isExpanded)
        .onChange(of: vm.selection) { _, _ in
            isExpanded = false
        }
    }

    // MARK: - Selected object

    private func detailPanel(maxHeight: CGFloat, safeBottom: CGFloat) -> some View {
        let c = AppTheme.colors(for: scheme)
        // Высота считается ВМЕСТЕ с местом под таб-бар: содержимое карточки
        // прижато к её верху, и без этого запаса последняя строка ложилась в
        // семи точках от пилюли — «сливается всё» (владелец, 23 сен).
        let target = (isExpanded ? min(expandedHeight, maxHeight * 0.86) : baseHeight)
            + CustomTabBar.clearance
        return VStack(spacing: 0) {
            grabber(c).gesture(dragGesture)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let trip = vm.selectedTrip {
                        tripCard(trip, c)
                    } else if let discovery = vm.selectedDiscovery {
                        DiscoveryCardSheet(discovery: discovery)
                    } else if let road = vm.selectedRoad {
                        roadCard(road, c)
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SheetContentHeightKey.self,
                                               value: proxy.size.height)
                    }
                }
                .padding(.bottom, 20 + CustomTabBar.clearance)
            }
            // Свёрнутой карточке скроллить нечего — она облегает содержимое.
            // Пока скролл был включён, он съедал жест вверх, и «потяни
            // вверх» работало только за саму ручку в 36 pt.
            .scrollDisabled(!isExpanded)
        }
        // Свёрнутая карточка ТЯНЕТСЯ ЦЕЛИКОМ: подсказка зовёт тянуть, и
        // отвечать на это обязана вся она. Развёрнутая — только ручкой,
        // иначе жест снова отнимет скролл у списка поездок (урок 0.7.0:
        // «карточка, содержимое которой нельзя достать»).
        .gesture(isExpanded ? nil : dragGesture)
        .frame(maxWidth: .infinity)
        .frame(height: max(120, target - drag))
        .background(AtlasTheme.background, in: UnevenRoundedRectangle(
            topLeadingRadius: 28, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous
        ))
        .overlay(alignment: .topTrailing) {
            closeButton(c)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: 20, y: -6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(panelIdentifier)
        .onPreferenceChange(SheetContentHeightKey.self) { height in
            // Только в свёрнутом виде: развёрнутая карточка содержит список
            // поездок, и её замер сделал бы свёрнутую во весь экран. И только
            // на ЗАМЕТНОЕ изменение — запись на каждый кадр разметки это тот
            // самый цикл, о котором предупреждает `ContentView`.
            guard height > 0 else { return }
            if isExpanded {
                guard abs(height - measuredExpandedHeight) > 1 else { return }
                measuredExpandedHeight = height
            } else {
                guard abs(height - measuredContentHeight) > 1 else { return }
                measuredContentHeight = height
            }
        }
    }

    /// The drag handle, and the ONLY thing that drags.
    ///
    /// The gesture used to sit on the whole panel, where it swallowed the
    /// scroll of the list underneath: a region with forty-four trips opened a
    /// card whose contents could not be reached at all. A grabber-only handle
    /// is also what every sheet on iOS does.
    private func grabber(_ c: AppTheme.Colors) -> some View {
        Capsule()
            .fill(AtlasTheme.handle)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .accessibilityIdentifier("mymap_grabber")
    }

    /// Lets the UI tour assert which card is up without reading its copy.
    private var panelIdentifier: String {
        if vm.selectedTrip != nil { return "mymap_trip_card" }
        if vm.selectedDiscovery != nil { return "mymap_discovery_card" }
        if vm.selectedRoad != nil { return "mymap_road_card" }
        return "mymap_region_card"
    }

    private var baseHeight: CGFloat {
        if vm.selectedTrip != nil { return 176 }
        // Карточка находки: медальон, имя, дата — и, у секрета, история; у
        // загадки — мини-карта с кругом. «На карте» здесь нет, мы уже на
        // карте (`DiscoveryCardSheet.showsOnMap`).
        if vm.selectedDiscovery != nil { return 300 }
        // Header plus three rows — enough to read as a list worth pulling up.
        if vm.selectedRoad != nil { return 260 }
        // Регион облегает содержимое: плитки, города и подсказка «потяни
        // вверх» — и ничего сверх них. 350 остаётся ответом до первого
        // замера, а потолок держит карточку края с длинным списком городов
        // в разумных границах.
        guard measuredContentHeight > 0 else { return 350 }
        return min(max(measuredContentHeight + 26, 200), 420)
    }

    /// Карточки, под которыми есть ещё что-то: список поездок региона, список
    /// поездок дороги — и история секрета, которая бывает в несколько абзацев.
    private var canExpand: Bool {
        vm.selectedRoad != nil || vm.selectedDiscovery != nil
    }

    /// Раскрытая карточка тоже облегает содержимое — просто содержимого у
    /// неё больше. Потолок ставит вызывающий (`maxHeight * 0.86`): выше него
    /// карточка накрыла бы карту, ради которой экран и открыт.
    private var expandedHeight: CGFloat {
        guard canExpand else { return baseHeight }
        guard measuredExpandedHeight > 0 else { return 560 }
        return max(measuredExpandedHeight + 26, baseHeight)
    }

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
        .buttonStyle(PressableCardStyle())
        .padding(.trailing, 16)
        .padding(.top, 14)
        .accessibilityIdentifier("mymap_close")
        .accessibilityLabel(AppStrings.closeSheet(lang.language))
    }

    /// Строка поездки. Осталась от карточки региона, которая уехала в слот, —
    /// её по-прежнему рисует карточка ДОРОГИ, и второй копии быть не должно.
    private func tripRow(_ trip: MapTripPin, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            MapTripThumb(trip: trip, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate,
                                             language: lang.language)
                     ?? AppStrings.tripTitle(lang.language))
                    .font(AppType.itemTitle)
                    .foregroundStyle(AtlasTheme.ink)
                    .lineLimit(1)
                Text(tripSubtitle(trip))
                    .font(.inter(12))
                    .foregroundStyle(AtlasTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AtlasTheme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func tripSubtitle(_ trip: MapTripPin) -> String {
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        let km = Measure.distance(
            metres: trip.distance, unit: distanceUnit, lang: lang.language, style: .tenths)
        return "\(when) · \(km)"
    }

    private func sectionTitle(
        _ text: String,
        _ c: AppTheme.Colors,
        action: (title: String, run: () -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .atlasSectionStyle()
            Spacer(minLength: 8)
            if let action {
                Button {
                    Haptics.tap()
                    action.run()
                } label: {
                    HStack(spacing: 3) {
                        Text(action.title)
                            .font(.inter(13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(AtlasTheme.accent)
                    // A comfortable target without pushing the heading around.
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
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
                .font(.inter(17, weight: .semibold))
                .foregroundStyle(AtlasTheme.ink)
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
            .buttonStyle(PressableCardStyle())
        }

        if !isExpanded, trips.count > 2 {
            Text(AppStrings.mapRoadPullHint(lang.language))
                .font(.inter(12))
                .foregroundStyle(AtlasTheme.secondary)
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
                     ?? (AppStrings.tripTitle(lang.language)))
                    .font(.inter(16, weight: .bold))
                    .foregroundStyle(AtlasTheme.ink)
                    .lineLimit(1)
                Text(tripHeadline(trip))
                    .font(.inter(12))
                    .foregroundStyle(AtlasTheme.secondary)
                    .lineLimit(1)
                Text(tripSpeeds(trip))
                    .font(.inter(12))
                    .foregroundStyle(AtlasTheme.secondary)
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
                .background(AtlasTheme.accent, in: Capsule())
        }
        .buttonStyle(PressableCardStyle())
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .accessibilityIdentifier("mymap_open_trip")
    }

    private func tripHeadline(_ trip: MapTripPin) -> String {
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        let km = Measure.distance(
            metres: trip.distance, unit: distanceUnit, lang: lang.language, style: .grouped)
        let time = Trip.formattedTimeHuman(trip.duration, lang: lang.language)
        return "\(when) · \(km) · \(time)"
    }

    private func tripSpeeds(_ trip: MapTripPin) -> String {
        let avg = AppStrings.myMapAvg(lang.language)
        let max = AppStrings.myMapMax(lang.language)
        let a = Measure.speed(ms: trip.avgSpeedMS, unit: distanceUnit, lang: lang.language)
        let m = Measure.speed(ms: trip.maxSpeedMS, unit: distanceUnit, lang: lang.language)
        return "\(avg) \(a) · \(max) \(m)"
    }
}

// MARK: - Pieces

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


/// Высота содержимого карточки. Ключ — не «ещё один PreferenceKey ради
/// красоты»: без замера свёрнутая карточка региона стояла на литерале и
/// оставляла под собой пустое поле.
private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
