import Foundation

struct UserSettings {
    var avatarEmoji: String
    var themeMode: String   // "dark", "light", "system"
    var language: String    // "ru", "en"
    var fuelConsumption: Double  // liters per 100km
    var fuelPrice: Double        // per liter
    var selectedVehicleId: UUID?

    static let `default` = UserSettings(
        avatarEmoji: "🏎️",
        themeMode: "dark",
        language: "ru",
        fuelConsumption: 7.8,
        fuelPrice: 56.0,
        selectedVehicleId: nil
    )
}
