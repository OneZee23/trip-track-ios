import CoreLocation
import Foundation

/// Checks raw positions before they can alter the smoother, route or odometer.
/// Accuracy alone cannot identify a GPS jump: interference can report 8 m
/// accuracy while moving a stationary phone hundreds of metres in one second.
struct RecordingFixContinuity {
    enum Rejection: String {
        case invalid
        case timestamp
        case speed
        case displacement
    }

    private var lastAccepted: CLLocation?

    mutating func reset() { lastAccepted = nil }

    /// A rejected fix never becomes the anchor. The next good position is
    /// compared with the last good measurement, not with the rejected jump.
    /// Long but physically possible GPS gaps remain eligible for recording.
    mutating func rejection(for fix: CLLocation) -> Rejection? {
        guard CLLocationCoordinate2DIsValid(fix.coordinate),
              fix.timestamp.timeIntervalSinceReferenceDate.isFinite,
              fix.horizontalAccuracy.isFinite,
              fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= FixGate.recordingAccuracyLimit,
              fix.speed.isFinite else { return .invalid }
        guard fix.speed <= FixGate.maxSpeedMS else { return .speed }

        if let previous = lastAccepted {
            let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { return .timestamp }
            // Permit measurement noise, including dense genuine fixes, without
            // letting two coarse 200 m fixes excuse a 400 m teleport. The
            // allowance is bounded by the existing trusted-accuracy budget.
            let uncertainty = min(TripDistanceGate.odometerAccuracyLimit,
                                  previous.horizontalAccuracy + fix.horizontalAccuracy)
            let reachable = TripDistanceGate.maxPlausibleSpeed * dt + uncertainty
            guard fix.distance(from: previous) <= reachable else { return .displacement }
        }

        lastAccepted = fix
        return nil
    }
}
