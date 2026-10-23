import SwiftUI

struct ProfileRoutineTripsView: View {
    let group: ProfileRoutineTrips
    let onOpen: (Trip) -> Void
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var unit
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false
    @State private var showsAll = false

    private var trips: [Trip] { group.trips }
    private var colors: AppTheme.Colors { AppTheme.colors(for: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                ForEach(showsAll ? trips : Array(trips.prefix(7))) { trip in compactRow(trip) }
                if !showsAll && trips.count > 7 { moreButton }
            }
        }.surfaceCard(cornerRadius: 16)
    }

    private var header: some View {
        Button {
            Haptics.selection()
            expanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34).background(colors.cardAlt, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.profileRoutineCount(lang.language, count: trips.count) + " · "
                         + Measure.distance(metres: group.distance, unit: unit, lang: lang.language))
                        .font(.interScaled(15, weight: .semibold, relativeTo: .subheadline)).foregroundStyle(colors.text)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.85)
                    Text(titles).font(.interScaled(13, relativeTo: .footnote)).foregroundStyle(colors.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(colors.textTertiary)
            }.foregroundStyle(colors.text).padding(14).contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("profile_routine_toggle")
        .accessibilityValue(expanded ? AppStrings.historySectionsExpanded(lang.language) : AppStrings.historySectionsCollapsed(lang.language))
    }

    private func compactRow(_ trip: Trip) -> some View {
        Button { Haptics.tap(); onOpen(trip) } label: {
            HStack(spacing: 8) {
                Text(title(trip)).foregroundStyle(colors.text).lineLimit(1)
                Text(ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language))
                    .font(.interScaled(12, relativeTo: .caption)).foregroundStyle(colors.textTertiary)
                Spacer(minLength: 0)
                Text(Measure.distance(metres: trip.distance, unit: unit, lang: lang.language))
                    .font(.interScaled(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(colors.text)
            }
            .font(.interScaled(14, relativeTo: .subheadline))
            .frame(minHeight: 44).contentShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(colors.border).frame(height: 1) }
        }
        .buttonStyle(PressableCardStyle()).accessibilityIdentifier("profile_routine_trip_\(trip.id)")
        .padding(.horizontal, 14)
    }

    private var moreButton: some View {
        Button { Haptics.selection(); showsAll = true } label: {
            Text(AppStrings.profileMoreTrips(lang.language, count: trips.count - 7))
                .font(.interScaled(14, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(AppTheme.accent).frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(PressableCardStyle()).accessibilityIdentifier("profile_routine_more")
    }

    private func title(_ trip: Trip) -> String {
        TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language)
            ?? RegionDisplay.localized(trip.region, language: lang.language)
            ?? ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language)
    }
    private var titles: String { group.titleTrips.map(title).joined(separator: ", ") }
}
