#if DEBUG
import Foundation

@MainActor
enum DebugHiddenPartsSeed {
    static let launchArgument = "-seed-hidden-parts"

    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(launchArgument) || arguments.contains("-seed-hidden-parts-fresh")
    }

    static func seed() {
        let repository = CoreDataTripRepository(persistenceController: .shared)
        let trips = repository.fetchTrips(limit: 500, offset: 0)
        for trip in trips where trip.endDate != nil {
            repository.seedMissingTrackPointSpeeds(for: trip.id)
        }
        guard let listedTrip = trips.first(where: { $0.endDate != nil }) else { return }
        guard let trip = repository.fetchTripDetail(id: listedTrip.id), trip.trackPoints.count >= 6 else { return }
        let start = trip.trackPoints[trip.trackPoints.count / 3].timestamp
        let end = trip.trackPoints[(trip.trackPoints.count * 2) / 3].timestamp
        let arguments = ProcessInfo.processInfo.arguments
        let parts = arguments.contains("-seed-hidden-parts-fresh")
            ? TripHiddenParts()
            : TripHiddenParts(
                startMetres: 500,
                endMetres: 1_000,
                sections: [HiddenSection(id: UUID(), from: start, to: end)],
                numbersVisibleOnly: false)
        repository.updateHiddenParts(for: trip.id, parts: parts)
        if arguments.contains("-seed-filming-mode") {
            let centre = PlaceManager.shared.places.first?.coordinate
                ?? trip.trackPoints.first?.coordinate
            if let centre {
                var home = HomeSettings.load()
                home.latitude = centre.latitude
                home.longitude = centre.longitude
                home.radius = .yard
                home.trimsPublicTracks = true
                home.save()
            }
        }
        UserDefaults.standard.set(trip.id.uuidString, forKey: "debug.hiddenParts.tripId")
    }
}
#endif
