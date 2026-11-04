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
        guard let listedTrip = repository.fetchTrips(limit: 50, offset: 0).first(where: { $0.endDate != nil }),
              let trip = repository.fetchTripDetail(id: listedTrip.id), trip.trackPoints.count >= 6 else { return }
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
        UserDefaults.standard.set(trip.id.uuidString, forKey: "debug.hiddenParts.tripId")
    }
}
#endif
