import SwiftUI

struct TripsTabView: View {
    @StateObject private var tripsVM: TripsViewModel
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    init(tripManager: TripManager) {
        _tripsVM = StateObject(wrappedValue: TripsViewModel(tripManager: tripManager))
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.tripsTab(lang.language))
                            .font(.system(size: 34, weight: .heavy))
                            .tracking(-0.5)
                            .foregroundStyle(c.text)

                        Text(AppStrings.tripsHistory(lang.language))
                            .font(.system(size: 15))
                            .foregroundStyle(c.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)

                    if tripsVM.trips.isEmpty {
                        emptyState
                    } else {
                        ForEach(tripsVM.trips) { trip in
                            NavigationLink(destination: TripDetailView(tripId: trip.id, viewModel: tripsVM)) {
                                TripCardView(trip: trip)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .background(c.bg)
            .onAppear { tripsVM.loadTrips() }
        }
    }

    private var emptyState: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 12) {
            Image(systemName: "car.side")
                .font(.system(size: 48))
                .foregroundStyle(c.textTertiary)

            Text(AppStrings.noTrips(lang.language))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(c.textSecondary)

            Text(AppStrings.startFirstTrip(lang.language))
                .font(.system(size: 14))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}
