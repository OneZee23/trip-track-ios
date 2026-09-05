import SwiftUI

/// «Карта машины» — экран 05 канона 0.6.4.
///
/// НАСТОЯЩАЯ карта, а не набросок маршрутов: тот же `MyMapRepresentable`, что
/// рисует «Мою карту» и чужую, с туманом, дорожной сетью и регионами. Разница
/// между тремя картами ровно одна — массив поездок на входе, и она целиком
/// живёт в `TripSource`.
///
/// Первая версия рисовала полилинии на плоской заливке через
/// `LightRoutePreview`. На макете это читалось как карта, а на устройстве —
/// как две красные закорючки в пустоте: у превью нет ни подложки, ни
/// масштаба, ни понятия «где это вообще».
struct VehicleMapView: View {
    let vehicleId: UUID
    let vehicleName: String

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm: MyMapViewModel

    init(vehicleId: UUID, vehicleName: String) {
        self.vehicleId = vehicleId
        self.vehicleName = vehicleName
        _vm = StateObject(wrappedValue: MyMapViewModel(
            source: VehicleTripSource(vehicleId: vehicleId)))
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ZStack {
            MyMapRepresentable(
                exploration: vm.exploration,
                fog: vm.fogOverlay,
                veil: MyMapView.showsVeil ? vm.fogVeil : nil,
                selectedRoute: vm.selectedRoute,
                selection: vm.selection,
                highlightedRegionId: vm.highlightedRegionId,
                language: l,
                onZoomLevelChange: { _ in },
                onSelectTrip: { _ in },
                onSelectRoad: { _ in },
                onTapMap: { _ in },
                cameraCommand: $vm.cameraCommand
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header(c, l)
                Spacer(minLength: 0)
                summary(c, l)
            }

            if vm.isLoading { CarLoadingView() }
        }
        .navigationBarHidden(true)
        .task { await vm.loadRemote() }
    }

    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(c.text)
                    .frame(width: 36, height: 36)
                    .background(c.card, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(AppStrings.vehicleWhereWas(l))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
                Text(vehicleName)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(c.card, in: Capsule())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func summary(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let regions = vm.exploration.regions.count
        let cities = vm.exploration.regions.reduce(0) { $0 + $1.visitedCityCount }
        return Text(placesLine(regions: regions, cities: cities, l))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(c.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(c.card, in: Capsule())
            .padding(.bottom, 20)
    }

    private func placesLine(regions: Int, cities: Int, _ l: LanguageManager.Language) -> String {
        let r = "\(regions) " + AppStrings.nounRegions(l, regions)
        let c = "\(cities) " + AppStrings.nounCities(l, cities)
        return r + " · " + c
    }
}
