import Foundation
import Combine
import UserNotifications

@MainActor
final class AutoTripService: ObservableObject {
    static let shared = AutoTripService()

    let bluetoothDetector = BluetoothDetector()
    let audioRouteDetector = AudioRouteDetector()

    private weak var mapViewModel: MapViewModel?
    private let notificationManager = NotificationManager.shared
    private let settings = SettingsManager.shared

    private var autoStopTimer: Timer?
    private var notificationObservers: [Any] = []

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
    }

    func startIfNeeded() {
        guard settings.autoRecordMode != .off else {
            stopMonitoring()
            return
        }
        guard !settings.savedBluetoothDevices.isEmpty else { return }

        // Ensure notification permissions are granted
        notificationManager.requestAuthorization { _ in }

        startMonitoring()
    }

    func startMonitoring() {
        bluetoothDetector.startMonitoring()
        audioRouteDetector.startMonitoring()
    }

    func stopMonitoring() {
        bluetoothDetector.stopMonitoring()
        audioRouteDetector.stopMonitoring()
        cancelAutoStopTimer()
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
    }

    // MARK: - Event Handling

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

        // Ignore if already recording
        guard !vm.isRecording else { return }

        // Deduplicate — both detectors might fire for same device
        guard shouldProcessEvent(.connected, name: name) else { return }

        // Cancel any pending auto-stop (reconnected quickly)
        cancelAutoStopTimer()

        // Select the vehicle linked to this BT device
        if let vehicleId = settings.vehicleId(forDeviceName: name) {
            settings.selectedVehicleId = vehicleId
            settings.saveSettings()
        }

        switch settings.autoRecordMode {
        case .auto:
            vm.startRecording()
            notificationManager.sendAutoStartNotification()
        case .remind:
            notificationManager.sendTripStartPrompt(deviceName: name)
        case .off:
            break
        }
    }

    private func handleDeviceDisconnected(name: String) {
        guard let vm = mapViewModel else { return }

        // Only relevant if recording
        guard vm.isRecording else { return }

        // Deduplicate
        guard shouldProcessEvent(.disconnected, name: name) else { return }

        let timeout = settings.autoStopTimeout
        notificationManager.sendTripStopPrompt(minutes: timeout)
        startAutoStopTimer(minutes: timeout)
    }

    // MARK: - Auto-stop Timer

    private func startAutoStopTimer(minutes: Int) {
        cancelAutoStopTimer()

        // Foreground timer
        autoStopTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(minutes * 60),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoStopTrip()
            }
        }

        // Background fallback: schedule a local notification at the deadline
        // so the user gets prompted even if the app is suspended and the timer doesn't fire
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
        vm.stopRecording()
    }

    // MARK: - Notification Action Handling

    private func setupNotificationObservers() {
        let startObs = NotificationCenter.default.addObserver(
            forName: .autoTripStartRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let vm = self?.mapViewModel, !vm.isRecording else { return }
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
}

