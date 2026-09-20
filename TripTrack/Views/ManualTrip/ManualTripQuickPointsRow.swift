import SwiftUI
import CoreLocation

/// Чипы «Дом» / частые места / «Точка на карте» — под полями точек, решение
/// владельца 20 сен (§2): точку можно поставить без похода в поиск.
///
/// Пустого места без домов и мест нет — чип «Точка на карте» стоит всегда,
/// «Дом» и до трёх частых мест приходят снаружи уже отфильтрованными
/// (`ManualTripFrequentPlaces`, домашняя координата — `SettingsManager
/// .homeLocation`): эта вью только рисует то, что ей дали.
struct ManualTripQuickPointsRow: View {
    let home: CLLocationCoordinate2D?
    let frequentPlaces: [Place]
    let isMapTapArmed: Bool
    let onPick: (ManualTripPoint) -> Void
    let onArmMapTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let home {
                    let title = AppStrings.manualTripChipHome(lang.language)
                    chip(icon: "house.fill", title: title) {
                        onPick(ManualTripPoint(name: title, coordinate: home))
                    }
                }
                ForEach(frequentPlaces) { place in
                    let title = place.name?.isEmpty == false
                        ? place.name! : AppStrings.placeUnnamed(lang.language)
                    chip(icon: "mappin.circle.fill", title: title) {
                        onPick(ManualTripPoint(name: title, coordinate: place.coordinate))
                    }
                }
                chip(icon: "hand.tap.fill",
                     title: AppStrings.manualTripChipMapPoint(lang.language),
                     highlighted: isMapTapArmed, action: onArmMapTap)
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("manual_trip_quick_points")
    }

    private func chip(
        icon: String, title: String, highlighted: Bool = false, action: @escaping () -> Void
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(highlighted ? .white : c.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(highlighted ? AppTheme.accent : c.cardAlt, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableCardStyle())
    }
}
