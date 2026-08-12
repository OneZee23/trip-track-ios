import Foundation

/// Tracks meaningful movement during an active recording. Replaces the pair
/// of inline fields (`lastTripDistance`, `lastDistanceChangeTime`) that
/// AutoTripService used to manage by hand — the value-type wrapper lets us
/// unit-test the staleness / threshold logic in isolation, with an injected
/// clock, without dragging the whole singleton along.
///
/// Concept: every location update that grows trip distance by at least
/// `AutoTripPolicy.meaningfulMovementDistance` is "real" movement and
/// resets the inactivity clock. Anything less is drift / parking-lot
/// crawl and the clock keeps ticking. After enough idle time
/// (`isStale(threshold:)` returns true), the auto-stop machinery fires.
struct RecordingMovementTracker {
    private(set) var lastDistanceMeters: Double?
    private(set) var lastChangeTime: Date?

    /// Clear all state. Called when recording ends so the tracker is fresh
    /// for the next trip. (`AutoTripService.updateMovementForInactivity`
    /// also calls this when it sees `!vm.isRecording`.)
    mutating func reset() {
        lastDistanceMeters = nil
        lastChangeTime = nil
    }

    /// Record the current trip distance.
    /// - On first call (or after `reset()`), seeds the baseline and returns false.
    /// - On subsequent calls, returns true iff distance gained at least
    ///   `AutoTripPolicy.meaningfulMovementDistance` since the last reset.
    ///   When that happens the baseline is bumped forward.
    @discardableResult
    mutating func record(currentDistance: Double, now: Date = Date()) -> Bool {
        guard let lastDist = lastDistanceMeters, lastChangeTime != nil else {
            lastDistanceMeters = currentDistance
            lastChangeTime = now
            return false
        }
        // A shrinking odometer is not stillness — it is a different trip.
        // Re-seed instead of measuring this trip's first metres against the
        // last trip's total, which no drive can ever exceed and which would
        // read as "parked" for the whole journey.
        guard currentDistance >= lastDist else {
            lastDistanceMeters = currentDistance
            lastChangeTime = now
            return false
        }
        guard currentDistance - lastDist >= AutoTripPolicy.meaningfulMovementDistance else {
            return false
        }
        lastDistanceMeters = currentDistance
        lastChangeTime = now
        return true
    }

    /// True when the trip hasn't gained meaningful distance for at least
    /// `threshold` seconds. Returns false before the tracker has seen its
    /// first sample — staleness without a baseline is meaningless.
    func isStale(threshold: TimeInterval, now: Date = Date()) -> Bool {
        guard let lastChange = lastChangeTime else { return false }
        return now.timeIntervalSince(lastChange) > threshold
    }

    /// Push the change timestamp forward without updating the distance
    /// baseline. Used when the user dismisses an inactivity prompt with
    /// "Continue" — they explicitly chose to keep going, so don't re-prompt
    /// in another second; give them another full window before the next check.
    mutating func extendWindow(to time: Date = Date()) {
        lastChangeTime = time
    }
}
