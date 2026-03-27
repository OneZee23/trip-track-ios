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
        print("[LiveActivity] frequentPushesEnabled: \(authInfo.frequentPushesEnabled)")

        let existing = Activity<TripActivityAttributes>.activities
        print("[LiveActivity] Found \(existing.count) orphaned activities on init")
        for activity in existing {
            print("[LiveActivity]   orphan id=\(activity.id) state=\(activity.activityState)")
        }
        // Cleanup is done in startActivity() via endAllActivities() — NOT here,
        // because Task{} in init would race with startActivity() and kill the new activity.
    }

    // MARK: - Public API

    func startActivity(tripId: UUID, startDate: Date) {
        let authInfo = ActivityAuthorizationInfo()
        print("[LiveActivity] startActivity called — areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            print("[LiveActivity] ⚠️ Activities are DISABLED. User needs to enable in Settings > TripTrack > Live Activities")
            return
        }

        // End any existing activities synchronously first, then start new one
        currentActivity = nil
        lastUpdateDate = nil

        Task {
            // Await cleanup of all orphaned activities before starting
            for activity in Activity<TripActivityAttributes>.activities {
                print("[LiveActivity] Ending orphan id=\(activity.id)")
                await activity.end(
                    .init(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }

            // Now start the new activity
            let attributes = TripActivityAttributes(tripId: tripId, startDate: startDate)
            let initialState = TripActivityAttributes.ContentState(
                speedKmh: 0,
                distanceKm: 0,
                isPaused: false,
                pausedDuration: 0
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: initialState, staleDate: nil),
                    pushType: nil
                )
                self.currentActivity = activity
                self.lastUpdateDate = Date()
                print("[LiveActivity] ✅ Started activity id=\(activity.id)")
            } catch {
                print("[LiveActivity] ❌ Failed to start: \(error)")
            }
        }
    }

    func updateActivity(speed: Double, distance: Double, isPaused: Bool, pausedDuration: TimeInterval) {
        guard let activity = currentActivity else { return }

        // Throttle updates, but always push pause/stop state changes
        if let lastUpdate = lastUpdateDate,
           Date().timeIntervalSince(lastUpdate) < throttleInterval {
            let currentState = activity.content.state
            if currentState.isPaused == isPaused {
                return
            }
        }

        let state = TripActivityAttributes.ContentState(
            speedKmh: speed,
            distanceKm: distance,
            isPaused: isPaused,
            pausedDuration: pausedDuration
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }

        lastUpdateDate = Date()
    }

    func endActivity() {
        guard let activity = currentActivity else { return }

        print("[LiveActivity] Ending activity id=\(activity.id)")
        Task {
            await activity.end(
                .init(state: activity.content.state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }

        currentActivity = nil
        lastUpdateDate = nil
    }

    func endActivityWithSummary(distance: Double, duration: String, avgSpeed: Double) {
        guard let activity = currentActivity else { return }

        print("[LiveActivity] Ending with summary id=\(activity.id)")

        let finalState = TripActivityAttributes.ContentState(
            speedKmh: 0,
            distanceKm: distance,
            isPaused: false,
            pausedDuration: 0,
            isFinished: true,
            finalDuration: duration,
            averageSpeedKmh: avgSpeed
        )

        Task {
            await activity.update(.init(state: finalState, staleDate: nil))
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(300))
            )
        }

        currentActivity = nil
        lastUpdateDate = nil
    }

    // MARK: - Cleanup

    private func endAllActivities() {
        // End tracked activity
        if let activity = currentActivity {
            Task {
                await activity.end(
                    .init(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            currentActivity = nil
            lastUpdateDate = nil
        }

        // End any orphaned activities from previous sessions
        for activity in Activity<TripActivityAttributes>.activities {
            Task {
                await activity.end(
                    .init(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    private func cleanupOrphanedActivities() {
        Task {
            for activity in Activity<TripActivityAttributes>.activities {
                print("[LiveActivity] Cleaning orphan id=\(activity.id)")
                await activity.end(
                    .init(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }
}
