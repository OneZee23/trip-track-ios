import AppIntents
import Foundation

/// Surfaces "Start Trip" in the Shortcuts app + Personal Automations. The
/// motivating use case: CarPlay over Wi-Fi/USB doesn't fire our Bluetooth
/// auto-start, so multi-car users can wire a personal automation
/// ("When CarPlay connects → Start Trip with Vehicle = …") and TripTrack
/// will record without them remembering to tap Start.
///
/// `openAppWhenRun = true` so the user sees the live recording view
/// immediately — running silently in the background would lose the
/// "I'm tracking your trip" affordance.
struct StartTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Trip"
    static var description = IntentDescription(
        "Begins recording a trip in TripTrack. Optionally pick which vehicle the trip is in.",
        categoryName: "Trips"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Vehicle",
        description: "Pick which car the trip is in. Leave empty to use your currently-selected vehicle."
    )
    var vehicle: VehicleAppEntity?

    func perform() async throws -> some IntentResult {
        await TripIntentHandler.shared.handleStart(vehicleId: vehicle?.id)
        return .result()
    }
}
