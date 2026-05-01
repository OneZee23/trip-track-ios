import Foundation

/// Drops duplicate events that fire within a configured time window per key.
///
/// Use case: BT and audio-route detectors both report a connect for the same
/// device within a few hundred ms. Before this utility the auto-trip service
/// kept a one-slot tuple `(type, name, time)` and reimplemented the check
/// inline; the dedicated type makes the rule explicit and unit-testable.
///
/// Generic over `Key` so callers can use whatever identity makes sense:
/// a string device name, a struct of `(eventType, name)`, or a sentinel for
/// global single-slot dedup.
struct TimeWindowDebouncer<Key: Hashable> {
    private var lastSeen: [Key: Date] = [:]
    let window: TimeInterval

    init(window: TimeInterval) {
        self.window = window
    }

    /// Returns true if the event should be processed. Returns false (and
    /// does NOT update the timestamp) when the same key was seen within
    /// the window. On true, the timestamp is recorded so subsequent calls
    /// inside the window will be suppressed.
    mutating func shouldProcess(_ key: Key, now: Date = Date()) -> Bool {
        if let last = lastSeen[key], now.timeIntervalSince(last) < window {
            return false
        }
        lastSeen[key] = now
        return true
    }

    mutating func reset() {
        lastSeen.removeAll()
    }
}
