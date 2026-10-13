import Foundation

/// Snapshot of the result a stop would produce, including the same tail trim
/// and trusted-point odometer used by TripManager.stopTrip. Opening or leaving
/// the confirmation never pauses or changes the recording.
struct RecordingFinishPreview {
    let tripID: UUID
    let endDate: Date
    let distance: Double
    let duration: TimeInterval
    let maxSpeed: Double

    var discardReason: TripJunkClassifier.Reason? {
        TripJunkClassifier.reason(distanceMeters: distance, durationSeconds: duration, maxSpeedMS: maxSpeed)
    }

    /// Time and GPS continue while the question is open. If the outcome has
    /// changed, show the new question before accepting the irreversible tap.
    func confirmsSameOutcome(as current: RecordingFinishPreview) -> Bool {
        tripID == current.tripID && discardReason == current.discardReason
    }

    var formattedDuration: String {
        let total = Int(max(0, duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
