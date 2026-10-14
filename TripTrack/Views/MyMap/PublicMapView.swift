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
struct PublicMapView: View {
    let accountId: UUID
    let ownerName: String?
    /// Ограничить карту одной машиной (0.6.4). `nil` — весь публичный след
    /// человека, как было в 0.6.3. Фильтр честный: сервер сам проверяет, что
    /// машина открыта и её карта не выключена.
    let vehicleId: UUID?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @StateObject private var vm: MyMapViewModel
    @State private var summaryHeight: CGFloat = 0

    init(accountId: UUID, ownerName: String?, vehicleId: UUID? = nil) {
        self.accountId = accountId
        self.ownerName = ownerName
        self.vehicleId = vehicleId
        _vm = StateObject(wrappedValue: MyMapViewModel(
            source: RemoteTripSource(accountId: accountId, vehicleId: vehicleId)))
    }

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
                onZoomLevelChange: { _ in },
                onSelectTrip: { _ in },
                onSelectRoad: { _ in },
                // Чужие объекты не открываются: у смотрящего нет прав ни на
                // деталку поездки, ни на разбор региона.
                onTapMap: { _ in },
                cameraCommand: $vm.cameraCommand
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header(c, l)
                Spacer(minLength: 0)
                summary(l)
                    // Высота сводки тут переменная (загрузка, отказ, пусто,
                    // числа), поэтому она измеряется, а не вписана числом:
                    // логотип Apple и «Legal» обязаны остаться видны над ней.
                    .measuredBottomOverlay($summaryHeight)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("public_map_summary")
            }

            if vm.isLoading { CarLoadingView() }
        }
        .navigationBarHidden(true)
        .task { await vm.loadRemote() }
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
                // числами. Статистика этот случай уже закрывает.
                // Ничего, кроме ручки листа: `CarLoadingView` уже висит
                // оверлеем поверх карты и говорит о загрузке за нас.
                Color.clear.frame(height: 24)
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
