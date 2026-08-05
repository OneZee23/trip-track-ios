import SwiftUI
import MapKit
import Combine
import OSLog

/// Shares the `gps` category with RealGPSProvider so watchdog restarts appear
/// inline with raw-fix diagnostics in the exported log.
private let gpsLog = Logger(subsystem: "com.triptrack", category: "gps")
/// Speed-pipeline diagnostics (raw GPS vs smoothed HUD value). `.debug` so it's
/// live-Console only — catches "speed stuck / jumps" reports during dev.
private let speedLog = Logger(subsystem: "com.triptrack", category: "speed")

@MainActor
final class MapViewModel: ObservableObject {
    // MARK: - Map State
    @Published var userTrackingMode: MKUserTrackingMode = .follow
    @Published var isDarkMap: Bool = false

    // MARK: - Recording State
    @Published var isRecording: Bool = false
    @Published var speed: Double = 0        // km/h
    @Published var altitude: Double = 0     // meters
    @Published var distance: Double = 0     // km
    @Published var duration: String = "00:00"
    @Published var gpsAccuracy: Double = 0  // meters
    /// No accepted fix for >10s while recording — the GPS pill flips to
    /// «GPS потерян» and the in-trip banner shows (Figma 494:119).
    /// Presentation-only; the 60s watchdog handles actual recovery.
    @Published var gpsSignalStale: Bool = false
    /// Location permission denied/restricted — Record idle becomes the
    /// «Нет доступа к геолокации» screen (Figma 475:119).
    @Published var locationDenied: Bool = false
    /// Launch-time recovery prompt (Figma 505:119) — a force-quit recording
    /// was found; the user picks Continue vs Finish&Save (never discard).
    @Published var showRecoveryPrompt: Bool = false
    var recoveryDistanceKm: Double = 0
    var recoveryDuration: String = "0:00"
    @Published var trackOverlays: [MKOverlay] = []
    @Published var pendingBadges: [(badge: Badge, count: Int)] = []
    @Published var showBadgeCelebration: Bool = false
    @Published var lastCompletedTrip: Trip?
    @Published var lastCompletionData: TripCompletionData?
    @Published var isPaused: Bool = false

    // Pending state for celebration-first flow
    private var pendingCompletedTrip: Trip?
    private var pendingCompletionData: TripCompletionData?
    @Published var discardedJunkTrip: Bool = false

    // MARK: - Camera (idle mode only)
    @Published var zoomDelta: Double = 0
    @Published var currentCameraDistance: Double = 1000

    private static let minCameraDistance: Double = 200
    private static let maxCameraDistance: Double = 15_000_000

    var canZoomIn: Bool { currentCameraDistance > Self.minCameraDistance }
    var canZoomOut: Bool { currentCameraDistance < Self.maxCameraDistance }

    // MARK: - Cached Stats (loaded once, refreshed on stop)
    @Published var cachedTotalKm: Double = 0
    @Published var cachedTripCount: Int = 0

    /// Reads selectedVehicleId from settings entity at recording start
    private var selectedVehicleId: UUID? {
        gamificationManager.fetchSettingsEntity()?.selectedVehicleId
    }

    // MARK: - Dependencies
    var locationManager: LocationManager
    let tripManager: TripManager
    let trackManager = SmoothTrackManager()
    let gamificationManager = GamificationManager()
    let territoryManager = TerritoryManager()
    let roadCollectionManager = RoadCollectionManager()

    private var cancellables = Set<AnyCancellable>()
    private var durationTimer: AnyCancellable?
    private var recordingStartDate: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartDate: Date?
    private var sunCheckTimer: AnyCancellable?
    private var speedDecayTimer: AnyCancellable?
    private var gpsWatchdogTimer: AnyCancellable?
    private var lastValidLocationTime: Date = .distantPast
    private var lastSpeedUpdate: Date = .distantPast
    private var smoothedSpeed: Double = 0
    private static let speedEMAAlpha: Double = 0.3
    /// Consecutive sub-floor (≈stopped OR unknown-speed) samples. Used to tell a
    /// genuine stop from a lone unknown-speed fix before snapping the HUD to 0.
    private var consecutiveZeroSpeed = 0
    private var mainTrackOverlay: MKPolyline?
    private var headOverlay: GlowingHeadOverlay?
    private var fogOverlay: FogOverlay?
    private var lastOverlayUpdate: Date = .distantPast
    /// Separate throttle for the glowing head segment, which republishes at up to
    /// 60fps (CADisplayLink). 10Hz is plenty smooth and keeps the overlay churn
    /// (and the route-blink risk) down — see the surgical overlay diff.
    private var lastHeadOverlayUpdate: Date = .distantPast
    private var fogBuilt = false

