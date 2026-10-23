import Foundation

/// Prepared once with the journal, never accumulated during a row render.
struct ProfileRoutineTrips: Identifiable {
    let trips: [Trip]
    let distance: Double
    let titleTrips: [Trip]
    var id: UUID { trips[0].id }

    init(trips: [Trip]) {
        precondition(!trips.isEmpty)
        self.trips = trips
        distance = trips.reduce(0) { $0 + $1.distance }
        var seen: Set<String> = []
        var titles: [Trip] = []
        for trip in trips {
            if seen.insert(trip.title ?? trip.region ?? "").inserted { titles.append(trip) }
            if titles.count == 3 { break }
        }
        titleTrips = titles
    }
}
