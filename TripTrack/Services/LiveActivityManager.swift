import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<TripActivityAttributes>?
    private var lastUpdateDate: Date?
    private let throttleInterval: TimeInterval = 2.0

    private init() {
        let authInfo = ActivityAuthorizationInfo()
        print("[LiveActivity] areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")

        let existing = Activity<TripActivityAttributes>.activities
        print("[LiveActivity] Found \(existing.count) orphaned activities on init")
    }

    /// Current language & dark mode — read fresh on every update
    private var currentLanguage: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    }

    private var currentIsDarkMode: Bool {
        UserDefaults.standard.bool(forKey: "liveActivityDarkMode")
    }

    // MARK: - Start

    func startActivity(tripId: UUID, startDate: Date, vehicleName: String, vehicleAvatar: String) {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            print("[LiveActivity] ⚠️ Activities DISABLED")
            return
        }

        currentActivity = nil
        lastUpdateDate = nil

        Task {
            for activity in Activity<TripActivityAttributes>.activities {
                await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }

            let attributes = TripActivityAttributes(
                tripId: tripId,
                startDate: startDate,
                vehicleName: vehicleName,
                vehicleAvatar: vehicleAvatar
            )
            let initialState = TripActivityAttributes.ContentState(
                speedKmh: 0, distanceKm: 0, isPaused: false, pausedDuration: 0,
                language: currentLanguage, isDarkMode: currentIsDarkMode
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: initialState, staleDate: nil),
                    pushType: nil
                )
                self.currentActivity = activity
                self.lastUpdateDate = Date()
                print("[LiveActivity] ✅ Started id=\(activity.id)")
            } catch {
                print("[LiveActivity] ❌ Failed: \(error)")
            }
        }
    }

    // MARK: - Update

    func updateActivity(speed: Double, distance: Double, isPaused: Bool, pausedDuration: TimeInterval, elapsedAtPause: TimeInterval? = nil) {
        guard let activity = currentActivity else { return }

        // Throttle, but always push pause state changes
        if let lastUpdate = lastUpdateDate,
           Date().timeIntervalSince(lastUpdate) < throttleInterval {
            if activity.content.state.isPaused == isPaused {
                return
            }
        }

        let state = TripActivityAttributes.ContentState(
            speedKmh: speed, distanceKm: distance, isPaused: isPaused,
            pausedDuration: pausedDuration, elapsedAtPause: elapsedAtPause,
            language: currentLanguage, isDarkMode: currentIsDarkMode
        )

        Task { await activity.update(.init(state: state, staleDate: nil)) }
        lastUpdateDate = Date()
    }

    // MARK: - End

    func endActivity() {
        // End tracked activity
        if let activity = currentActivity {
            Task {
                await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
            currentActivity = nil
            lastUpdateDate = nil
        }
        // Also end any lingering activities (e.g. finished summary still showing)
        Task {
            for activity in Activity<TripActivityAttributes>.activities {
                await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }

    func endActivityWithSummary(distance: Double, duration: String, avgSpeed: Double) {
        guard let activity = currentActivity else { return }

        let finalState = TripActivityAttributes.ContentState(
            speedKmh: 0, distanceKm: distance, isPaused: false, pausedDuration: 0,
            isFinished: true, finalDuration: duration, averageSpeedKmh: avgSpeed,
            language: currentLanguage, isDarkMode: currentIsDarkMode
        )

        Task {
            await activity.update(.init(state: finalState, staleDate: nil))
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(300)))
        }
        currentActivity = nil
        lastUpdateDate = nil
    }

    // MARK: - Cleanup

    private func endAllActivities() {
        if let activity = currentActivity {
            Task { await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate) }
            currentActivity = nil
            lastUpdateDate = nil
        }
        for activity in Activity<TripActivityAttributes>.activities {
            Task { await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate) }
        }
    }
}
