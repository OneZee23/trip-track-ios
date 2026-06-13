import Foundation

/// Single source of truth for "should this GPS segment count toward distance?".
///
/// Used by every distance/stat path so they can't diverge:
///  - the live accumulator (`TripManager.handleNewLocation`)
///  - the finalize recompute (`TripManager.updateEntityStats`)
///  - the post-trip processor (`PostTripTrackProcessor.recalculateStats`)
///  - the moving-average split (`Trip.movementSplit`)
///
/// Previously the same predicate + magic numbers were copy-pasted in all four.
enum TripDistanceGate {
    /// Max plausible vehicle speed (m/s ≈ 300 km/h). A segment implying more is a
    /// GPS teleport jump (multipath / dropout snap-back) and is excluded.
    static let maxPlausibleSpeed: Double = 83.0
    /// Absolute fallback cap (m) for segments with no usable time delta — without
    /// `dt` we can't judge implied speed, so reject anything over 1 km as a jump.
    static let maxSegmentDistance: Double = 1000.0

    /// Whether a segment covering `meters` over `dt` seconds should count.
    ///
    /// With a usable `dt` (> 0) it gates on IMPLIED SPEED, so a real sparse-GPS /
    /// dead-zone bridge (minutes apart, >1 km, but a sane speed) is KEPT while a
    /// true teleport (huge distance, tiny dt → impossible speed) is rejected.
    /// Without a usable `dt` it falls back to the absolute distance cap.
    static func isPlausibleSegment(meters: Double, dt: TimeInterval) -> Bool {
        if dt > 0 { return meters / dt <= maxPlausibleSpeed }
        return meters < maxSegmentDistance
    }
}
