import Foundation

/// Bridge between App Intents (shared code) and MapViewModel (app-only).
/// The app target sets the callbacks; the widget extension leaves them nil (intents run in app process anyway).
@MainActor
final class TripIntentHandler {
    static let shared = TripIntentHandler()

    var onPause: (() -> Void)?
    var onStop: (() -> Void)?

    private init() {}

    func handlePause() {
        onPause?()
    }

    func handleStop() {
        onStop?()
    }
}
