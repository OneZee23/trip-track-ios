import SwiftUI

struct TripsListView: View {
    @ObservedObject var viewModel: TripsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.trips.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "car.side")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Trips Yet")
                            .font(.title3.weight(.semibold))
                        Text("Start your first trip from the Tracking tab")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.trips) { trip in
                            NavigationLink(destination: TripDetailView(tripId: trip.id, viewModel: viewModel)) {
                                TripRowView(trip: trip)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteTrip(viewModel.trips[index])
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Trips")
        }
        .onAppear {
            viewModel.loadTrips()
        }
    }
}

private struct TripRowView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trip.startDate, style: .date)
                .font(.headline)
            HStack(spacing: 16) {
                Label(String(format: "%.1f km", trip.distanceKm), systemImage: "road.lanes")
                Label(trip.formattedDuration, systemImage: "clock")
                Label(String(format: "%.0f km/h", trip.maxSpeedKmh), systemImage: "speedometer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
