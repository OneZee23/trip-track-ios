import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    /// Static data — set once when the activity starts
    var tripId: UUID
    var startDate: Date

    struct ContentState: Codable, Hashable {
        var speedKmh: Double
        var distanceKm: Double
        var isPaused: Bool
        /// Accumulated paused seconds — used to offset the timer display
        var pausedDuration: TimeInterval
    }
}
