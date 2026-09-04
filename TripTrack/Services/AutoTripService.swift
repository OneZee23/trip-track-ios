import Foundation
import UserNotifications
import CoreLocation
import UIKit
import OSLog

/// Auto-detect debug log. Goes through `com.triptrack` subsystem so
/// `DebugLogExporter` picks it up in user-shared diagnostic bundles. Every
/// state transition and decision branch logs at `.notice` so we can replay
/// the entire sequence post-hoc when a user reports a bug from days ago.
private let autoLog = Logger(subsystem: "com.triptrack", category: "auto-trip")

@MainActor
final class AutoTripService: ObservableObject {
    static let shared = AutoTripService()

    let bluetoothDetector = BluetoothDetector()
    let audioRouteDetector = AudioRouteDetector()
    let motionDetector = MotionDetector()

    private weak var mapViewModel: MapViewModel?
    private let notificationManager = NotificationManager.shared
    private let settings = SettingsManager.shared

    private var autoStopTimer: Timer?
    private var notificationObservers: [Any] = []
    private var keepAliveLocationManager: CLLocationManager?
    private var keepAliveDelegate: KeepAliveLocationDelegate?

    private enum EventType { case connected, disconnected }
    private struct EventKey: Hashable {
        let type: EventType
        let name: String
    }
    private var eventDebouncer = TimeWindowDebouncer<EventKey>(
        window: AutoTripPolicy.eventDeduplicationWindow
    )

    private init() {
        setupDetectors()
        setupNotificationObservers()
    }

