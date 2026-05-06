import AppIntents

/// Registers TripTrack's user-invocable intents in the Shortcuts app.
/// `AppShortcutsProvider` is what makes the intents discoverable in the
/// "App Shortcuts" section without the user having to manually create a
/// shortcut first — just open Shortcuts.app and they're listed under
/// TripTrack.
struct TripTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTripIntent(),
            phrases: [
                "Start trip in \(.applicationName)",
                "Begin a trip in \(.applicationName)",
                "Record a trip in \(.applicationName)"
            ],
            shortTitle: "Start Trip",
            systemImageName: "play.circle"
        )
    }
}
