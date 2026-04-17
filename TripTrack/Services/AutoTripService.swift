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
    private var motionEndedDebounceTimer: Timer?
    private var notificationObservers: [Any] = []
    private var keepAliveLocationManager: CLLocationManager?
    private var keepAliveDelegate: KeepAliveLocationDelegate?

    // Debounce: ignore duplicate events within this window
    private let deduplicationInterval: TimeInterval = 5
    private var lastProcessedEvent: (type: EventType, name: String, time: Date)?
    private enum EventType { case connected, disconnected }

    private init() {
        setupDetectors()
        setupNotificationObservers()
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

    func startMonitoring() {
        bluetoothDetector.startMonitoring()
        audioRouteDetector.startMonitoring()
        motionDetector.startLiveUpdates()
        startKeepAlive()
    }

    func stopMonitoring() {
        bluetoothDetector.stopMonitoring()
        audioRouteDetector.stopMonitoring()
        motionDetector.stopLiveUpdates()
        motionEndedDebounceTimer?.invalidate()
        motionEndedDebounceTimer = nil
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
    private var foregroundRetryObserver: Any?

    private func handleAutomotiveDetected() {
        guard let vm = mapViewModel, !vm.isRecording else { return }

        // Don't re-remind for the same driving session
        if settings.autoRecordMode == .remind && hasRemindedForCurrentTrip { return }

        // Deduplicate: don't trigger twice within 30s (BT + Motion can fire together)
        if let last = lastTripTriggerTime, Date().timeIntervalSince(last) < 30 { return }
        lastTripTriggerTime = Date()

        // Check if BT audio route matches a saved device → select vehicle
        if let btDevice = audioRouteDetector.currentBluetoothOutput(),
           let vehicleId = settings.vehicleId(forDeviceName: btDevice) {
            settings.selectedVehicleId = vehicleId
            settings.saveSettings()
        }

        // Try to recover the real trip start time from CMMotion history
        motionDetector.queryAutomotiveStartTime { [weak self] automotiveStartDate in
            guard let self else { return }
            let deviceName = self.audioRouteDetector.currentBluetoothOutput()
                ?? AppStrings.car(LanguageManager.currentLanguage)
            self.triggerTripStart(vm: vm, deviceName: deviceName, estimatedStartDate: automotiveStartDate)
        }
    }

    // MARK: - Inactivity Auto-stop

    private var lowSpeedStartTime: Date?
    private static let inactivityTimeout: TimeInterval = 20 * 60 // 20 minutes
    private static let lowSpeedThreshold: Double = 2.0 // km/h

    /// Called periodically from MapViewModel speed updates to track inactivity
    func updateSpeedForInactivity(_ speedKmh: Double) {
        guard let vm = mapViewModel, vm.isRecording else {
            lowSpeedStartTime = nil
            return
        }

        if speedKmh < Self.lowSpeedThreshold {
            if lowSpeedStartTime == nil {
                lowSpeedStartTime = Date()
            }
            if let start = lowSpeedStartTime,
               Date().timeIntervalSince(start) > Self.inactivityTimeout {
                // Stationary for 20 minutes — trigger auto-stop
                let timeout = settings.autoStopTimeout
                notificationManager.sendTripStopPrompt(minutes: timeout)
                startAutoStopTimer(minutes: timeout)
                lowSpeedStartTime = nil // reset so we don't re-trigger
            }
        } else {
            lowSpeedStartTime = nil
        }
    }

    // MARK: - Unified Trip Trigger

    private func triggerTripStart(vm: MapViewModel, deviceName: String, estimatedStartDate: Date? = nil) {
        let isInForeground = UIApplication.shared.applicationState == .active

        // Request background task to prevent iOS from suspending before GPS warms up
        if !isInForeground {
            var bgTaskId: UIBackgroundTaskIdentifier = .invalid
            bgTaskId = UIApplication.shared.beginBackgroundTask {
                UIApplication.shared.endBackgroundTask(bgTaskId)
            }
            // End after 25 seconds or when recording is stable
            Task {
                try? await Task.sleep(for: .seconds(25))
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
            self?.motionEndedDebounceTimer?.invalidate()
            self?.handleAutomotiveDetected()
        }
        motionDetector.onAutomotiveEnded = { [weak self] in
            guard let self else { return }
            // Debounce: CMMotion flickers between states at red lights etc.
            // Wait 60s of non-automotive before triggering auto-stop
            self.motionEndedDebounceTimer?.invalidate()
            self.motionEndedDebounceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.hasRemindedForCurrentTrip = false
                    guard let vm = self.mapViewModel, vm.isRecording else { return }
                    let timeout = self.settings.autoStopTimeout
                    self.notificationManager.sendTripStopPrompt(minutes: timeout)
                    self.startAutoStopTimer(minutes: timeout)
                }
            }
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
        guard !vm.isRecording else { return }
        guard shouldProcessEvent(.connected, name: name) else { return }

        cancelAutoStopTimer()

        if let vehicleId = settings.vehicleId(forDeviceName: name) {
            settings.selectedVehicleId = vehicleId
            settings.saveSettings()
        }

        triggerTripStart(vm: vm, deviceName: name)
    }

    private func handleDeviceDisconnected(name: String) {
        guard let vm = mapViewModel else { return }
        guard vm.isRecording else { return }
        guard shouldProcessEvent(.disconnected, name: name) else { return }

        let timeout = settings.autoStopTimeout
        notificationManager.sendTripStopPrompt(minutes: timeout)
        startAutoStopTimer(minutes: timeout)
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
        vm.stopRecording()
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
                self?.cancelAutoStopTimer()
            }
        }

        notificationObservers = [startObs, stopObs, continueObs]
    }

    // MARK: - Deduplication

    private func shouldProcessEvent(_ type: EventType, name: String) -> Bool {
        let now = Date()
        if let last = lastProcessedEvent,
           last.type == type,
           last.name == name,
           now.timeIntervalSince(last.time) < deduplicationInterval {
            return false
        }
        lastProcessedEvent = (type: type, name: name, time: now)
        return true
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
