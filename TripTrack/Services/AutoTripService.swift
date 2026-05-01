import Foundation
import UserNotifications
import CoreLocation
import UIKit

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
        guard !isMonitoringActive else { return }
        isMonitoringActive = true
        bluetoothDetector.startMonitoring()
        audioRouteDetector.startMonitoring()
        motionDetector.startLiveUpdates()
        startKeepAlive()
    }

    func stopMonitoring() {
        guard isMonitoringActive else { return }
        isMonitoringActive = false
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
        guard let vm = mapViewModel else { return }

        // If a trip is already recording but it's been parked > staleTripTimeout,
        // this automotive event is the start of a *new* session — finish the
        // stale one before triggering. Without this, a previous trip whose
        // background auto-stop never fired (Timer.scheduledTimer doesn't run
        // while the app is suspended) silently absorbs the next drive.
        if vm.isRecording {
            guard isStaleByMovement else { return }
            cancelAutoStopTimer()
            autoStopTrip()
        }

        // Don't re-remind for the same driving session
        if settings.autoRecordMode == .remind && hasRemindedForCurrentTrip { return }

        // Deduplicate: BT + Motion can fire together within milliseconds
        if let last = lastTripTriggerTime,
           Date().timeIntervalSince(last) < AutoTripPolicy.triggerDeduplicationWindow { return }
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
        guard let vm = mapViewModel, vm.isRecording,
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
        guard settings.autoRecordMode == .auto else { return }
        guard let vm = mapViewModel, vm.isRecording else { return }
        guard movementTracker.isStale(threshold: AutoTripPolicy.staleTripTimeout) else { return }
        autoStopTrip()
    }

    // MARK: - Unified Trip Trigger

    private func triggerTripStart(vm: MapViewModel, deviceName: String, estimatedStartDate: Date? = nil) {
        // Defence-in-depth: every caller already gates on `!vm.isRecording`
        // up the stack, but those checks happen before async hops (motion
        // query, dispatch barriers). One last guard here so a slow callback
        // never sends an "are you in the car?" prompt while a trip is
        // already running.
        guard !vm.isRecording else { return }
        let isInForeground = UIApplication.shared.applicationState == .active

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
                self?.handleDeviceEvent(event)
            }
        }
        audioRouteDetector.onDeviceEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleDeviceEvent(event)
            }
        }
        motionDetector.onAutomotiveDetected = { [weak self] in
            guard let self else { return }
            // Long gap since the car last stopped moving → treat as a new driving session
            if let lastEnd = self.lastAutomotiveEndTime,
               Date().timeIntervalSince(lastEnd) > AutoTripPolicy.newDrivingSessionGap {
                self.hasRemindedForCurrentTrip = false
            }
            if let vm = self.mapViewModel, vm.isRecording {
                // Car moved again — cancel any pending inactivity auto-stop
                self.cancelAutoStopTimer()
            }
            self.handleAutomotiveDetected()
        }
        motionDetector.onAutomotiveEnded = { [weak self] in
            // CMMotion flickers on red lights / traffic jams — don't drive auto-stop
            // from this signal (GPS-speed inactivity does that instead). We only
            // record the timestamp so onAutomotiveDetected can spot a new session.
            self?.lastAutomotiveEndTime = Date()
        }
    }

    // MARK: - BT Event Handling

    private func handleDeviceEvent(_ event: BluetoothEvent) {
        switch event {
        case .connected(let deviceName):
            handleDeviceConnected(name: deviceName)
        case .disconnected(let deviceName):
            handleDeviceDisconnected(name: deviceName)
        }
    }

    private func handleDeviceConnected(name: String) {
        guard let vm = mapViewModel else { return }
        guard shouldProcessEvent(.connected, name: name) else { return }

        if let vehicleId = settings.vehicleId(forDeviceName: name) {
            settings.selectedVehicleId = vehicleId
            settings.saveSettings()
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
                cancelAutoStopTimer()
            }
            return
        }

        cancelAutoStopTimer()
        triggerTripStart(vm: vm, deviceName: name)
    }

    private func handleDeviceDisconnected(name: String) {
        guard let vm = mapViewModel else { return }
        guard shouldProcessEvent(.disconnected, name: name) else { return }

        // BT disconnect is a strong end-of-session signal — always reset remind flag
        hasRemindedForCurrentTrip = false

        guard vm.isRecording else { return }

        // BT off + already-idle trip = double confirmation user has parked.
        // Skip the 3-min grace and end now — the grace is for BT-flap
        // glitches, not for an obviously-finished trip.
        if isStaleByMovement(threshold: AutoTripPolicy.bluetoothDisconnectFastStopIdleThreshold) {
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
            autoStopTrip()
            return
        }

        let timeout = settings.autoStopTimeout
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
        cancelAutoStopTimer()

        autoStopTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(minutes * 60),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
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

    private func cancelAutoStopTimer() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        notificationManager.cancelTripStopPrompt()
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationManager.autoStopDeadlineId]
        )
    }

    private func autoStopTrip() {
        guard let vm = mapViewModel, vm.isRecording else { return }
        if let trip = vm.tripManager.activeTrip {
            notificationManager.sendAutoStopNotification(distanceKm: trip.distanceKm, duration: trip.formattedDuration)
        }
        // Hand the moment the trip stopped moving down to `stopTrip` — for
        // stale-recovery / inactivity-fired auto-stops the wall clock is
        // 10–15+ min past the real end, and `trimmedEndDate` can't recover
        // it from track points (parked tails are all-filtered-out). Without
        // this the trip duration includes the entire detection window.
        vm.stopRecording(suggestedEndDate: movementTracker.lastChangeTime)
        hasRemindedForCurrentTrip = false
    }

    // MARK: - Notification Action Handling

    private func setupNotificationObservers() {
        let startObs = NotificationCenter.default.addObserver(
            forName: .autoTripStartRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hasRemindedForCurrentTrip = false
                guard let vm = self?.mapViewModel, !vm.isRecording else { return }
                // Pre-warm GPS immediately — don't wait for full startRecording() chain
                vm.locationManager.startTracking()
                vm.startRecording()
            }
        }

        let stopObs = NotificationCenter.default.addObserver(
            forName: .autoTripStopRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelAutoStopTimer()
                self?.autoStopTrip()
            }
        }

        let continueObs = NotificationCenter.default.addObserver(
            forName: .autoTripContinueRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
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
                guard let self, let vm, vm.isRecording else { return }
                if let obs = self.foregroundRetryObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self.foregroundRetryObserver = nil
                }
                let settings = SettingsManager.shared
                let vehicle = settings.vehicles.first { $0.id == settings.selectedVehicleId } ?? settings.vehicles.first
                let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
                LiveActivityManager.shared.startActivity(
                    tripId: vm.tripManager.activeTrip?.id ?? UUID(),
                    startDate: vm.tripManager.activeTrip?.startDate ?? Date(),
                    vehicleName: vehicle?.name ?? (lang == "ru" ? "Авто" : "Car"),
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
