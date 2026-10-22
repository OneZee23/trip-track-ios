import CoreLocation
import SwiftUI

/// Карта публичных поездок другого человека (0.6.3).
///
/// Это НЕ вторая карта. Рендер тот же самый — `MyMapRepresentable`,
/// `MyMapOverlays`, `MapExploration`, — меняется ровно один вход: поездки
/// приезжают из `RemoteTripSource`, а не из CoreData. Карту предстоит
/// переделывать до 1.0, и правка обязана менять оба места сразу; форк рендера
/// не завёлся бы обратно.
///
/// Своя карта живёт в `MyMapViewModel.shared` — синглтоне, который переживает
/// переключение табов. Здесь намеренно СВОЙ экземпляр: чужой аккаунт, заехавший
/// в общий, стёр бы состояние карты владельца.
///
/// С 0.9.1 карта отвечает на нажатия, как «Атлас» (владелец 22 окт 2026):
/// регион открывается в той же шторке — числа и его поездки, — а маршрут
/// выделяется и показывает свои поездки строками. Прежний запрет («у
/// смотрящего нет прав») был неправдой: поездки здесь только публичные, и
/// профиль с лентой открывают их и так. Поездка спрашивается у сервера и
/// открывается поверх, как рекорд в чужой статистике.
struct PublicMapView: View {
    let accountId: UUID
    let ownerName: String?
    /// Ограничить карту одной машиной (0.6.4). `nil` — весь публичный след
    /// человека, как было в 0.6.3. Фильтр честный: сервер сам проверяет, что
    /// машина открыта и её карта не выключена.
    let vehicleId: UUID?
    /// Куда смотреть, пока всё грузится (0.9.1): рамка последних поездок,
    /// пришедших с профилем. `nil` — камеру поставят сами маршруты.
    let initialBounds: GeoBounds?

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @StateObject private var vm: MyMapViewModel
    @State private var summaryHeight: CGFloat = 0
    @State private var zoomLevel: MapZoomLevel = .far
    /// Поездка, которую сейчас спрашивают у сервера: индикатор в её строке и
    /// защита от второго нажатия.
    @State private var openingTripId: UUID?
    @State private var openedTrip: SocialFeedTrip?
    @State private var toastItem: ToastItem?

    init(accountId: UUID, ownerName: String?, vehicleId: UUID? = nil,
         initialBounds: GeoBounds? = nil) {
        self.accountId = accountId
        self.ownerName = ownerName
        self.vehicleId = vehicleId
        self.initialBounds = initialBounds
        _vm = StateObject(wrappedValue: MyMapViewModel(
            source: RemoteTripSource(accountId: accountId, vehicleId: vehicleId)))
    }

    /// Сколько последних поездок профиля задают рамку камеры.
    static let startTripLimit = 10

    /// Рамка камеры на время загрузки — по превью последних поездок профиля.
    /// Пустые превью не в счёт; ни одной точки — `nil`, и камеру поставят
    /// сами маршруты, когда приедут.
    nonisolated static func startBounds(previews: [[CLLocationCoordinate2D]]) -> GeoBounds? {
        GeoBounds(covering: previews.flatMap { $0 })
    }