    deinit {
        // Defensive — observer tokens stored in `notificationObservers`
        // need explicit removal even though `addObserver(forName:queue:using:)`
        // captures `[weak self]`. Without this, the closures stay registered
        // for the process lifetime if AutoTripService ever becomes instance-
        // based instead of a singleton.
        for token in notificationObservers {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = foregroundRetryObserver {
            NotificationCenter.default.removeObserver(token)
        }
        autoStopTimer?.invalidate()
    }

    // MARK: - Setup

    func configure(mapViewModel: MapViewModel) {
        self.mapViewModel = mapViewModel
        // Replay queued automotive detection from background launch
        if pendingAutomotiveDetection {
            pendingAutomotiveDetection = false
            handleAutomotiveDetected()
        }
    }

    func startIfNeeded() {
        guard settings.autoRecordMode != .off else {
            stopMonitoring()
            return
        }

        // Ensure notification permissions are granted
        notificationManager.requestAuthorization { _ in }

        startMonitoring()
    }

    private var isMonitoringActive = false

    func startMonitoring() {
        // Idempotence guard — `ContentView.onAppear` calls
        // `startIfNeeded()` every reappear, and several Settings flows
        // also fire it. Without this, each call stacked another set of
        // selector observers in `AudioRouteDetector` (which uses the
        // `selector:` API that doesn't dedupe), and re-armed BLE / motion
        // monitoring redundantly. First call wins; subsequent calls
        // no-op until `stopMonitoring`.
        guard !isMonitoringActive else {
            autoLog.notice("[auto.monitor_start.skip] reason=already_active")
            return
        }
        isMonitoringActive = true
        autoLog.notice("[auto.monitor_start] mode=\(self.settings.autoRecordMode.rawValue, privacy: .public)")
        bluetoothDetector.startMonitoring()
        audioRouteDetector.startMonitoring()
        motionDetector.startLiveUpdates()
        startKeepAlive()
    }

    func stopMonitoring() {
        guard isMonitoringActive else { return }
        isMonitoringActive = false
        autoLog.notice("[auto.monitor_stop]")
        bluetoothDetector.stopMonitoring()
        audioRouteDetector.stopMonitoring()
        motionDetector.stopLiveUpdates()
        cancelAutoStopTimer()
        stopKeepAlive()
    }

    /// Whether a background launch detected automotive activity (queued for when mapViewModel is ready)
    private var pendingAutomotiveDetection = false

    /// Called when app is launched in background by significant location change
    func handleBackgroundLaunch() {
        guard settings.autoRecordMode != .off else { return }

        motionDetector.queryRecentAutomotive { [weak self] isAutomotive in
            guard let self, isAutomotive else { return }
            if self.mapViewModel != nil {
                self.handleAutomotiveDetected()
            } else {
                // mapViewModel not configured yet — queue for when configure() is called
                self.pendingAutomotiveDetection = true
            }
        }
    }

    // MARK: - Keep-alive via Significant Location Change

    private func startKeepAlive() {
        guard keepAliveLocationManager == nil else { return }
        guard CLLocationManager.authorizationStatus() == .authorizedAlways else { return }

        let delegate = KeepAliveLocationDelegate { [weak self] in
            // Woken by significant location change — check for automotive activity
            self?.motionDetector.queryRecentAutomotive { isAutomotive in
                guard isAutomotive else { return }
                self?.handleAutomotiveDetected()
            }
        }
        let manager = CLLocationManager()
        manager.delegate = delegate
        manager.startMonitoringSignificantLocationChanges()
        keepAliveLocationManager = manager
        keepAliveDelegate = delegate
    }

    private func stopKeepAlive() {
        keepAliveLocationManager?.stopMonitoringSignificantLocationChanges()
        keepAliveLocationManager = nil
        keepAliveDelegate = nil
    }

    // MARK: - Automotive Detection (from CMMotion)

    private var lastTripTriggerTime: Date?
    /// Prevents re-sending remind notification while the same driving session continues
    private var hasRemindedForCurrentTrip = false
    /// Timestamp of the last `automotive → not automotive` transition. Used to detect
    /// when a new driving session starts (long gap → treat next `automotive` as a new session).
    private var lastAutomotiveEndTime: Date?
    private var foregroundRetryObserver: Any?

    private func handleAutomotiveDetected() {
        guard let vm = mapViewModel else {
            autoLog.notice("[auto.detected.skip] reason=no_view_model")
            return
        }

        let lastEndAgo = lastAutomotiveEndTime.map { Int(Date().timeIntervalSince($0)) }
        autoLog.notice("[auto.detected] mode=\(self.settings.autoRecordMode.rawValue, privacy: .public) isRecording=\(vm.isRecording, privacy: .public) hasReminded=\(self.hasRemindedForCurrentTrip, privacy: .public) lastAutomotiveEnd_s_ago=\(lastEndAgo.map(String.init) ?? "nil", privacy: .public)")

        // If a trip is already recording but it's been parked > staleTripTimeout,
        // this automotive event is the start of a *new* session — finish the
        // stale one before triggering. Without this, a previous trip whose
        // background auto-stop never fired (Timer.scheduledTimer doesn't run
        // while the app is suspended) silently absorbs the next drive.
        //
        // Only auto-split in `.auto` mode. In `.remind`/`.off` silently ending
        // the current recording would violate "ask first"; the user will see
        // the stale trip still active in the UI and can finalize it manually
        // (consistent with `recoverStaleTripIfNeeded`).
        if vm.isRecording {
            let stale = isStaleByMovement
            guard settings.autoRecordMode == .auto, stale else {
                autoLog.notice("[auto.detected.skip] reason=already_recording mode=\(self.settings.autoRecordMode.rawValue, privacy: .public) stale_15min=\(stale, privacy: .public)")
                return
            }
            autoLog.notice("[auto.detected.split_session] reason=stale_recording_in_auto_mode")
            cancelAutoStopTimer()
            autoStopTrip()
        }

        // Don't re-remind for the same driving session
        if settings.autoRecordMode == .remind && hasRemindedForCurrentTrip {
            autoLog.notice("[auto.detected.skip] reason=already_reminded_this_session")
            return
        }

        // Deduplicate: BT + Motion can fire together within milliseconds
        if let last = lastTripTriggerTime,
           Date().timeIntervalSince(last) < AutoTripPolicy.triggerDeduplicationWindow {
            autoLog.notice("[auto.detected.skip] reason=dedup_window since_last_s=\(Int(Date().timeIntervalSince(last)), privacy: .public)")
            return
        }
        lastTripTriggerTime = Date()

        // Check if BT audio route matches a saved device → select vehicle
        if let btDevice = audioRouteDetector.currentBluetoothOutput(),
           let vehicleId = settings.vehicleId(forDeviceName: btDevice) {
            settings.selectedVehicleId = vehicleId
            settings.saveSettings()
        }

        // Try to recover the real trip start time from CMMotion history.
        // The query is async (~seconds), so re-check `vm.isRecording` inside
        // the callback — the user may have manually started recording in
        // that window and we'd otherwise fire a redundant "you're in the
        // car" notification on top of an already-running trip.
        motionDetector.queryAutomotiveStartTime { [weak self] automotiveStartDate in
            guard let self else { return }
            guard !vm.isRecording else { return }
            let deviceName = self.audioRouteDetector.currentBluetoothOutput()
                ?? AppStrings.car(LanguageManager.currentLanguage)
            self.triggerTripStart(vm: vm, deviceName: deviceName, estimatedStartDate: automotiveStartDate)
        }
    }

    // MARK: - Inactivity Auto-stop (distance-based)

    private var movementTracker = RecordingMovementTracker()

    /// Called from `MapViewModel` on every published location update to track
    /// real movement. Uses `RecordingMovementTracker` to gate on actual
    /// distance growth instead of speed (the old EMA-on-GPS-speed approach
    /// kept resetting on noisy readings during long stops in city centers).
    func updateMovementForInactivity() {
        // A MANUALLY PAUSED trip must never be auto-stopped — the user intentionally
        // paused (e.g. overnight). Treat paused like "no active tracking": reset the
        // tracker so the inactivity window restarts fresh on resume, and bail.
        guard let vm = mapViewModel, vm.isRecording, !vm.isPaused,
              let distance = vm.tripManager.activeTrip?.distance else {
            // Tracker is reused across recordings; clear it when none is active.
            movementTracker.reset()
            return
        }

        // Returns true on meaningful gain (>=100m); the tracker resets its
        // internal clock and we can bail. False means we're still in the
        // same idle window — check whether it's overstayed.
        if movementTracker.record(currentDistance: distance) { return }

        // Inactivity prompts only fire in `.auto` mode. In `.remind` and
        // `.off` the user opted out of automatic management; if they started
        // manually they expect to stop manually. The tracker still stays
        // populated for `recoverStaleTripIfNeeded`, which IS active in all
        // modes since a 15+ min frozen trip is junk regardless.
        guard settings.autoRecordMode == .auto,
              movementTracker.isStale(threshold: AutoTripPolicy.inactivityTimeout) else { return }
        let timeout = settings.autoStopTimeout
        notificationManager.sendTripStopPrompt(minutes: timeout, reason: .inactivity)
        startAutoStopTimer(minutes: timeout)
        // Re-arm the window so we don't re-trigger every location update
        // until the next full inactivity stretch.
        movementTracker.extendWindow()
    }

    /// Called from `didBecomeActive` to recover from the case where the app
    /// was suspended past the inactivity window — `Timer.scheduledTimer`
    /// doesn't fire while suspended, so a trip that idled 30+ minutes in
    /// background ends up still recording when the user re-opens the app.
    private func recoverStaleTripIfNeeded() {
        // Only auto-end stale trips in `.auto` mode. In `.remind` and `.off`
        // the user opted out of automatic management — silently ending their
        // trip on foreground entry would feel like the app stole their data.
        // They'll see the trip is still recording and can stop it manually.
        guard settings.autoRecordMode == .auto else {
            autoLog.notice("[auto.recover_stale.skip] reason=mode=\(self.settings.autoRecordMode.rawValue, privacy: .public)")
            return
        }
        guard let vm = mapViewModel, vm.isRecording, !vm.isPaused else { return }
        guard movementTracker.isStale(threshold: AutoTripPolicy.staleTripTimeout) else {
            autoLog.notice("[auto.recover_stale.skip] reason=not_stale")
            return
        }
        autoLog.notice("[auto.recover_stale.fire] reason=foreground_entry_stale_trip")
        autoStopTrip()
    }

    // MARK: - Unified Trip Trigger

    private func triggerTripStart(vm: MapViewModel, deviceName: String, estimatedStartDate: Date? = nil) {
        // Defence-in-depth: every caller already gates on `!vm.isRecording`
        // up the stack, but those checks happen before async hops (motion
        // query, dispatch barriers). One last guard here so a slow callback
        // never sends an "are you in the car?" prompt while a trip is
        // already running.
        guard !vm.isRecording else {
            autoLog.notice("[auto.trip_start.skip] reason=already_recording device=\"\(deviceName, privacy: .public)\"")
            return
        }
        let isInForeground = UIApplication.shared.applicationState == .active
        autoLog.notice("[auto.trip_start] mode=\(self.settings.autoRecordMode.rawValue, privacy: .public) foreground=\(isInForeground, privacy: .public) device=\"\(deviceName, privacy: .public)\" hasEstimatedStart=\(estimatedStartDate != nil, privacy: .public)")

        // Request background task to prevent iOS from suspending before GPS warms up
        if !isInForeground {
            var bgTaskId: UIBackgroundTaskIdentifier = .invalid
            bgTaskId = UIApplication.shared.beginBackgroundTask {
                UIApplication.shared.endBackgroundTask(bgTaskId)
            }
            Task {
                try? await Task.sleep(for: .seconds(AutoTripPolicy.backgroundLaunchTaskTimeout))
                await MainActor.run {
                    UIApplication.shared.endBackgroundTask(bgTaskId)
                }
            }
        }

        switch settings.autoRecordMode {
        case .auto:
            vm.startRecording()
            // `startRecording` refuses on a denied location permission and
            // while the force-quit recovery prompt is up — and said so only in
            // `startRefusal`, which nobody here read. Everything below assumed
            // success: the trip got backdated, «Запись началась» was posted,
            // and the driver spent the whole journey believing the road was
            // being written down. Say nothing rather than something false.
            guard vm.isRecording else {
                autoLog.error("[auto.trip_start.refused] reason=\(String(describing: vm.startRefusal), privacy: .public) device=\"\(deviceName, privacy: .public)\"")
                notificationManager.sendAutoStartFailedNotification(reason: vm.startRefusal)
                return
            }
            // Backdate trip start to when automotive activity actually began
            if let realStart = estimatedStartDate {
                vm.tripManager.backdateTrip(to: realStart)
            }
            // Retry Live Activity when app comes to foreground (background start may fail silently)
            if !isInForeground {
                scheduleLiveActivityRetry(vm: vm)
            }
            if isInForeground {
                NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
            } else {
                notificationManager.sendAutoStartNotification()
            }
        case .remind:
            hasRemindedForCurrentTrip = true
            if isInForeground {
                NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
            } else {
                notificationManager.sendTripStartPrompt(deviceName: deviceName)
            }
        case .off:
            break
        }
    }

    // MARK: - Detector Wiring

    private func setupDetectors() {
        bluetoothDetector.onDeviceEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleDeviceEvent(event, source: "bt_cb")
            }
        }
        audioRouteDetector.onDeviceEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleDeviceEvent(event, source: "audio_route")
            }
        }
        motionDetector.onAutomotiveDetected = { [weak self] in
            guard let self else { return }
            // Long gap since the car last stopped moving → treat as a new driving session
            if let lastEnd = self.lastAutomotiveEndTime,
               Date().timeIntervalSince(lastEnd) > AutoTripPolicy.newDrivingSessionGap {
                autoLog.notice("[auto.motion_callback] new_session_gap_detected gap_s=\(Int(Date().timeIntervalSince(lastEnd)), privacy: .public) reset_remind_flag=true")
                self.hasRemindedForCurrentTrip = false
            }
            if let vm = self.mapViewModel, vm.isRecording {
                // Car moved again — cancel any pending inactivity auto-stop
                autoLog.notice("[auto.motion_callback] cancel_stop_timer reason=car_moved_while_recording")
                self.cancelAutoStopTimer()
            }
            self.handleAutomotiveDetected()
        }
        motionDetector.onAutomotiveEnded = { [weak self] in
            // CMMotion flickers on red lights / traffic jams — don't drive auto-stop
            // from this signal (GPS-speed inactivity does that instead). We only
            // record the timestamp so onAutomotiveDetected can spot a new session.
            autoLog.notice("[auto.motion_callback] automotive_ended set_last_automotive_end=now")
            self?.lastAutomotiveEndTime = Date()
        }
    }

    // MARK: - BT Event Handling

    private func handleDeviceEvent(_ event: BluetoothEvent, source: String = "?") {
        switch event {
        case .connected(let deviceName):
            autoLog.notice("[auto.event] kind=connect source=\(source, privacy: .public) device=\"\(deviceName, privacy: .public)\"")
            handleDeviceConnected(name: deviceName)
        case .disconnected(let deviceName):
            autoLog.notice("[auto.event] kind=disconnect source=\(source, privacy: .public) device=\"\(deviceName, privacy: .public)\"")
            handleDeviceDisconnected(name: deviceName)
        }
    }

    private func handleDeviceConnected(name: String) {
        guard let vm = mapViewModel else {
            autoLog.notice("[auto.bt_connect.skip] reason=no_view_model device=\"\(name, privacy: .public)\"")
            return
        }
        guard shouldProcessEvent(.connected, name: name) else {
            autoLog.notice("[auto.bt_connect.skip] reason=debounced device=\"\(name, privacy: .public)\"")
            return
        }
        autoLog.notice("[auto.bt_connect] device=\"\(name, privacy: .public)\" mode=\(self.settings.autoRecordMode.rawValue, privacy: .public) isRecording=\(vm.isRecording, privacy: .public)")

        if let vehicleId = settings.vehicleId(forDeviceName: name) {
            settings.selectedVehicleId = vehicleId
            settings.saveSettings()
            autoLog.notice("[auto.bt_connect.vehicle_matched] vehicle_id=\(vehicleId.uuidString, privacy: .public)")
        }

        if vm.isRecording {
            // Already recording. Was the prior trip parked long enough that
            // this reconnect is really a new session? If so split — without
            // this, a return-to-car after >15 min (e.g. parked downtown for an
            // errand, came back) silently merges into the previous trip,
            // producing the "1-hour 3.1 km" zombie trips the user reported.
            // Otherwise (BT just flapped, came back) keep the trip going and
            // cancel any pending auto-stop.
            if isStaleByMovement {
                autoLog.notice("[auto.bt_connect.path] taken=split_stale_then_new_trip")
                cancelAutoStopTimer()
                autoStopTrip()
                // Brief gap so the auto-stop notification renders before the
                // new-trip start — without it the user can miss the visual
                // cue that a split actually happened.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, let vm = self.mapViewModel, !vm.isRecording else { return }
                    self.triggerTripStart(vm: vm, deviceName: name)
                }
            } else {
                autoLog.notice("[auto.bt_connect.path] taken=keep_recording_cancel_stop_timer")
                cancelAutoStopTimer()
            }
            return
        }

        autoLog.notice("[auto.bt_connect.path] taken=trigger_new_trip")
        cancelAutoStopTimer()
        triggerTripStart(vm: vm, deviceName: name)
    }

    private func handleDeviceDisconnected(name: String) {
        guard let vm = mapViewModel else {
            autoLog.notice("[auto.bt_disconnect.skip] reason=no_view_model device=\"\(name, privacy: .public)\"")
            return
        }
        guard shouldProcessEvent(.disconnected, name: name) else {
            autoLog.notice("[auto.bt_disconnect.skip] reason=debounced device=\"\(name, privacy: .public)\"")
            return
        }

        // BT disconnect is a strong end-of-session signal — always reset remind flag
        hasRemindedForCurrentTrip = false

        let stale5 = isStaleByMovement(threshold: AutoTripPolicy.bluetoothDisconnectFastStopIdleThreshold)
        let tripDist = vm.tripManager.activeTrip?.distance ?? 0
        let tripDur = vm.tripManager.activeTrip?.duration ?? 0
        autoLog.notice("[auto.bt_disconnect] device=\"\(name, privacy: .public)\" mode=\(self.settings.autoRecordMode.rawValue, privacy: .public) isRecording=\(vm.isRecording, privacy: .public) stale_5min=\(stale5, privacy: .public) dist_m=\(Int(tripDist), privacy: .public) dur_s=\(Int(tripDur), privacy: .public)")

        guard vm.isRecording else {
            autoLog.notice("[auto.bt_disconnect.skip] reason=not_recording")
            return
        }

        // Fast-stop heuristics that skip the 3-min grace are valid only in
        // `.auto` mode. In `.remind` the user opted into "ask first" — silently
        // ending the recording (even with confidence) violates that contract.
        // Same gating as `recoverStaleTripIfNeeded`. A false BT-disconnect
        // event mid-drive used to hit the "real-drive" path and immediately
        // kill the trip; the prompt+timer path below handles BT flap correctly
        // via `cancelAutoStopTimer` on reconnect.
        if settings.autoRecordMode == .auto {
            // BT off + already-idle trip = double confirmation user has parked.
            // Skip the 3-min grace and end now — the grace is for BT-flap
            // glitches, not for an obviously-finished trip.
            if stale5 {
                autoLog.notice("[auto.bt_disconnect.path] taken=immediate_stop_stale")
                autoStopTrip()
                return
            }

            // BT off after a real drive = user got out and is now walking. If
            // we wait the 3-min grace, GPS keeps logging footsteps (~5 km/h,
            // points >5m apart so drift filter doesn't reject them) and a
            // 50-min drive becomes a 53-min "drive" with 250m of walking
            // tacked on. End now and trim to the last distance-change time.
            // The 3-min grace is reserved for trips so short they could only
            // be a BT glitch in the first place.
            if let trip = vm.tripManager.activeTrip,
               trip.distance >= AutoTripPolicy.immediateEndOnBtDisconnectMinDistance,
               trip.duration >= AutoTripPolicy.immediateEndOnBtDisconnectMinDuration {
                autoLog.notice("[auto.bt_disconnect.path] taken=immediate_stop_real_drive thresh_dist_m=\(Int(AutoTripPolicy.immediateEndOnBtDisconnectMinDistance), privacy: .public) thresh_dur_s=\(Int(AutoTripPolicy.immediateEndOnBtDisconnectMinDuration), privacy: .public)")
                autoStopTrip()
                return
            }
        }

        let timeout = settings.autoStopTimeout
        autoLog.notice("[auto.bt_disconnect.path] taken=prompt_timer timeout_min=\(timeout, privacy: .public)")
        notificationManager.sendTripStopPrompt(minutes: timeout, reason: .bluetooth)
        startAutoStopTimer(minutes: timeout)
    }

    /// Has the active trip's distance been frozen long enough that the next
    /// trigger should be treated as a new session?
    private var isStaleByMovement: Bool {
        movementTracker.isStale(threshold: AutoTripPolicy.staleTripTimeout)
    }

    private func isStaleByMovement(threshold: TimeInterval) -> Bool {
        movementTracker.isStale(threshold: threshold)
    }

    // MARK: - Auto-stop Timer

    private func startAutoStopTimer(minutes: Int) {
        autoLog.notice("[auto.stop_timer.start] timeout_min=\(minutes, privacy: .public)")
        cancelAutoStopTimer()

        autoStopTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(minutes * 60),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                autoLog.notice("[auto.stop_timer.fired]")
                self?.autoStopTrip()
            }
        }

        // Background fallback notification
        let content = UNMutableNotificationContent()
        let lang = LanguageManager.currentLanguage
        content.title = AppStrings.notifTripStopTitle(lang)
        content.body = AppStrings.notifAutoStopBody(lang)
        content.sound = .default
        content.categoryIdentifier = NotificationManager.tripStopPromptCategory
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: NotificationManager.autoStopDeadlineId,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Recording lifecycle

    /// A recording just began — reset the inactivity tracker to THIS trip's
    /// odometer.
    ///
    /// The tracker's only other reset lives in `updateMovementForInactivity`'s
    /// guard-else, which needs a location update to run — and the moment a trip
    /// ends, `TripManager.stopTrip` stops CoreLocation, so that callback never
    /// arrives again. The tracker therefore carried the *previous* trip's
    /// distance baseline and last-movement timestamp into the next one. The
    /// next trip starts its odometer at zero, so `record()` compared 0 against
    /// (say) 45 km and concluded "no meaningful movement", while `isStale`
    /// measured against a timestamp from the last drive: an inactivity prompt
    /// within minutes of setting off, and — once the auto-stop timer fired —
    /// a recording silently ended and backdated in the middle of the drive.
    func recordingDidStart() {
        movementTracker.reset()
        cancelAutoStopTimer()
        autoLog.notice("[auto.tracker.reset] reason=recording_started")
    }

    /// A recording ended — drop the tracker state and any armed auto-stop so
    /// nothing from this trip can reach the next one.
    func recordingDidEnd() {
        movementTracker.reset()
        cancelAutoStopTimer()
        // A pending Live-Activity retry belongs to the trip that armed it.
        if let obs = foregroundRetryObserver {
            NotificationCenter.default.removeObserver(obs)
            foregroundRetryObserver = nil
        }
        autoLog.notice("[auto.tracker.reset] reason=recording_ended")
    }

    private func cancelAutoStopTimer() {
        if autoStopTimer != nil {
            autoLog.notice("[auto.stop_timer.cancel]")
        }
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        notificationManager.cancelTripStopPrompt()
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationManager.autoStopDeadlineId]
        )
    }

    private func autoStopTrip() {
        guard let vm = mapViewModel, vm.isRecording else {
            autoLog.notice("[auto.trip_stop.skip] reason=not_recording")
            return
        }
        let lastChange = movementTracker.lastChangeTime
        let lastChangeAgo = lastChange.map { Int(Date().timeIntervalSince($0)) }
        if let trip = vm.tripManager.activeTrip {
            autoLog.notice("[auto.trip_stop] dist_m=\(Int(trip.distance), privacy: .public) dur_s=\(Int(trip.duration), privacy: .public) last_change_s_ago=\(lastChangeAgo.map(String.init) ?? "nil", privacy: .public)")
            notificationManager.sendAutoStopNotification(distanceKm: trip.distanceKm, duration: trip.formattedDuration)
        } else {
            autoLog.notice("[auto.trip_stop] active_trip=nil")
        }
        // Hand the moment the trip stopped moving down to `stopTrip` — for
        // stale-recovery / inactivity-fired auto-stops the wall clock is
        // 10–15+ min past the real end, and `trimmedEndDate` can't recover
        // it from track points (parked tails are all-filtered-out). Without
        // this the trip duration includes the entire detection window.
        vm.stopRecording(suggestedEndDate: lastChange)
        hasRemindedForCurrentTrip = false
    }

    // MARK: - Notification Action Handling

    private func setupNotificationObservers() {
        let startObs = NotificationCenter.default.addObserver(
            forName: .autoTripStartRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                autoLog.notice("[auto.notification_action] action=start_requested_by_user")
                self?.hasRemindedForCurrentTrip = false
                guard let vm = self?.mapViewModel, !vm.isRecording else {
                    autoLog.notice("[auto.notification_action.skip] action=start reason=already_recording_or_no_vm")
                    return
                }
                // Pre-warm GPS immediately — don't wait for full startRecording() chain
                vm.locationManager.startTracking()
                vm.startRecording()
            }
        }

        let stopObs = NotificationCenter.default.addObserver(
            forName: .autoTripStopRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                autoLog.notice("[auto.notification_action] action=stop_requested_by_user")
                self?.cancelAutoStopTimer()
                self?.autoStopTrip()
            }
        }

        let continueObs = NotificationCenter.default.addObserver(
            forName: .autoTripContinueRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                autoLog.notice("[auto.notification_action] action=continue_requested_by_user")
                guard let self else { return }
                self.cancelAutoStopTimer()
                // Push the inactivity window forward — user explicitly said
                // "keep going", so don't re-prompt them in another second.
                self.movementTracker.extendWindow()
            }
        }

        let foregroundObs = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recoverStaleTripIfNeeded()
            }
        }

        notificationObservers = [startObs, stopObs, continueObs, foregroundObs]
    }

    // MARK: - Deduplication

    private func shouldProcessEvent(_ type: EventType, name: String) -> Bool {
        eventDebouncer.shouldProcess(EventKey(type: type, name: name))
    }
    // MARK: - Live Activity Foreground Retry

    private func scheduleLiveActivityRetry(vm: MapViewModel) {
        if let obs = foregroundRetryObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        foregroundRetryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self, weak vm] _ in
            Task { @MainActor in
                guard let self else { return }
                // Fire once, whatever the outcome. Unregistering only on the
                // branch that went on to create the card left the observer
                // armed whenever the app was foregrounded after the trip had
                // already ended — and it then outlived its own trip and
                // rebuilt a Live Activity mid-drive weeks later, with a fresh
                // start date and isPaused=false over a paused recording.
                if let obs = self.foregroundRetryObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self.foregroundRetryObserver = nil
                }
                guard let vm, vm.isRecording else { return }
                let settings = SettingsManager.shared
                let vehicle = settings.vehicle(for: settings.selectedVehicleId)
                let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
                LiveActivityManager.shared.startActivity(
                    tripId: vm.tripManager.activeTrip?.id ?? UUID(),
                    startDate: vm.tripManager.activeTrip?.startDate ?? Date(),
                    vehicleName: vehicle?.name
                        ?? AppStrings.vehicleTypeCar(LanguageManager.Language(rawValue: lang) ?? .en),
                    vehicleAvatar: vehicle?.avatarEmoji ?? "🚗"
                )
            }
        }
    }
}

// MARK: - Keep-alive Location Delegate

final class KeepAliveLocationDelegate: NSObject, CLLocationManagerDelegate {
    private let onLocationUpdate: () -> Void

    init(onLocationUpdate: @escaping () -> Void) {
        self.onLocationUpdate = onLocationUpdate
        super.init()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onLocationUpdate()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
