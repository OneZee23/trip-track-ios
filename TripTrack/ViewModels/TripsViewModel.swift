import Foundation
import Combine

final class TripsViewModel: ObservableObject {
    @Published var trips: [Trip] = []

    private let tripManager: TripManager

    init(tripManager: TripManager) {
        self.tripManager = tripManager
    }

    func loadTrips() {
        trips = tripManager.fetchTrips()
    }

    func deleteTrip(_ trip: Trip) {
        tripManager.deleteTrip(id: trip.id)
        loadTrips()
    }

    func tripDetail(id: UUID) -> Trip? {
        tripManager.tripDetail(id: id)
    }
}