    // Fog reveal animation
    weak var fogRenderer: FogOverlayRenderer? // set by MapViewRepresentable callback
    private var fogAnimationLink: CADisplayLink?
    private var fogAnimationStart: Date?
    private static let fogAnimationDuration: Double = 0.7

    init() {
        let manager = LocationManager()
        self.locationManager = manager
        self.tripManager = TripManager(locationManager: manager)

        // Wire up Live Activity + Shortcuts intent handlers
        TripIntentHandler.shared.onPause = { [weak self] in self?.togglePause() }
        TripIntentHandler.shared.onStop = { [weak self] in
            guard let self, self.isRecording else { return }
            self.toggleRecording()
        }
        // StartTripIntent fires from the Shortcuts app / personal
        // automations. If a vehicle id was supplied we (a) persist it as the
        // selection so the garage UI reflects the automation's choice, and
        // (b) thread it straight into recording. (b) is the load-bearing part:
        // startRecording reads the vehicle from the *persisted* settings entity,
        // so relying on a bare in-memory assignment (the old bug) meant the
        // trip was stamped with the previously-saved/first car regardless of
        // what the Shortcut picked. Idempotent: if already recording, do nothing.
        TripIntentHandler.shared.onStart = { [weak self] vehicleId in
            guard let self, !self.isRecording else { return }
            if let vid = vehicleId {
                SettingsManager.shared.selectVehicle(id: vid)
            }
            self.toggleRecording(vehicleId: vehicleId)
        }
        // Hand the connectivity manager a weak self so commands from
        // the Watch hit the same control surface as on-screen taps.
        PhoneConnectivityManager.shared.mapViewModel = self

        setupRecordingBindings()
        setupSunBasedTheme()
        checkSunTheme() // Immediate check using cached location
        refreshTripStats()
        restoreActiveRecordingIfNeeded()

        // Rebuild territory when a trip is deleted. Also recompute the
        // cached trip stats — ProfileView renders cachedTripCount/TotalKm
        // directly, and without this the Я strip keeps the pre-delete
        // numbers until the Record tab happens to refresh them.
        NotificationCenter.default.publisher(for: .tripDeleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.territoryManager.rebuildFromTrips()
                self?.refreshTripStats()
            }
            .store(in: &cancellables)

        // Cloud-Sync pull can restore a whole library onto a fresh device
        // without touching stopRecording/TrackingView.onAppear — the only
        // other writers of the cached trip stats. Without this the Я tab
        // stays gated in its first-launch zero-trip state (ProfileView
        // checks cachedTripCount == 0) for the rest of the session while
        // the restored trips are already visible in the feed.
        // (MyMapViewModel documents the same restore-on-fresh-device
        // hazard for its own caches.)
        NotificationCenter.default.publisher(for: .syncPullCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshTripStats()
            }
            .store(in: &cancellables)

        // Location permission mirror for the Record screen (Figma 475:119).
        NotificationCenter.default.publisher(for: .locationAuthDenied)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let denied = note.object as? Bool else { return }
                self?.locationDenied = denied
            }
            .store(in: &cancellables)

