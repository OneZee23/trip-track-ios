import SwiftUI

struct AtlasRegionRow: View {
    let region: MapRegionStat
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var unit

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.localizedName(lang.language))
                        .font(AppType.itemTitle).foregroundStyle(AtlasTheme.ink)
                    if let date = region.firstVisited {
                        Text(AppStrings.mapRegionSince(lang.language, date: date))
                            .font(AppType.meta).foregroundStyle(AtlasTheme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text(Measure.distance(km: region.openedKm, unit: unit, lang: lang.language))
                        .font(AppType.itemValue).foregroundStyle(AtlasTheme.accent)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AtlasTheme.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.75)
            if region.totalCities > 0 {
                HStack(spacing: 10) {
                    GeometryReader { geometry in
                        Capsule().fill(AtlasTheme.progressTrack)
                        Capsule().fill(AtlasTheme.accent)
                            .frame(width: geometry.size.width * min(1, CGFloat(region.visitedCityCount) / CGFloat(region.totalCities)))
                    }
                    .frame(height: 6)
                    Text(AppStrings.mapCitiesOfTotal(lang.language, opened: region.visitedCityCount, total: region.totalCities)
                         + " " + AppStrings.citiesGenitive(lang.language, count: region.totalCities))
                        .font(.inter(13)).foregroundStyle(AtlasTheme.secondary)
                }
            }
        }
        .padding(.vertical, 13).padding(.horizontal, 16)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
