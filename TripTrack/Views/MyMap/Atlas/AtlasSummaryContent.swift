import SwiftUI

/// Содержимое шторки «Атласа»: одно на все три положения (спека §3.5).
///
/// «Содержимое одно на все положения: в сводке видна его верхняя часть, в
/// списке всё целиком со скроллом» — поэтому блок «Исследовано» здесь ровно
/// один, а не по копии на каждое состояние. Две копии одного блока разъехались
/// бы, как разъехались два таб-бара.
struct AtlasSummaryContent: View {
    @ObservedObject var vm: MyMapViewModel
    let detent: AtlasSheetDetent
    var onShare: () -> Void
    var onExplain: () -> Void
    var onOpenRegion: (String) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var unit

    var body: some View {
        switch detent {
        case .peek:
            // В подсказке видна ТОЛЬКО закреплённая строка заголовка, которую
            // рисует сама шторка. Строка «189 миль новых дорог ▴» убрана
            // эрратой 1: сводку возвращает закрытие карточки места, и второй
            // дороги к тому же результату быть не должно.
            EmptyView()
        case .collapsed:
            exploredBlock
                .padding(.horizontal, 16)
        case .expanded:
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    exploredBlock
                    // Поля поиска и строки «Поездки в атласе» здесь пока НЕТ,
                    // и это решение, а не пропуск: их экраны (состояние 14 и
                    // список поездок) ещё не собраны, а поле, которое ничего
                    // не ищет, и строка, которая никуда не ведёт, — это
                    // нажатие, которое ничего не делает, то есть хуже
                    // отсутствующего (CLAUDE.md). Вернутся вместе со своими
                    // экранами.
                    regionsSection
                    citiesSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, CustomTabBar.clearance)
            }
        }
    }

    // MARK: Исследовано

    private var exploredBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                // Тап по заголовку открывает «как мы считаем»: иконки ⓘ у
                // него нет — спека запрещает вторые подписи и пояснения.
                Button(action: onExplain) {
                    Text(exploredTitle)
                        .atlasSectionStyle()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("atlas_explored_title")

                Spacer(minLength: 8)
                shareButton
            }
            AtlasStatTrio(columns: columns)
        }
    }

    /// С выбранным периодом заголовок сам его и называет: «Исследовано
    /// 24…27 сент.». Второго места, где период назван словами, нет — на
    /// кнопке текста не бывает никогда.
    private var exploredTitle: String {
        AppStrings.atlasExplored(lang.language)
    }

    private var shareButton: some View {
        Button(action: onShare) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AtlasTheme.accentInk)
                .frame(width: 36, height: 36)
                .background(AtlasTheme.accentSoft, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.share(lang.language))
        .accessibilityIdentifier("atlas_share")
    }

    private var columns: [AtlasStatTrio.Column] {
        let roads = Measure.distanceParts(km: vm.revealed.openedKm, unit: unit, lang: lang.language)
        let total = Measure.distanceParts(km: vm.exploration.totalKm, unit: unit, lang: lang.language)
        return [
            .init(id: "roads", value: roads.value, unit: roads.unit,
                  caption: AppStrings.atlasNewRoads(lang.language), action: onExplain),
            .init(id: "total", value: total.value, unit: total.unit,
                  caption: AppStrings.atlasTotalShort(lang.language), action: onExplain),
            // Без действия: список поездок — отдельный экран, и пока его
            // нет, шеврон обещал бы переход, которого не будет.
            .init(id: "trips", value: "\(vm.exploration.tripCount)", unit: nil,
                  caption: AppStrings.tripsGenitive(lang.language, count: vm.exploration.tripCount))
        ]
    }

    // MARK: Регионы

    private var regionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(AppStrings.atlasRegions(lang.language),
                          link: "\(vm.exploration.regionCount)")
            VStack(spacing: 0) {
                ForEach(Array(vm.exploration.regions.enumerated()), id: \.element.id) { index, region in
                    if index > 0 {
                        Rectangle().fill(AtlasTheme.separator)
                            .frame(height: 1).padding(.leading, 68)
                    }
                    regionRow(region)
                }
            }
            .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
        }
    }

    private func regionRow(_ region: MapRegionStat) -> some View {
        Button { onOpenRegion(region.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AtlasTheme.accentInk)
                    .frame(width: 44, height: 44)
                    .background(AtlasTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.localizedName(lang.language))
                        .font(AppType.itemTitle)
                        .foregroundStyle(AtlasTheme.ink)
                        .lineLimit(1)
                    Text(regionSubtitle(region))
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AtlasTheme.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("atlas_region_\(region.id)")
    }

    private func regionSubtitle(_ region: MapRegionStat) -> String {
        let distance = Measure.distance(km: region.km, unit: unit, lang: lang.language)
        let cities = AppStrings.atlasCitiesOutOf(lang.language,
                                                 visited: region.cities.count,
                                                 total: region.totalCities)
        return distance + " · " + cities
    }

    // MARK: Города

    private var citiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(AppStrings.atlasCities(lang.language),
                          link: AppStrings.atlasCitiesOutOf(lang.language,
                                                            visited: vm.overview.cityCount,
                                                            total: totalCities))
            FlowRow(spacing: 8) {
                ForEach(visitedCities, id: \.id) { city in
                    Text(city.localizedName(lang.language))
                        .font(AppType.chip)
                        .foregroundStyle(AtlasTheme.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(AtlasTheme.card, in: Capsule())
                }
                if foggedCities > 0 {
                    Text(AppStrings.atlasMoreInFog(lang.language, count: foggedCities))
                        .font(AppType.chip)
                        .foregroundStyle(AtlasTheme.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(AtlasTheme.secondary.opacity(0.6)))
                }
            }
        }
    }

    private var visitedCities: [AtlasOverviewIndex.City] {
        vm.overview.cities(language: lang.language).filter(\.isVisited)
    }

    private var totalCities: Int {
        vm.exploration.regions.reduce(0) { $0 + $1.totalCities }
    }

    private var foggedCities: Int { Swift.max(0, totalCities - vm.overview.cityCount) }

    // MARK: Общее

    /// Заголовок секции и счёт справа — БЕЗ шеврона.
    ///
    /// Шеврон обещает переход, а экранов «все регионы» и «все города» ещё
    /// нет: «если нажатие что-то открывает — это видно», и обратное тоже
    /// верно — не открывает, значит и знака перехода быть не должно
    /// (CLAUDE.md). Вернётся вместе со своим экраном.
    private func sectionHeader(_ title: String, link: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).atlasSectionStyle()
            Spacer(minLength: 8)
            Text(link)
                .font(AppType.meta)
                .monospacedDigit()
                .foregroundStyle(AtlasTheme.secondary)
        }
    }
}
