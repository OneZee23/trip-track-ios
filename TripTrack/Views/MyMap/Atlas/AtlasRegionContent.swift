import SwiftUI

/// Подсостояние «Регион» внутри того же слота у нижнего края (спека, 16).
///
/// **Регион больше не открывает вторую шторку.** До 27 сентября он показывал
/// прежнюю панель 0.8.1 поверх новой, со своим радиусом, своей ручкой, своей
/// пружиной и заголовком отдельным слоем у верхнего края экрана. Два разных
/// листа на одном экране и были тем, что владелец назвал «полная жесть
/// несоответствия по UX/UI». Теперь это ОДНА шторка, которая меняет
/// содержимое, — как «Места» меняют содержимое стека, а не заводят второй.
///
/// Шапка стоит НАД скроллом: выход обязан быть на месте всегда, сколько бы
/// человек ни пролистал.
struct AtlasRegionContent: View {
    @ObservedObject var vm: MyMapViewModel
    let region: MapRegionStat
    /// «Назад» — туда, откуда пришли: в список, если регион открыли строкой,
    /// в сводку, если булавкой на карте.
    var onBack: () -> Void
    /// × — всегда в сводку.
    var onClose: () -> Void
    var onOpenTrip: (UUID) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var unit
    /// Список поездок длинный, и целиком он нужен редко: первые четыре
    /// отвечают на «когда я тут был», остальные — по просьбе.
    @State private var showsAllTrips = false

    var body: some View {
        VStack(spacing: 0) {
            AtlasSubstateHeader(
                title: region.localizedName(lang.language),
                subtitle: subtitle,
                backLabel: AppStrings.back(lang.language),
                closeLabel: AppStrings.close(lang.language),
                onBack: onBack,
                onClose: onClose
            )
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    AtlasStatTrio(columns: columns)
                    if !visitedCities.isEmpty || foggedCities > 0 { citiesSection }
                    if !vm.selectedRegionTrips.isEmpty { tripsSection }
                }
                .padding(.horizontal, AtlasTheme.sideInset)
                .padding(.bottom, CustomTabBar.clearance)
            }
        }
        .accessibilityIdentifier("atlas_region_page")
    }

    /// «Россия · с апреля 2026» — то же, что несла прежняя шапка. Страна
    /// отвечает «где это», дата — «с каких пор он мой».
    private var subtitle: String? {
        let country = RegionAtlas.shared.countryName(region.countryCode, lang.language)
            ?? region.countryCode
        guard let date = region.firstVisited else { return country }
        return country + " · " + AppStrings.mapRegionSince(lang.language, date: date)
    }

    // MARK: Тройка чисел

    private var columns: [AtlasStatTrio.Column] {
        let opened = Measure.distanceParts(km: region.openedKm, unit: unit, lang: lang.language)
        let total = Measure.distanceParts(km: region.km, unit: unit, lang: lang.language)
        return [
            .init(id: "opened", value: opened.value, unit: opened.unit,
                  caption: AppStrings.atlasNewRoads(lang.language)),
            .init(id: "total", value: total.value, unit: total.unit,
                  caption: AppStrings.atlasTotalShort(lang.language)),
            .init(id: "trips", value: "\(region.tripCount)", unit: nil,
                  caption: AppStrings.tripsGenitive(lang.language, count: region.tripCount))
        ]
    }

    // MARK: Города

    /// Чипы открытых городов и пунктирный чип «ещё N в тумане».
    ///
    /// Ссылки «все 28 ›» здесь нет: экрана списка городов ещё не существует,
    /// а нажатие, которое ничего не делает, хуже отсутствующего. Придёт
    /// вместе со своим экраном.
    private var citiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AppStrings.atlasCities(lang.language)).atlasSectionStyle()
                Spacer(minLength: 8)
                Text(AppStrings.atlasCitiesOutOf(lang.language,
                                                 visited: region.visitedCityCount,
                                                 total: region.totalCities))
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
            }
            FlowRow(spacing: 8) {
                ForEach(visitedCities) { city in
                    // Тап по городу ведёт камеру к нему — как и прежде.
                    // Выбор региона при этом НЕ снимается: человек остался в
                    // регионе и просто попросил посмотреть поближе.
                    Button {
                        Haptics.selection()
                        vm.cameraCommand = .fit(GeoBounds(around: city.coordinate, metres: 12_000),
                                                padding: .overview)
                    } label: {
                        Text(city.localizedName(lang.language))
                            .font(AppType.chip)
                            .foregroundStyle(AtlasTheme.ink)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(AtlasTheme.card, in: Capsule())
                    }
                    .buttonStyle(PressableCardStyle())
                }
                if foggedCities > 0 {
                    Text(AppStrings.atlasMoreInFog(lang.language, count: foggedCities))
                        .font(AppType.chip)
                        .foregroundStyle(AtlasTheme.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .overlay(Capsule()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(AtlasTheme.secondary.opacity(0.6)))
                }
            }
        }
    }

    private var visitedCities: [MapCityStat] { region.cities }
    private var foggedCities: Int { Swift.max(0, region.totalCities - region.visitedCityCount) }

    // MARK: Поездки

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AppStrings.atlasTripsHere(lang.language))
                    .atlasSectionStyle()
                Text("\(trips.count)")
                    .font(AppType.meta)
                    .monospacedDigit()
                    .foregroundStyle(AtlasTheme.secondary)
                Spacer(minLength: 8)
                if trips.count > 4 && !showsAllTrips {
                    Button {
                        Haptics.selection()
                        showsAllTrips = true
                    } label: {
                        HStack(spacing: 3) {
                            Text(AppStrings.mapSeeAll(lang.language, count: trips.count))
                                .font(AppType.meta)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(AtlasTheme.accent)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("atlas_region_all_trips")
                }
            }
            // ЛЕНИВЫЙ столбец: у края с тысячей поездок обычный `ForEach`
            // строил бы тысячу строк с мини-картой каждая — и до первого
            // кадра списка (урок 0.7.0).
            LazyVStack(spacing: 0) {
                ForEach(Array(shownTrips.enumerated()), id: \.element.id) { index, trip in
                    if index > 0 {
                        Rectangle().fill(AtlasTheme.separator)
                            .frame(height: 1).padding(.leading, 64)
                    }
                    tripRow(trip)
                }
            }
            .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
        }
    }

    private var trips: [MapTripPin] { vm.selectedRegionTrips }
    private var shownTrips: [MapTripPin] {
        showsAllTrips ? trips : Array(trips.prefix(4))
    }

    private func tripRow(_ trip: MapTripPin) -> some View {
        Button {
            Haptics.tap()
            onOpenTrip(trip.id)
        } label: {
            HStack(spacing: 12) {
                MapTripThumb(trip: trip, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate,
                                                 language: lang.language)
                         ?? AppStrings.tripTitle(lang.language))
                        .font(AppType.itemTitle)
                        .foregroundStyle(AtlasTheme.ink)
                        .lineLimit(1)
                    Text(tripSubtitle(trip))
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
        .accessibilityIdentifier("atlas_region_trip")
    }

    private func tripSubtitle(_ trip: MapTripPin) -> String {
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        let km = Measure.distance(metres: trip.distance, unit: unit,
                                  lang: lang.language, style: .tenths)
        return when + " · " + km
    }
}
