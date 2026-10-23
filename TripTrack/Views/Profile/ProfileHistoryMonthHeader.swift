import SwiftUI

struct ProfileHistoryMonthHeader: View {
    let month: ProfileHistoryMonth
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var unit

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 5) {
            Text(month.heading)
                .font(.interScaled(24, weight: .heavy, relativeTo: .title2))
                .tracking(-0.5).foregroundStyle(c.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("profile_month_header")
            Text(AppStrings.profileChapterSummary(
                lang.language, distance: Measure.distance(metres: month.distance, unit: unit, lang: lang.language),
                trips: month.tripCount, regions: month.regionCount))
                .font(.interScaled(13, relativeTo: .footnote)).foregroundStyle(c.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12).padding(.bottom, 4)
    }
}
