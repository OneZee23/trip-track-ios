import SwiftUI

/// «Поездки этой машины» — экран 04 канона 0.6.4.
///
/// Приём взят у бортжурнала drive2 и переведён на нашу валюту: у них справа
/// в каждой строке деньги и пробег, у нас — километры и набор высоты. Правый
/// край списка читается сам по себе, не заглядывая в заголовки.
///
/// Сортировка — оттуда же («По теме / По дате / По лайкам»), но по нашим осям:
/// по дате, по длине, по высоте. Лайков в биографии машины нет и не будет.
struct VehicleTripsView: View {
    let vehicleId: UUID
    let vehicleName: String

    @EnvironmentObject private var lang: LanguageManager
    /// Нужен ровно за одним: `TripsViewModel` для экрана поездки. Список,
    /// из которого нельзя открыть поездку, — это витрина, а не список.
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    enum Sort: CaseIterable {
        case date, distance, elevation
    }

    @State private var trips: [Trip] = []
    @State private var sort: Sort = .date
    @State private var loaded = false
    @State private var openTripId: UUID?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            nav(c: c, l: l)
            ScrollView {
                VStack(spacing: 12) {
                    segments(c: c, l: l)
                    list(c: c, l: l)
                    Text(AppStrings.vehicleTripsPrivateNote(l))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg.ignoresSafeArea())
        // У экрана СВОЯ шапка с шевроном, поэтому системный навбар прячем —
        // иначе на экране две кнопки «назад», и непонятно, чем они разные.
        .toolbar(.hidden, for: .navigationBar)
        .task(id: vehicleId) { await load() }
        .navigationDestination(item: $openTripId) { id in
            TripDetailView(tripId: id,
                           viewModel: TripsViewModel(tripManager: mapVM.tripManager))
        }
    }

    // MARK: - Шапка

    private func nav(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            VStack(spacing: 1) {
                Text(AppStrings.vehicleTripsShort(l))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(c.text)
                Text(vehicleName)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.text)
                        // 44×44 — минимум, ниже которого палец промахивается,
                        // а VoiceOver читает «кнопка» без имени: у картинки
                        // подписи нет, и системный ярлык её не заменяет.
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(AppStrings.back(l))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    // MARK: - Сортировка

    private func segments(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 0) {
            ForEach(Sort.allCases, id: \.self) { s in
                Button {
                    Haptics.tap()
                    sort = s
                } label: {
                    Text(title(s, l))
                        .font(.system(size: 12, weight: sort == s ? .semibold : .medium))
                        .foregroundStyle(sort == s ? c.text : c.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 999)
                                .fill(sort == s ? c.card : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 999))
    }

    private func title(_ s: Sort, _ l: LanguageManager.Language) -> String {
        switch s {
        case .date:      return AppStrings.sortByDate(l)
        case .distance:  return AppStrings.sortByDistance(l)
        case .elevation: return AppStrings.sortByElevation(l)
        }
    }

    // MARK: - Список

    @ViewBuilder
    private func list(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let rows = sorted()
        if rows.isEmpty {
            Text(loaded ? AppStrings.vehicleBiographyEmpty(l) : "")
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
        } else {
            VStack(spacing: 0) {
                ForEach(0..<rows.count, id: \.self) { idx in
                    if idx > 0 { Divider().overlay(c.border) }
                    row(rows[idx], c: c, l: l)
                }
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
    }

    private func row(_ trip: Trip, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            openTripId = trip.id
        } label: {
            HStack(spacing: 10) {
                LightRoutePreview(coordinates: trip.previewCoordinates,
                                  accentColor: trip.isPrivate ? c.textTertiary : AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if trip.isPrivate {
                            // Замок, а не отсутствие строки: своя приватная поездка
                            // видна ХОЗЯИНУ и считается в его биографию.
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(c.textTertiary)
                        }
                        Text(TripRowText.title(trip, l))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(trip.isPrivate ? c.textSecondary : c.text)
                            .lineLimit(1)
                    }
                    Text(TripRowText.when(trip, l))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TripRowText.km(trip, l))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(trip.isPrivate ? c.textSecondary : c.text)
                    if trip.elevation > 0 {
                        Text(TripRowText.elevation(trip, l))
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Данные

    private func sorted() -> [Trip] {
        switch sort {
        case .date:      return trips.sorted { $0.startDate > $1.startDate }
        case .distance:  return trips.sorted { $0.distance > $1.distance }
        case .elevation: return trips.sorted { $0.elevation > $1.elevation }
        }
    }

    private func load() async {
        let id = vehicleId
        let mine = await Task.detached(priority: .userInitiated) { () -> [Trip] in
            let repo: TripRepository = CoreDataTripRepository()
            return repo.fetchTripsForMap().filter { $0.vehicleId == id && !$0.isTransfer }
        }.value
        trips = mine
        loaded = true
    }
}
