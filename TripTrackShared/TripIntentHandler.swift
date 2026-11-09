import Foundation

/// Bridge between App Intents (shared code) and MapViewModel (app-only).
/// The app target sets the callbacks; the widget extension leaves them nil (intents run in app process anyway).
@MainActor
final class TripIntentHandler {
    static let shared = TripIntentHandler()

    /// The target state of the pressed button, `nil` for a card that only toggles.
    var onPause: ((Bool?) -> Void)?
    var onStop: (() -> Void)?
    /// Отметка на маршруте, поставленная кнопкой на Live Activity.
    var onCheckpoint: (() -> Void)?
    /// Fired by `StartTripIntent` (e.g. via Shortcuts personal automation
    /// "When CarPlay connects → Start Trip with vehicle X"). Optional UUID
    /// is the vehicle id to switch to before recording starts; nil keeps
    /// the currently-selected one.
    var onStart: ((UUID?) -> Void)?

    private init() {}

    func handlePause(target: Bool? = nil) {
        onPause?(target)
    }

    func handleStop() {
        onStop?()
    }

    func handleCheckpoint() {
        onCheckpoint?()
    }

    func handleStart(vehicleId: UUID?) {
        onStart?(vehicleId)
    }
}

/// Whether a Live Activity pause button changes the recording.
///
/// The card can lag behind the app: ActivityKit spaces out updates in the
/// background, so a pause made on the screen, CarPlay or the watch may still
/// show «Пауза» on the lock screen. A toggle would then resume the trip the
/// person had just paused. The button says what it showed, and a recording
/// already in that state is left alone; only an old card without a target
/// toggles, as before.
enum PauseIntentDecision {
    static func shouldToggle(target: Bool?, isPaused: Bool) -> Bool {
        guard let target else { return true }
        return target != isPaused
    }
}
