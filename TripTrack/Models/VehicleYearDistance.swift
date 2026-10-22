import Foundation

struct VehicleYearDistance: Identifiable, Equatable {
    let year: Int
    let km: Double
    var id: Int { year }

    static func aggregate(_ trips: [Trip], vehicleID: UUID, calendar: Calendar = .current) -> [VehicleYearDistance] {
        var years: [Int: Double] = [:]
        for trip in trips where trip.vehicleId == vehicleID && !trip.isTransfer && trip.confirmation == .confirmed {
            years[calendar.component(.year, from: trip.startDate), default: 0] += trip.scoringKm
        }
        return years.sorted { $0.key < $1.key }.map { VehicleYearDistance(year: $0.key, km: $0.value) }
    }
}