        // Clear fog caches after territory rebuild completes (async).
        // (MyMapViewModel.shared reloads itself on the same notification.)
        NotificationCenter.default.publisher(for: .territoryRebuilt)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                FogPolygonBuilder.clearCache()
                self?.rebuildFog()
            }
            .store(in: &cancellables)

        // AutoTrip recovery rewound the entity's startDate — pull our
        // recording start in sync so the live duration timer reads
        // correctly for the rest of the trip.
        NotificationCenter.default.publisher(for: .tripStartDateBackdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let newStart = note.object as? Date else { return }
                self.recordingStartDate = newStart
                self.updateDuration()
            }
            .store(in: &cancellables)

        Task { @MainActor [tripManager, gamificationManager, territoryManager] in
            StartupTrace.mark("migrations begin")
            // Mark existing trips as processed (one-time migration)
            tripManager.migrateMarkExistingTripsProcessed()

            // Re-process all trips with spike removal (one-time v2 migration)
            tripManager.migrateReprocessTripsWithSpikeRemoval()

            // Regenerate preview polylines with correct timestamp sorting (one-time)
            tripManager.migrateRegeneratePreviewPolylines()

            // Process any trips that weren't post-processed (e.g., app killed before completion)
            let processor = PostTripTrackProcessor()
            await processor.processUnprocessedTrips()

            tripManager.backfillPreviewPolylines()
            tripManager.migrateRegionsIfNeeded()

            let allTrips = tripManager.fetchTrips()
            let settingsEntity = gamificationManager.fetchSettingsEntity()
            gamificationManager.backfillIfNeeded(trips: allTrips, settingsEntity: settingsEntity)

            territoryManager.backfillIfNeeded()
            gamificationManager.backfillBadgesIfNeeded(trips: allTrips)
            StartupTrace.mark("migrations+backfill done")
        }
    }

    // MARK: - Location

    func requestLocationPermission() {
        locationManager.startRealGPS()
    }

    func stopLocationUpdates() {
        locationManager.stopRealGPS()
    }

    // MARK: - Tracking Mode

    func cycleTrackingMode() {
        switch userTrackingMode {
        case .none:
            userTrackingMode = .follow
        case .follow:
            userTrackingMode = .followWithHeading
        case .followWithHeading:
            userTrackingMode = .none
        @unknown default:
            userTrackingMode = .none
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func zoomIn() {
        zoomDelta = 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func zoomOut() {
        zoomDelta = -1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Recording

    func toggleRecording(vehicleId: UUID? = nil) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(vehicleId: vehicleId)
        }
        // Push the new state to the Watch immediately. Without this
        // the wrist UI would stay on the prior "idle" / "recording"
        // screen until the next GPS sample lands (up to a few seconds
        // on a cold lock).
        PhoneConnectivityManager.shared.publish(
            isRecording: isRecording, isPaused: isPaused,
            speedKmh: speed, distanceKm: distance,
            elapsedSeconds: Int(recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0)
        )
    }

    func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()
        tripManager.isPaused = isPaused
        PhoneConnectivityManager.shared.publish(
            isRecording: true, isPaused: isPaused,
            speedKmh: speed, distanceKm: distance,
            elapsedSeconds: Int(recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0)
        )
        if isPaused {
            pauseStartDate = Date()
            durationTimer?.cancel()
            durationTimer = nil
        } else {
            if let pauseStart = pauseStartDate {
                pausedAccumulated += Date().timeIntervalSince(pauseStart)
                pauseStartDate = nil
            }
            durationTimer = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.updateDuration()
                }
        }
        // Update Live Activity with pause state
        var elapsed: TimeInterval?
        if isPaused, let start = recordingStartDate {
            elapsed = Date().timeIntervalSince(start) - pausedAccumulated
        }
        LiveActivityManager.shared.updateActivity(
            speed: speed,
            distance: distance,
            isPaused: isPaused,
            pausedDuration: pausedAccumulated,
            elapsedAtPause: elapsed
        )

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Recording Recovery

    /// Restore active recording if TripManager recovered an orphaned trip on launch.
    private func restoreActiveRecordingIfNeeded() {
        // Legacy safety path: an already-adopted active recording (should not
        // happen since 6.1.0 stashes orphans instead) still restores silently.
        if tripManager.isRecording, let trip = tripManager.activeTrip {
            adoptRecoveredTrip(trip, startLiveActivity: true)
            return
        }
        // 6.1.0 (Figma 505:119): a recoverable force-quit orphan raises the
        // launch prompt instead of silently resuming.
        if let orphan = tripManager.recoverableOrphan {
            recoveryDistanceKm = orphan.distance / 1000
            recoveryDuration = Self.formatRecoveryDuration(tripManager.recoverableOrphanDuration)
            showRecoveryPrompt = true
        }
    }

    /// «Продолжить запись» in the recovery prompt.
    func continueRecoveredTrip() {
        guard let trip = tripManager.adoptRecoverableOrphan() else {
            // Nothing to adopt (e.g. a BT auto-start began a NEW recording
            // while the prompt was up — the orphan stays stashed for the
            // next launch rather than corrupting the live trip).
            showRecoveryPrompt = false
            return
        }
        showRecoveryPrompt = false
        adoptRecoveredTrip(trip, startLiveActivity: true)
    }

    /// «Завершить и сохранить» — adopt, then run the normal stop pipeline
    /// (track processing, XP, summary sheet). No Live Activity is started:
    /// none is live for a never-resumed recording.
    func finishRecoveredTrip() {
        // Capture BEFORE adopt clears the stash: the trip must end at its
        // last recorded point, not at relaunch time (a 6h-old orphan would
        // otherwise gain 6h of duration and garbage XP).
        let orphanDuration = tripManager.recoverableOrphanDuration
        guard let trip = tripManager.adoptRecoverableOrphan() else {
            showRecoveryPrompt = false
            return
        }
        showRecoveryPrompt = false
        adoptRecoveredTrip(trip, startLiveActivity: false)
        let orphanEndDate = trip.startDate.addingTimeInterval(orphanDuration)
        // Let the prompt sheet finish dismissing before the stop pipeline
        // presents the badge celebration / summary — presenting during a
        // dismissal is silently dropped by SwiftUI.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.stopRecording(suggestedEndDate: orphanEndDate)
        }
    }

    private func adoptRecoveredTrip(_ trip: Trip, startLiveActivity: Bool) {
        isRecording = true
        isPaused = false
        recordingStartDate = trip.startDate
        pausedAccumulated = 0
        pauseStartDate = nil
        smoothedSpeed = 0
        // Fresh staleness baseline — background starts otherwise compare
        // against a stale lastSpeedUpdate and flash «GPS потерян».
        gpsSignalStale = false
        lastSpeedUpdate = Date()
        trackManager.reset()
        trackManager.startAnimation()

        // Recovered trips need the same lifetime timers as a fresh start — without
        // this the duration label froze and there was no GPS-stall watchdog.
        startRecordingTimers()

        if startLiveActivity {
            // Prefer the recovered trip's own vehicle over the current global
            // selection (the user may have changed it since force-quitting).
            self.startLiveActivity(tripId: trip.id, startDate: trip.startDate, vehicleId: trip.vehicleId ?? selectedVehicleId)
        }

        #if DEBUG
        print("Recording restored: trip \(trip.id), started \(trip.startDate)")
        #endif
    }

    /// Speed decay + Kalman prediction + signal-lost detection during GPS
    /// gaps. Recreated for every recording (stopRecording cancels it).
    private func startSpeedDecayTimer() {
        speedDecayTimer?.cancel()
        speedDecayTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isRecording else { return }

                // Kalman prediction: if GPS gap is active, feed predicted position to display
                if !self.isPaused, self.tripManager.kalmanFilter.isPredicting,
                   let predicted = self.tripManager.kalmanFilter.predictedLocation() {
                    self.trackManager.addPoint(predicted.coordinate)
                }

                // Signal-lost presentation: no accepted fix for >10s.
                let sinceLastFix = Date().timeIntervalSince(self.lastSpeedUpdate)
                let stale = sinceLastFix > 10
                if stale != self.gpsSignalStale { self.gpsSignalStale = stale }

                // Speed decay: if no GPS update for 2s, gradually reduce speed to 0
                guard self.speed > 0 else { return }
                if sinceLastFix > 2.0 {
                    let decayed = self.speed * 0.4
                    self.speed = decayed < 1 ? 0 : decayed
                    self.smoothedSpeed = self.speed
                }
            }
    }

    /// «0:23» — hours:minutes for the recovery chip.
    private static func formatRecoveryDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// Resolves the car (with the shared selection fallback) and starts the
    /// Lock-Screen Live Activity. Shared by fresh-start and force-quit recovery.
    private func startLiveActivity(tripId: UUID, startDate: Date, vehicleId: UUID?) {
        let vehicle = SettingsManager.shared.vehicle(for: vehicleId)
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        LiveActivityManager.shared.startActivity(
            tripId: tripId,
            startDate: startDate,
            vehicleName: vehicle?.name ?? (lang == "ru" ? "Авто" : "Car"),
            vehicleAvatar: vehicle?.avatarEmoji ?? "🚗"
        )
    }

    func startRecording(vehicleId overrideId: UUID? = nil) {
        // Re-entry guard — BT auto-trigger + notification action + manual tap
        // can all reach this method on the same MainActor tick. Without the
        // guard each call would create its own TripEntity, leaving orphans.
        guard !isRecording else { return }
        // No location permission → no recording. The idle screen shows the
        // «Нет доступа к геолокации» state with an Open-Settings slider
        // instead; this guard covers programmatic starts (BT, Shortcuts).
        guard !locationDenied else { return }
        // The recovery prompt is on screen — an auto-start (BT reconnect is
        // the CANONICAL recovery moment) would race the orphan adoption and
        // corrupt both trips. The user resolves the prompt first.
        guard !showRecoveryPrompt else { return }
        // Reset state
        isPaused = false
        tripManager.isPaused = false
        recordingStartDate = Date()
        pausedAccumulated = 0
        pauseStartDate = nil
        gpsSignalStale = false
        lastSpeedUpdate = Date()

        smoothedSpeed = 0

        // Reset track
        trackManager.reset()
        trackManager.startAnimation()
        mainTrackOverlay = nil
        headOverlay = nil

        // Rebuild fog before clearing overlays so it's included
        rebuildFog()

        // Start trip in CoreData. Prefer an explicit override (passed by the
        // Shortcuts/automation start path) over the persisted selection, so the
        // recorded trip is stamped with exactly the chosen vehicle without
        // depending on a prior persist having already landed.
        let vid = overrideId ?? selectedVehicleId
        tripManager.startTrip(vehicleId: vid)
        isRecording = true

        // Start Live Activity on Lock Screen / Dynamic Island
        startLiveActivity(
            tripId: tripManager.activeTrip?.id ?? UUID(),
            startDate: recordingStartDate ?? Date(),
            vehicleId: vid
        )

        // Simple follow mode — no zoom management
        userTrackingMode = .follow

        startRecordingTimers()

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Starts the recording-lifetime timers (1s duration label, GPS-stall watchdog,
    /// sun-theme). Shared by startRecording AND the force-quit recovery path — without
    /// this the recovered trip had a frozen duration label and, worse, NO GPS watchdog
    /// to restart tracking if CoreLocation went quiet on a long drive.
    private func startRecordingTimers() {
        durationTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDuration()
            }

        // stopRecording cancels the decay timer — recreate per recording.
        startSpeedDecayTimer()

        // GPS watchdog — restart tracking if no valid updates for 60 seconds
        lastValidLocationTime = Date()
        gpsWatchdogTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Skip while paused — a paused trip (e.g. parked overnight) is
                // *expected* to be quiet; restarting tracking there is pointless
                // battery churn. On resume the next tick handles a dead signal.
                guard let self, self.isRecording, !self.isPaused else { return }
                let silence = Date().timeIntervalSince(self.lastValidLocationTime)
                if silence > 60 {
                    gpsLog.notice("watchdog: no valid fix for \(Int(silence))s — restarting CoreLocation")
                    self.locationManager.stopTracking()
                    self.locationManager.startTracking()
                    // Give the restarted GPS a fresh 60s window to re-acquire.
                    // Without this, a genuinely dead signal (taiga, long tunnel)
                    // makes the watchdog tear down + restart CoreLocation every
                    // 30s forever — which itself prevents it from ever settling
                    // and drains the battery on exactly the long drives we care
                    // about most.
                    self.lastValidLocationTime = Date()
                }
            }

        // Sun-based theme check during recording
        sunCheckTimer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let loc = self.locationManager.currentLocation else { return }
                self.updateThemeForSun(coordinate: loc.coordinate)
            }
    }

    func stopRecording(suggestedEndDate: Date? = nil) {
        // Re-entry guard — manual Stop tap, Live Activity Stop intent, and
        // AutoTripService.autoStopTrip can all reach this method on the same
        // MainActor tick. Flip `isRecording` to false BEFORE the body runs
        // so any second concurrent call fails the guard and bails — without
        // this, `tripManager.stopTrip()` ran twice and side effects (Live
        // Activity end, gamification, junk-discard delete) executed twice.
        guard isRecording else { return }
        isRecording = false
        // Notify subscribers (Feed, Stats) regardless of which cleanup branch runs,
        // including silent junk-discard where the trip is deleted
        defer { NotificationCenter.default.post(name: .tripRecordingEnded, object: nil) }

        // Haptic immediately — before any async work, while app may still be in foreground
        let haptic = UINotificationFeedbackGenerator()
        haptic.prepare()
        haptic.notificationOccurred(.success)

        let completedTrip = tripManager.stopTrip(suggestedEndDate: suggestedEndDate)
        trackManager.stopAnimation()
        stopFogAnimation()
        isPaused = false
        tripManager.isPaused = false
        userTrackingMode = .follow
        durationTimer?.cancel()
        durationTimer = nil
        sunCheckTimer?.cancel()
        sunCheckTimer = nil
        speedDecayTimer?.cancel()
        speedDecayTimer = nil
        gpsWatchdogTimer?.cancel()
        gpsWatchdogTimer = nil
        mainTrackOverlay = nil
        headOverlay = nil
        speed = 0
        altitude = 0

        // Rebuild fog with new tiles from completed trip
        FogPolygonBuilder.clearCache()
        rebuildFog()
        distance = 0
        duration = "00:00"

        // Post-trip track processing (fill GPS gaps)
        if let trip = completedTrip {
            let processor = PostTripTrackProcessor()
            Task {
                await processor.processTrip(trip.id)
            }
        }

        if let trip = completedTrip, trip.isJunk {
            LiveActivityManager.shared.endActivity()
            tripManager.deleteTrip(id: trip.id)
            discardedJunkTrip = true
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            refreshTripStats()
            return
        }

        // Refresh cached stats after trip ends
        refreshTripStats()

        // End Live Activity with trip summary (stays on lock screen for 5 min)
        if let trip = completedTrip {
            LiveActivityManager.shared.endActivityWithSummary(
                distance: trip.distanceKm,
                duration: trip.formattedDuration,
                avgSpeed: trip.averageSpeedKmh
            )
        } else {
            LiveActivityManager.shared.endActivity()
        }

        // Process gamification — use lightweight fetch (no track points for historical trips).
        // The completedTrip already has track points from the recording session.
        if let trip = completedTrip {
            var allTrips = tripManager.fetchTrips()
            // Replace the lightweight version with the full trip (has track points)
            if let idx = allTrips.firstIndex(where: { $0.id == trip.id }) {
                allTrips[idx] = trip
            }
            let settingsEntity = gamificationManager.fetchSettingsEntity()
            let vehicleEntity = gamificationManager.fetchVehicleEntity(id: trip.vehicleId)

            let completionData = gamificationManager.processCompletedTrip(
                trip: trip,
                allTrips: allTrips,
                settingsEntity: settingsEntity,
                vehicleEntity: vehicleEntity
            )

            // Save earned badge IDs to trip entity
            let earnedIds = completionData.newBadges.map(\.id)
            tripManager.saveBadgesJSON(tripId: trip.id, badgeIds: earnedIds)

            // Process road collection
            var finalData = completionData
            finalData.roadCard = roadCollectionManager.processTrip(trip)

            // Collect badges for celebration
            pendingBadges = completionData.newBadges.map { badge in
                let count = completionData.repeatedBadgeCounts[badge.id] ?? 1
                return (badge: badge, count: count)
            }

            if !pendingBadges.isEmpty {
                // Badges earned → show celebration FIRST, then summary after dismiss
                pendingCompletedTrip = completedTrip
                pendingCompletionData = finalData
                showBadgeCelebration = true
            } else {
                // No badges → show summary directly
                lastCompletionData = finalData
                lastCompletedTrip = completedTrip
            }
        } else {
            // No trip data — shouldn't happen, but safe fallback
            lastCompletedTrip = completedTrip
        }

    }

    /// Called after badge celebration is dismissed to show the trip summary
    func showPendingSummary() {
        guard let trip = pendingCompletedTrip else { return }
        lastCompletionData = pendingCompletionData
        lastCompletedTrip = trip
        pendingCompletedTrip = nil
        pendingCompletionData = nil
    }

    func refreshTripStats() {
        let stats = tripManager.fetchTripStats()
        cachedTotalKm = stats.totalDistance / 1000.0
        cachedTripCount = stats.count
    }

    private func setupRecordingBindings() {
        // Location updates → speed + track points
        locationManager.$currentLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }

                // Skip warm-up period for speed/track, but still update watchdog timestamp
                self.lastValidLocationTime = Date()
                if self.locationManager.realGPS.isWarmingUp { return }

                let rawSpeed = max(0, update.speed)
                let speedKmh = rawSpeed < 1.0 ? 0 : rawSpeed * 3.6

                let gap = Date().timeIntervalSince(self.lastSpeedUpdate)
                if speedKmh == 0 {
                    // Sub-floor sample (<1 m/s). This is EITHER a genuine stop OR
                    // an unknown-speed fix — CLLocation.speed == -1 is clamped to
                    // 0 upstream and such fixes are deliberately KEPT in degraded
                    // GPS (tunnel/taiga). So snap the HUD to 0 only after TWO
                    // consecutive sub-floor samples: a lone unknown-speed fix
                    // among real speeds must NOT flash the speedometer 60→0→60,
                    // while a real stop still reads 0 within ~2s (vs the old
                    // ~7-fix EMA tail that showed "16 km/h at a red light").
                    self.consecutiveZeroSpeed += 1
                    if self.consecutiveZeroSpeed >= 2 {
                        self.smoothedSpeed = 0
                    } else {
                        // First sub-floor sample → fall through to the EMA so one
                        // stray unknown fix is smoothed, not snapped.
                        self.smoothedSpeed = Self.speedEMAAlpha * 0 + (1 - Self.speedEMAAlpha) * self.smoothedSpeed
                    }
                } else {
                    self.consecutiveZeroSpeed = 0
                    if gap > 3.0 {
                        // After a background/GPS gap, jump straight to the real value.
                        self.smoothedSpeed = speedKmh
                    } else {
                        let alpha = Self.speedEMAAlpha
                        self.smoothedSpeed = alpha * speedKmh + (1 - alpha) * self.smoothedSpeed
                    }
                }
                self.speed = self.smoothedSpeed
                speedLog.debug("speed: raw=\(Int(rawSpeed * 3.6))km/h hud=\(Int(self.smoothedSpeed))km/h gap=\(String(format: "%.1f", gap))s zeros=\(self.consecutiveZeroSpeed)")
                AutoTripService.shared.updateMovementForInactivity()

                self.lastSpeedUpdate = Date()
                self.altitude = update.altitude
                self.gpsAccuracy = update.horizontalAccuracy
                if self.gpsSignalStale { self.gpsSignalStale = false }

                if self.isRecording && !self.isPaused {
                    self.trackManager.addPoint(update.coordinate)
                    let isNewTile = self.territoryManager.recordVisit(coordinate: update.coordinate)

                    // Animate fog reveal when a new tile is discovered
                    if isNewTile {
                        self.rebuildFogAnimated()
                    }

                    // Update Live Activity with current tracking data
                    LiveActivityManager.shared.updateActivity(
                        speed: self.speed,
                        distance: self.distance,
                        isPaused: false,
                        pausedDuration: self.pausedAccumulated
                    )
                    // Mirror the same live state to the Watch. WCSession
                    // `updateApplicationContext` is debounced internally,
                    // safe to call every GPS tick — only the latest dict
                    // makes it to the wrist.
                    let elapsed = Int(self.recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0)
                    PhoneConnectivityManager.shared.publish(
                        isRecording: true,
                        isPaused: false,
                        speedKmh: self.speed,
                        distanceKm: self.distance,
                        elapsedSeconds: elapsed
                    )
                }
            }
            .store(in: &cancellables)

        // Speed decay + Kalman prediction during GPS gaps. Created here for
        // the first recording AND recreated by startRecordingTimers() —
        // stopRecording cancels it, so init-only creation left every trip
        // after the first without decay/Kalman/signal-lost detection.
        startSpeedDecayTimer()

        // Main track overlay (confirmed points — solid line, throttled to max 2x/sec)
        trackManager.$confirmedPoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] points in
                guard let self, self.isRecording, points.count >= 2 else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastOverlayUpdate) >= 0.5 else { return }
                self.lastOverlayUpdate = now
                var coords = points
                self.mainTrackOverlay = MKPolyline(coordinates: &coords, count: coords.count)
                self.updateTrackOverlays()
            }
            .store(in: &cancellables)

        // Head segment overlay (animated, glowing) — throttled to ~10Hz. The
        // CADisplayLink republishes head points up to 60fps; rebuilding the
        // overlay every frame floods updateUIView and (pre-fix) blinked the
        // route line. 0.1s is smooth and keeps overlay churn low.
        trackManager.$headSegmentPoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] points in
                guard let self, self.isRecording, points.count >= 2 else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastHeadOverlayUpdate) >= 0.1 else { return }
                self.lastHeadOverlayUpdate = now
                self.headOverlay = GlowingHeadOverlay(coordinates: points)
                self.updateTrackOverlays()
            }
            .store(in: &cancellables)

        // Trip distance
        tripManager.$activeTrip
            .compactMap { $0?.distanceKm }
            .receive(on: DispatchQueue.main)
            .assign(to: &$distance)
    }

    private func updateTrackOverlays() {
        var overlays: [MKOverlay] = []
        if let fog = fogOverlay { overlays.append(fog) }
        if let main = mainTrackOverlay { overlays.append(main) }
        if let head = headOverlay { overlays.append(head) }
        trackOverlays = overlays
    }

    // MARK: - Fog of War

    func rebuildFog() {
        fogOverlay = FogPolygonBuilder.build(
            visitedHashes: territoryManager.visitedGeohashes,
            visibleRect: .world
        )
        fogBuilt = true
        updateTrackOverlays()
    }

    /// Rebuild fog with animated reveal for newly discovered tiles.
    private func rebuildFogAnimated() {
        // Stop current animation — new overlay will include all pending + new tiles
        stopFogAnimation()

        guard let result = FogPolygonBuilder.buildAnimated(
            visitedHashes: territoryManager.visitedGeohashes,
            visibleRect: .world
        ) else { return }

        fogOverlay = result.overlay
        fogBuilt = true
        updateTrackOverlays()

        // Start animation if there are new tiles to reveal
        guard !result.newHashes.isEmpty else { return }
        fogAnimationStart = Date()
        startFogAnimation()
    }

    private func startFogAnimation() {
        guard fogAnimationLink == nil else { return }
        let proxy = DisplayLinkProxy { [weak self] in
            MainActor.assumeIsolated {
                self?.fogAnimationTick()
            }
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        fogAnimationLink = link
    }

    private func stopFogAnimation() {
        fogAnimationLink?.invalidate()
        fogAnimationLink = nil
        fogAnimationStart = nil
    }

    private func fogAnimationTick() {
        guard let start = fogAnimationStart, let overlay = fogOverlay else {
            stopFogAnimation()
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        let t = min(1.0, elapsed / Self.fogAnimationDuration)
        // EaseOut cubic
        let progress = 1.0 - pow(1.0 - t, 3)

        let stillAnimating = overlay.updateAnimationProgress(progress)
        fogRenderer?.setNeedsDisplay()

        if !stillAnimating {
            stopFogAnimation()
        }
    }

    /// Called by MapViewRepresentable when the map first renders.
    func handleVisibleRectChange(_ newRect: MKMapRect) {
        guard !fogBuilt else { return }
        rebuildFog()
    }

    private func updateDuration() {
        guard isRecording, let start = recordingStartDate else {
            duration = "00:00"
            return
        }
        let totalSeconds = Int(Date().timeIntervalSince(start) - pausedAccumulated)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            duration = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            duration = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // MARK: - Sun-Based Theme

    private func setupSunBasedTheme() {
        // Check once when first location arrives
        locationManager.$currentLocation
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.updateThemeForSun(coordinate: update.coordinate)
            }
            .store(in: &cancellables)
    }

    private func updateThemeForSun(coordinate: CLLocationCoordinate2D) {
        isDarkMap = SunCalculator.isNight(at: coordinate)
        UserDefaults.standard.set(isDarkMap, forKey: "liveActivityDarkMode")
    }

    func checkSunTheme() {
        if let loc = locationManager.currentLocation {
            updateThemeForSun(coordinate: loc.coordinate)
        } else if let cached = locationManager.cachedSystemLocation {
            updateThemeForSun(coordinate: cached.coordinate)
        }
    }
}
