import Foundation

struct PublicVehicleMod: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let date: String
    let odometerKm: Double?
    let photos: [PublicVehiclePhoto]?

    var entry: VehicleMod {
        VehicleMod(id: id, title: title, date: date, odometerKm: odometerKm, photoIds: (photos ?? []).map(\.id))
    }
}
