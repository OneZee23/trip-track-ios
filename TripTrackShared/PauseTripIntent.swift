import AppIntents

struct PauseTripIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Trip"

    /// What the pressed button showed: `true` is «Пауза», `false` is «Продолжить».
    /// `nil` is a card drawn by a build before 0.9.4, whose button only toggled.
    @Parameter(title: "Pause")
    var pause: Bool?

    init() {}

    init(pause: Bool) {
        self.pause = pause
    }

    func perform() async throws -> some IntentResult {
        await TripIntentHandler.shared.handlePause(target: pause)
        return .result()
    }
}
