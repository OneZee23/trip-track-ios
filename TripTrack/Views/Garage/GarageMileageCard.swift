import SwiftUI

struct GarageMileageCard: View {
    let odometerKm: Double
    let trackedKm: Double
    let years: [VehicleYearDistance]
    let unit: DistanceUnit
    var onEdit: (() -> Void)? = nil
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let parts = Measure.distanceParts(km: odometerKm, unit: unit, lang: l)
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.garageMileage(l)).font(.inter(16, weight: .bold)).foregroundStyle(c.text)
                .accessibilityIdentifier("garage_mileage")
            Button {
                onEdit?()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(parts.value).font(.inter(28, weight: .heavy)).foregroundStyle(c.text)
                        Text(parts.unit).font(.inter(13, weight: .semibold)).foregroundStyle(c.textSecondary)
                        Spacer(minLength: 0)
                        if onEdit != nil {
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(c.textTertiary)
                        }
                    }
                    Text(AppStrings.garageOnOdometer(l)).font(AppType.statCaption).tracking(AppType.statCaptionTracking)
                        .textCase(.uppercase).foregroundStyle(c.textTertiary)
                }.contentShape(Rectangle())
            }.buttonStyle(PressableCardStyle()).disabled(onEdit == nil)
            if !years.isEmpty { chart(c) }
            Text(AppStrings.garageTracked(l, distance: Measure.distance(km: trackedKm, unit: unit, lang: l)))
                .font(.inter(12)).foregroundStyle(c.textSecondary)
        }
        .padding(16).surfaceCard(cornerRadius: 20)
    }

    private func chart(_ c: AppTheme.Colors) -> some View {
        let maxKm = max(years.map(\.km).max() ?? 0, 1)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(years) { year in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text(Measure.distance(km: year.km, unit: unit, lang: lang.language))
                            .font(.inter(11, weight: .semibold)).foregroundStyle(c.text).lineLimit(1)
                        UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                            .fill(AppTheme.accent).frame(height: max(2, 70 * year.km / maxKm))
                        Text(String(year.year)).font(.inter(11)).foregroundStyle(c.textSecondary)
                    }.frame(
                        width: years.count <= 2
                            ? (UIScreen.main.bounds.width - 78) / CGFloat(max(1, years.count)) - 7 : 90)
                }
            }.frame(height: 110)
        }
    }
}
