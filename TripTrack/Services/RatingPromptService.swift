import Foundation
import StoreKit
import UIKit

/// In-app rating prompt orchestration.
///
/// Apple's `SKStoreReviewController.requestReview` is system-throttled to
/// 3 prompts per 365 days. We add app-side guards on top so the prompt
/// only shows when the user is actually engaged:
///
///   * ≥3 completed trips — they've used the core feature, not just opened
///     the app and bounced
///   * ≥7 launches — multiple distinct sessions, not "tapped 7 things"
///   * ≥30 days since last prompt — defensive on top of Apple's quota
///     (prevents "asked twice in a row after backing out of the sheet")
///   * Triggered specifically from the post-trip summary dismissal so
///     the prompt arrives during a positive emotional moment, never
///     interrupting an active flow
///
/// State is persisted in UserDefaults (singleton, lightweight). No
/// network, no analytics — Apple owns the rating UX entirely once we
/// call `requestReview`.
enum RatingPromptService {
    private static let lastPromptKey = "com.triptrack.rating.lastPromptDate"
    private static let launchCountKey = "com.triptrack.rating.launchCount"
    private static let cooldownDays = 30
    private static let minLaunches = 7
    private static let minTrips = 3

    /// Call once per cold launch from `TripTrackApp.init()`. Each call
    /// increments the persisted counter — basis for the "is this user
    /// actually using the app?" check below.
    static func recordLaunch() {
        let d = UserDefaults.standard
        let current = d.integer(forKey: launchCountKey)
        d.set(current + 1, forKey: launchCountKey)
    }

    /// Attempts to surface the system rating sheet. No-op if any guard
    /// fails — Apple's UX guidance is "never prompt unsuited moments",
    /// so silent skip is the right behavior.
    @MainActor
    static func requestReviewIfReady(tripCount: Int) {
        guard tripCount >= minTrips else { return }
        guard UserDefaults.standard.integer(forKey: launchCountKey) >= minLaunches else { return }
        if let last = UserDefaults.standard.object(forKey: lastPromptKey) as? Date {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < Double(cooldownDays * 24 * 3600) { return }
        }
        // Find the active foreground scene to host the prompt — App
        // Store rules require the prompt to attach to a visible
        // window scene; using `keyWindow` was deprecated in iOS 15.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        guard let scene else { return }
        SKStoreReviewController.requestReview(in: scene)
        UserDefaults.standard.set(Date(), forKey: lastPromptKey)
    }
}
