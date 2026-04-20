import Foundation

struct VehicleSyncPayload: Codable {
    let id: UUID
    let name: String
    let avatarEmoji: String
    let odometerKm: Double
    let level: Int
    let stickersJson: String?
    let cityConsumption: Double
    let highwayConsumption: Double
    let fuelPrice: Double
    let conflictVersion: Int
    let lastModifiedAt: Date
}
