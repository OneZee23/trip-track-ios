import Foundation

/// Bridge between App Intents (shared code) and MapViewModel (app-only).
/// The app target sets the callbacks; the widget extension leaves them nil (intents run in app process anyway).
@MainActor
final class TripIntentHandler {
    static let shared = TripIntentHandler()

    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    /// Fired by `StartTripIntent` (e.g. via Shortcuts personal automation
    /// "When CarPlay connects → Start Trip with vehicle X"). Optional UUID
    /// is the vehicle id to switch to before recording starts; nil keeps
    /// the currently-selected one.
    var onStart: ((UUID?) -> Void)?

    private init() {}

    func handlePause() {
        onPause?()
    }

    func handleStop() {
        onStop?()
    }

    func handleStart(vehicleId: UUID?) {
        onStart?(vehicleId)
    }
}
