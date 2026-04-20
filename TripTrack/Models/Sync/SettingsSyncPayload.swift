import Foundation

struct SettingsSyncPayload: Codable {
    let id: UUID
    let avatarEmoji: String
    let themeMode: String
    let language: String
    let distanceUnit: String
    let volumeUnit: String
    let fuelConsumption: Double
    let fuelPrice: Double
    let fuelCurrency: String
    let selectedVehicleId: UUID?
    let profileLevel: Int
    let profileXp: Int
    let currentStreak: Int
    let bestStreak: Int
    let lastTripDate: Date?
    let conflictVersion: Int
    let lastModifiedAt: Date
}