    /// Та же пружина, что у подсостояний «Атласа».
    private static let sheetSpring = Animation.spring(response: 0.45, dampingFraction: 0.86)

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ZStack {
            MyMapRepresentable(
                exploration: vm.exploration,
                revealed: vm.revealed,
                veil: MyMapView.showsVeil ? vm.fogVeil : nil,
                vein: vm.routeVein,
                selectedRoute: vm.selectedRoute,
                selection: vm.selection,
                language: l,
                bottomOverlayHeight: summaryHeight,
                initialBounds: initialBounds,
                framesWholeRoutes: true,
                onZoomLevelChange: { zoomLevel = $0 },
                onSelectTrip: { id in animateSelection { vm.select(.trip(id)) } },
                onSelectRoad: { ids in animateSelection { vm.selectRoad(ids) } },
                // Регион открывается по пальцу, а камера едет к нему только с
                // отдаления — то же правило, что у «Атласа»: на улице промах
                // мимо дороги не повод уносить человека на весь край.
                onTapMap: { coordinate in
                    guard !vm.isLoading else { return }
                    animateSelection { vm.selectRegion(at: coordinate, zoom: zoomLevel == .far) }
                },
                cameraCommand: $vm.cameraCommand
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header(c, l)
                Spacer(minLength: 0)
                sheet(l)
                    // Высота шторки тут переменная (загрузка, отказ, пусто,
                    // числа, регион, поездки), поэтому её ВЕРХ измеряется:
                    // логотип Apple и «Legal» обязаны остаться видны над ней.
                    // Содержимое со скроллом при этом стоит на высоте ЧИСЛОМ —
                    // замер скролла уходит вниз (урок листов «Атласа»).
                    .measuredBottomOverlay($summaryHeight)
                    // Имя — на всей шторке, вместе с её полями: тесты меряют
                    // её рамку до самого низа (`PublicMapSummaryTests`).
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(sheetIdentifier)
            }
            // Машинки поверх карты при загрузке больше нет (0.9.1): посреди
            // карты значок машины читался меткой места, а не «грузится».
            // Загрузку говорит скелетон в шторке, как у «Атласа».
        }
        .navigationBarHidden(true)
        .task { await vm.loadRemote() }
        .fullScreenCover(item: $openedTrip) { trip in
            NavigationStack {
                TripDetailView(
                    tripId: trip.id,
                    viewModel: TripsViewModel(tripManager: mapVM.tripManager),
                    social: trip
                )
            }
        }
        .toast(item: $toastItem)
    }

    private func animateSelection(_ change: () -> Void) {
        withAnimation(Self.sheetSpring) { change() }
    }

    /// Чужую поездку сначала спрашивают у сервера — карточка ленты несёт
    /// автора и реакции, а у карты есть только превью. Тот же путь, что у
    /// рекорда в чужой статистике.
    private func openTrip(_ id: UUID) {
        guard openingTripId == nil else { return }
        openingTripId = id
        Task { @MainActor in
            defer { openingTripId = nil }
            do {
                let res: SocialTripResponse = try await APIClient.shared.post(
                    APIEndpoint.socialTrip,
                    body: SocialTripRequest(tripId: id, includeTrack: false),
                    requiresAuth: AuthService.shared.isSignedIn)
                openedTrip = res.item
            } catch {
                toastItem = ToastItem(type: .error, message: AppStrings.tripLoadFailed(lang.language))
            }
        }
    }

    // MARK: - Шапка

    /// Над картой — только «назад» (13 окт 2026, вариант A). Плашка с именем
    /// и подписью терракотой повторяла шторку под ней: имя дважды,
    /// «публичные» трижды, а подпись цветом действия не нажималась. Имя
    /// теперь — первая строка шторки, как «Атлас» у своей карты.
    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack(spacing: 8) {
            // Домовая кнопка, а не своя: она предпочитает `\.previewPop`
            // обычному `\.dismiss`. Внутри `PreviewNavigator` вокруг экрана
            // нет NavigationStack, и `dismiss()` там снёс бы весь
            // fullScreenCover вместо возврата в профиль.
            NavBackButton()
                .accessibilityLabel(AppStrings.back(l))
                .accessibilityIdentifier("public_map_back")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    // MARK: - Нижний лист

    /// Одна шторка на всё: сводка, регион, поездки маршрута. Две шторки на
    /// одном экране «Атлас» уже пробовал — и это была «полная жесть
    /// несоответствия» (27 сен).
    private func sheet(_ l: LanguageManager.Language) -> some View {
        Group {
            if let region = vm.selectedRegion {
                regionPanel(region, l)
            } else if let trips = selectedTrips {
                tripsPanel(trips, l)
            } else {
                summary(l)
            }
        }
        .frame(maxWidth: .infinity)
        // Down to the physical bottom: the map is full-bleed, so a sheet that
        // stops at the safe area leaves a strip of map under the home
        // indicator. Only the BACKGROUND runs into the safe area — the content
        // keeps its inset, and the sheet's top (measured for Apple's logo)
        // does not move.
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: AtlasTheme.sheetRadius, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: AtlasTheme.sheetRadius,
                style: .continuous)
            .fill(AtlasTheme.background)
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var sheetIdentifier: String {
        if vm.selectedRegion != nil { return "public_map_region" }
        if selectedTrips != nil { return "public_map_trips" }
        return "public_map_summary"
    }

    /// Поездки под пальцем: одна — у булавки или дороги одной поездки,
    /// несколько — у дороги, по которой ездили не раз.
    private var selectedTrips: [MapTripPin]? {
        if let trip = vm.selectedTrip { return [trip] }
        return vm.selectedRoad
    }

    private func closeSelection() {
        animateSelection { vm.select(nil) }
    }

    /// Регион в той же шторке, что и сводка (0.9.1): числа, города и
    /// поездки — то же содержимое, что у «Атласа». «Назад» здесь нет: на
    /// экране он уже есть и ведёт к профилю, а возвращаться, кроме сводки,
    /// некуда — это делает ×.
    private func regionPanel(_ region: MapRegionStat, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            AtlasSubstateHeader(
                title: region.localizedName(l),
                subtitle: AtlasRegionContent.subtitle(for: region, lang: l),
                backLabel: AppStrings.back(l),
                closeLabel: AppStrings.close(l),
                onBack: nil,
                onClose: { closeSelection() }
            )
            .padding(.top, 12)
            AtlasRegionContent(
                vm: vm,
                region: region,
                onOpenTrip: { openTrip($0) },
                bottomInset: 12,
                openingTripId: openingTripId
            )
            // Другой регион — другой список: «Все» и прокрутка с прошлого не
            // переезжают.
            .id(region.id)
        }
        .frame(height: Self.regionPanelHeight)
    }

    /// Высота шторки региона — ЧИСЛОМ: внутри скролл, и замер ушёл бы вниз.
    /// Та же, на которую камера «Атласа» оставляет место под регион
    /// (`MapCameraCommand.Padding.region`), но не больше половины экрана —
    /// иначе на маленьком телефоне карты над шторкой не осталось бы.
    private static var regionPanelHeight: CGFloat {
        let screen = WindowLayoutMetrics.shared.size?.height ?? 844
        return min(440, screen * 0.55)
    }

    /// Поездки маршрута: строки, как у региона, без чисел над ними — на
    /// маршрут человек уже смотрит.
    private func tripsPanel(_ trips: [MapTripPin], _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            AtlasSubstateHeader(
                title: AppStrings.atlasTripsHere(l),
                subtitle: "\(trips.count) " + AppStrings.nounTrips(l, trips.count),
                backLabel: AppStrings.back(l),
                closeLabel: AppStrings.close(l),
                onBack: nil,
                onClose: { closeSelection() }
            )
            .padding(.top, 12)
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        if index > 0 {
                            Rectangle().fill(AtlasTheme.separator)
                                .frame(height: 1).padding(.leading, 64)
                        }
                        AtlasTripRow(trip: trip, isOpening: openingTripId == trip.id) {
                            openTrip(trip.id)
                        }
                    }
                }
                .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
                .padding(.horizontal, AtlasTheme.sideInset)
                .padding(.vertical, 12)
            }
            .scrollDisabled(trips.count <= Self.visibleTripRows)
        }
        .frame(height: Self.tripsPanelHeight(count: trips.count))
    }

    /// Сколько строк видно без прокрутки; при большем числе видна ещё
    /// половина следующей — знак, что список листается.
    private static let visibleTripRows = 4

    /// Высота шторки поездок — ЧИСЛОМ, от числа строк: шапка 44 и её поле 12,
    /// поля списка 12 + 12, строки по `AtlasTripRow.height`.
    static func tripsPanelHeight(count: Int) -> CGFloat {
        let rows = count > visibleTripRows ? CGFloat(visibleTripRows) + 0.5 : CGFloat(max(count, 1))
        return 12 + 44 + 12 + rows * AtlasTripRow.height + 12
    }

    /// The same sheet and tiles as one's own «Атлас» (12 Oct 2026). It used to
    /// be a white card of its own: three centred columns split by hairlines,
    /// a grey plate inside the white, and a grab handle on a sheet that does
    /// not move — a second drawing of the question «how far has this person
    /// driven», next to the first. And the card stopped short of the bottom
    /// edge: the map behind showed through under it on every iPhone with a
    /// home indicator.
    private func summary(_ l: LanguageManager.Language) -> some View {
        VStack(spacing: 12) {
            // Первая строка шторки — чья это карта, как «Атлас» у своей
            // (`AtlasSheetTitleRow`, эррата 1). Без известного имени — «Карта».
            AtlasSheetTitleRow(title: ownerTitle(l)) { EmptyView() }
                .padding(.horizontal, -AtlasTheme.sideInset)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("public_map_title")
            if vm.isLoading {
                // Иначе сводка утверждает «0 маршрутов · 0 км · 0 регионов» про
                // другого человека всё время загрузки — то есть врёт точными
                // числами. Скелетон «Атласа» (состояние 22) отвечает «сколько
                // сейчас появится и какой формы», а строка под ним верна уже
                // сейчас — и шторка не прыгает, когда приедут числа.
                // В той же белой карточке, что тройка чисел: полоски прямо на
                // бумаге шторки почти не видны, а карточка, появляющаяся из
                // ниоткуда вместе с числами, — лишний скачок.
                SkeletonPlaceholder(shape: .atlasStats, count: 1, period: 1.2)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
                    .accessibilityIdentifier("public_map_skeleton")
                Text(AppStrings.publicMapOnlyPublic(l))
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if vm.remoteFailed && vm.exploration.trips.isEmpty {
                // Отказ загрузки — НЕ «человек ничего не опубликовал». Второе
                //утверждение о другом человеке, которого мы не проверяли.
                Text(AppStrings.publicDataLoadFailed(l))
                    .font(.inter(14, weight: .semibold))
                    .foregroundStyle(AtlasTheme.ink)
                Button { Task { await vm.loadRemote() } } label: {
                    Text(AppStrings.retry(l))
                        .font(.inter(13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            } else if vm.isEmpty {
                // Ноль публичных поездок — это пустое состояние, а не отказ
                // загрузки: человек просто ничего не опубликовал.
                Text(AppStrings.publicMapEmptyTitle(l))
                    .font(.inter(14, weight: .semibold))
                    .foregroundStyle(AtlasTheme.ink)
                Text(AppStrings.publicMapEmptyBody(l))
                    .font(.inter(11.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AtlasTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Вне итога: неизвестное имя не повод молчать о том, что
                // числа под ним занижены.
                if vm.remoteFailed {
                    Text(AppStrings.publicDataPartial(l))
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Одна карточка на три числа, как итог своего «Атласа»
                // (`AtlasStatTrio`): это один итог, прочитанный с трёх сторон.
                AtlasStatTrio(columns: summaryColumns(l))
                // Одна строка вместо подписи в плашке и абзаца с именем: имя
                // уже стоит заголовком, а «публичные» — единственное, что
                // отличает эти числа от счётчиков профиля.
                Text(AppStrings.publicMapOnlyPublic(l))
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("public_map_only_public")
            }
        }
        .padding(.horizontal, AtlasTheme.sideInset)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func ownerTitle(_ l: LanguageManager.Language) -> String {
        let name = ownerName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? AppStrings.profileMapEntryTitle(l) : name
    }

    private func summaryColumns(_ l: LanguageManager.Language) -> [AtlasStatTrio.Column] {
        let trips = vm.exploration.trips.count
        let distance = Measure.distanceParts(km: vm.exploration.totalKm, unit: distanceUnit, lang: l)
        var columns: [AtlasStatTrio.Column] = [
            .init(id: "trips", value: "\(trips)", unit: nil,
                  caption: AppStrings.tripsGenitive(l, count: trips)),
            .init(id: "distance", value: distance.value, unit: distance.unit,
                  caption: AppStrings.atlasTotalShort(l))
        ]
        // Ноль при непустых маршрутах — не число, а «мы не умеем считать
        // там»: утверждение о другом человеке, которое было бы неправдой.
        let regions = vm.exploration.regions.count
        if !Self.hidesRegions(regions: regions, trips: trips) {
            columns.append(.init(id: "regions", value: "\(regions)", unit: nil,
                                 caption: AppStrings.nounRegions(l, regions)))
        }
        return columns
    }

    /// «0 регионов» при непустых маршрутах — не ноль, а страна, которой нет в
    /// атласе регионов: тогда ячейка не показывается вовсе.
    nonisolated static func hidesRegions(regions: Int, trips: Int) -> Bool {
        regions == 0 && trips > 0
    }
}
