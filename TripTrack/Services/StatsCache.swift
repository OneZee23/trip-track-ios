import Foundation

/// Lightweight cache for StatsView to avoid re-fetching and re-computing
/// when no trips have changed since the last computation.
///
/// Invalidation keys: tripCount + lastTripStartDate.
/// If both match, cached `[Trip]` array is returned directly.
@MainActor
enum StatsCache {
    private static var cachedTrips: [Trip] = []
    private static var cachedTripCount: Int = 0
    private static var cachedLastTripDate: Date?

    /// Returns cached trips if still valid, or nil if cache is stale.
    /// Caller should fetch fresh trips on nil and call `update(trips:count:lastDate:)`.
    static func tripsIfValid(currentCount: Int, currentLastDate: Date?) -> [Trip]? {
        guard !cachedTrips.isEmpty,
              cachedTripCount == currentCount,
              cachedLastTripDate == currentLastDate else {
            return nil
        }
        return cachedTrips
    }

    static func update(trips: [Trip], count: Int, lastDate: Date?) {
        cachedTrips = trips
        cachedTripCount = count
        cachedLastTripDate = lastDate
    }

    static func invalidate() {
        cachedTrips = []
        cachedTripCount = 0
        cachedLastTripDate = nil
    }
}
