import AppIntents

struct PauseTripIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Trip"

    func perform() async throws -> some IntentResult {
        await TripIntentHandler.shared.handlePause()
        return .result()
    }
}
