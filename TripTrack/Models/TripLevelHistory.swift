import Foundation

/// What level the owner was at when each trip was recorded.
///
/// A trip card in somebody's OWN list showed their CURRENT level, which is the
/// same number on all of them — the card is shared with the public feed, where
/// the level is telling you about a stranger. In your own list it says nothing
/// you do not already know.
///
/// The level at the time is a different thing entirely: open the list and the
/// drive from two years ago says LVL 3 while yesterday's says LVL 9. It is the
/// only place in the app that shows growth as a shape rather than a number.
///
/// It can be reconstructed for the whole history because `Trip.xpEarned` is
/// stamped on each trip, so the running total is a prefix sum over trips in
/// the order they happened.
enum TripLevelHistory {

    /// Level per trip id, oldest first.
    ///
    /// Returns nil when the history carries no XP at all — trips written before
    /// the field existed, or a library restored from a server that does not
    /// send it. Nil means «cannot know», which callers must show as the current
    /// level rather than as LVL 1 for everything.
    static func levels(for trips: [Trip]) -> [UUID: Int]? {
        let sorted = trips.sorted { $0.startDate < $1.startDate }
        guard sorted.contains(where: { $0.xpEarned > 0 }) else { return nil }

        var running = 0
        var result: [UUID: Int] = [:]
        result.reserveCapacity(sorted.count)
        for trip in sorted {
            // Counted BEFORE the level is read, so a trip shows the level it
            // left you at. A drive that pushes you to 4 should say 4 — that is
            // the moment worth remembering, not the level you began it on.
            running += max(0, trip.xpEarned)
            result[trip.id] = LevelSystem.level(for: running)
        }
        return result
    }
}
