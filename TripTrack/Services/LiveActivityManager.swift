import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<TripActivityAttributes>?
    private var currentAttributes: TripActivityAttributes?
    /// When the current ActivityKit activity was created. iOS ends a single Live
    /// Activity after ~8h of presentation; we recreate it before that so a long /
    /// multi-day trip keeps a live distance and working Pause/Stop on the Lock
    /// Screen. Best-effort: recreation needs the app active (Activity.request can
    /// fail when deep-backgrounded), so on a locked multi-day drive the card may
    /// still lapse until the next foreground — the in-app recording is unaffected.
    private var activityStartedAt: Date?
    private var lastUpdateDate: Date?
    private let throttleInterval: TimeInterval = 2.0
    /// Recreate the activity a little before the ~8h system cap.
    private static let maxActivityAge: TimeInterval = 7 * 3600 + 45 * 60
    /// staleDate horizon: if no update lands within this, the widget can render a
    /// "stale" treatment instead of a misleading 0.0. Generous for sparse-GPS
    /// stretches (taiga); GPS updates normally refresh it far sooner.
    private static let staleAfter: TimeInterval = 8 * 60

    /// Whether a Live Activity is currently live (used to restart it after a long
    /// pause where iOS may have ended it past the 8h cap).
    var hasActivity: Bool { currentActivity != nil }

    /// True while a near-8h recreate is in flight, so overlapping update ticks
    /// don't spawn a second (duplicate) activity.
    private var isRestarting = false

    private init() {}

    /// Keeps `currentActivity` honest: ActivityKit does NOT nil our reference when
    /// iOS ends the card itself (e.g. at the ~8h cap during a long overnight pause).
    /// Without this `hasActivity` would stay true and the resume-restart would be a
    /// no-op. Only clears state when the ENDED activity is the one we track.
    private func observeState(_ activity: Activity<TripActivityAttributes>) {
        Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    guard let self else { return }
                    if self.currentActivity?.id == activity.id {
                        self.currentActivity = nil
                        self.currentAttributes = nil
                        self.activityStartedAt = nil
                    }
                    return
                }
            }
        }
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
            return
        }

        currentActivity = nil
        currentAttributes = nil
        activityStartedAt = nil
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
                    content: .init(state: initialState, staleDate: Date().addingTimeInterval(Self.staleAfter)),
                    pushType: nil
                )
                self.currentActivity = activity
                self.currentAttributes = attributes
                self.activityStartedAt = Date()
                self.lastUpdateDate = Date()
                self.observeState(activity)
            } catch {
                #if DEBUG
                print("LiveActivity: failed to start — \(error.localizedDescription)")
                #endif
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

        // Recreate the activity before the ~8h system cap so a marathon / multi-day
        // trip keeps a live distance and working Lock-Screen buttons.
        if let startedAt = activityStartedAt,
           !isRestarting,
           Date().timeIntervalSince(startedAt) > Self.maxActivityAge,
           let attrs = currentAttributes {
            isRestarting = true
            lastUpdateDate = Date()
            Task { await self.restartActivity(attributes: attrs, state: state) }
            return
        }

        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))) }
        lastUpdateDate = Date()
    }

    /// Tears down the aging activity and starts a fresh one carrying the SAME
    /// attributes — so `startDate` (and thus the Lock-Screen timer) stays
    /// continuous — and the current state. Ends the OLD activity BY REFERENCE
    /// (not the blanket sweep) and only AFTER the new one is live, so there's no
    /// visible gap. On failure (e.g. backgrounded) the old activity is kept and
    /// we retry on the next update tick.
    private func restartActivity(attributes: TripActivityAttributes, state: TripActivityAttributes.ContentState) async {
        defer { isRestarting = false }
        let old = currentActivity
        // Already torn down before this ran — nothing to recreate.
        guard old != nil else { return }
        do {
            let fresh = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter)),
                pushType: nil
            )
            // The trip may have been STOPPED while we awaited the request above
            // (endActivity / endActivityWithSummary nils currentActivity). Don't
            // resurrect a "recording" card after stop — tear the fresh one down.
            if currentActivity == nil {
                await fresh.end(.init(state: fresh.content.state, staleDate: nil), dismissalPolicy: .immediate)
                return
            }
            currentActivity = fresh
            activityStartedAt = Date()
            observeState(fresh)
            if let old {
                await old.end(.init(state: old.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
        } catch {
            #if DEBUG
            print("LiveActivity: restart failed — \(error.localizedDescription)")
            #endif
        }
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
