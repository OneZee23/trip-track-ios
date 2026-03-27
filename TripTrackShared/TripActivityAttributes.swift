import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    /// Static data — set once when the activity starts
    var tripId: UUID
    var startDate: Date
    var vehicleName: String
    var vehicleAvatar: String  // "pixel_car_orange" for image, or emoji like "🚗"

    struct ContentState: Codable, Hashable {
        var speedKmh: Double
        var distanceKm: Double
        var isPaused: Bool
        var pausedDuration: TimeInterval
        var elapsedAtPause: TimeInterval?
        var isFinished: Bool = false
        var finalDuration: String?
        var averageSpeedKmh: Double?
        /// Dynamic — updates when user switches language in app
        var language: String = "en"
        /// Dynamic — follows map dark mode (sun-based)
        var isDarkMode: Bool = false

        var isRu: Bool { language == "ru" }
    }
}
