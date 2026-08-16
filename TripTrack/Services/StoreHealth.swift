import Foundation
import OSLog

private let healthLog = Logger(subsystem: "com.triptrack", category: "store-health")

/// Whether the app may touch the user's data at all.
///
/// On the launch that lost a real user's library every service came up and
/// started writing against a store that was not the user's: the settings row
/// was recreated (which is why his XP, level and streak all read zero), sync
/// recovered pending entities from an empty database, auto-trip was live. None
/// of that should run against a store the app could not open — so this gate is
/// consulted in `TripTrackApp.init` BEFORE services start, not in `body`.
///
/// The ordering is the whole design. `SettingsManager.shared` is a `static let`
/// whose `loadSettings()` inserts a fresh `UserSettingsEntity` when it finds
/// none; once that has happened it cannot be undone by a later retry, because
/// the singleton's `init` will not run again. The recovered database would then
/// carry a second settings row with zeroed progress, and `loadSettings` fetches
/// with `fetchLimit = 1` and no sort descriptor — so which one wins on the next
/// launch is undefined. Holding the services is what prevents that.
@MainActor
final class StoreHealth: ObservableObject {
    static let shared = StoreHealth()

    /// Three retries before the destructive button appears. The failures worth
    /// retrying are transient — the likeliest by far is a store that is not yet
    /// readable because the device has not been unlocked since boot, given
    /// `NSPersistentStoreFileProtectionKey` is `completeUntilFirstUserAuthentication`
    /// — and a retry costs the user one tap. Offering "start fresh" immediately
    /// would just be the old silent wipe with a confirmation attached to it.
    static let attemptsBeforeStartFresh = 3

    @Published private(set) var isOpen: Bool
    /// Counts failed load OUTCOMES, not taps. An impatient user must not be
    /// walked toward the destructive button by tapping a slow retry three
    /// times on a store whose only problem is that it is large.
    @Published private(set) var failedAttempts: Int
    @Published private(set) var isRetrying = false

    private let controller: PersistenceController

    private init(controller: PersistenceController = .shared) {
        self.controller = controller
        var open = controller.isStoreOpen
        #if DEBUG
        // `-force-store-recovery` pretends the store failed so the screen can
        // be looked at on purpose. Without it this UI is reachable only by
        // corrupting a real database, which is how a screen ships unseen.
        // The store itself is untouched, so «Повторить» genuinely succeeds.
        if Self.isForcedByLaunchArgument {
            open = false
            healthLog.notice("store recovery FORCED by launch argument")
        }
        #endif
        isOpen = open
        failedAttempts = open ? 0 : 1
        if !open {
            healthLog.fault("store did not open on launch — holding services and showing recovery")
        }
    }

    static func offersStartFresh(failedAttempts: Int) -> Bool {
        failedAttempts >= attemptsBeforeStartFresh
    }

    var offersStartFresh: Bool { Self.offersStartFresh(failedAttempts: failedAttempts) }

    /// `loadPersistentStores` runs synchronously on the main actor here — no
    /// `shouldAddStoreAsynchronously` is ever set — so a large or damaged store
    /// freezes the screen while it works. The `isRetrying` flag is what the
    /// button disables itself on; without it the screen looks dead and invites
    /// exactly the repeat taps this counter must not reward.
    func retry() {
        guard !isRetrying, !isOpen else { return }
        isRetrying = true
        defer { isRetrying = false }

        #if DEBUG
        // In the forced demo the real store is fine, so a retry would succeed
        // on the first tap and the three-failure path — the one that reveals
        // the destructive button — could never be walked. Fail until the
        // threshold, then let it through.
        if Self.isForcedByLaunchArgument, failedAttempts < Self.attemptsBeforeStartFresh {
            failedAttempts += 1
            healthLog.notice("forced recovery: simulated failure \(self.failedAttempts)")
            return
        }
        #endif

        if controller.retryLoadingStore() {
            healthLog.notice("store opened on retry after \(self.failedAttempts) failure(s)")
            isOpen = true
            AppBootstrap.startServicesOnce()
        } else {
            failedAttempts += 1
            healthLog.error("retry failed (\(self.failedAttempts) total)")
        }
    }

    /// The user's explicit choice. The old database is moved aside, never
    /// deleted — `PersistenceController.setAsideStoreAndStartFresh` keeps the
    /// journal with it, which is what makes the screen's promise true.
    func startFresh() {
        controller.setAsideStoreAndStartFresh()
        isOpen = controller.isStoreOpen
        if isOpen {
            healthLog.notice("started fresh at the user's request")
            AppBootstrap.startServicesOnce()
        }
    }

    #if DEBUG
    /// `-force-store-recovery` makes the screen reachable on purpose. It is
    /// otherwise nearly impossible to open, which is how a screen ships
    /// unlooked-at.
    static var isForcedByLaunchArgument: Bool {
        ProcessInfo.processInfo.arguments.contains("-force-store-recovery")
    }
    #endif
}

/// The services that must not run against a store the app could not open.
///
/// Idempotent because the recovery screen can succeed on the second or third
/// attempt. Starting `SyncCoordinator` twice would not crash — it would
/// duplicate its Combine subscriptions, so every sync trigger fires twice and
/// nobody notices until the log doubles.
@MainActor
enum AppBootstrap {
    private static var didStart = false

    /// - Parameter body: test seam. Production passes nothing.
    static func startServicesOnce(_ body: (() -> Void)? = nil) {
        guard !didStart else { return }
        didStart = true
        if let body {
            body()
            return
        }
        // Handle background relaunch by significant location change: iOS
        // relaunches the app after force-quit when the cell tower changes.
        AutoTripService.shared.handleBackgroundLaunch()
        SyncQueue.shared.configure(transport: APISyncTransport.shared)
        SyncCoordinator.shared.start()
        // Diagnostic — verifies our ISO date parser produces UTC-correct dates.
        ISODate.runSelfTest()
    }

    #if DEBUG
    static func resetForTesting() { didStart = false }
    #endif
}
