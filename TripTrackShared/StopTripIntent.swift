import AppIntents

struct StopTripIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Trip"

    func perform() async throws -> some IntentResult {
        await TripIntentHandler.shared.handleStop()
        return .result()
    }
}
