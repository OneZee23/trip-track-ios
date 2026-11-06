import Foundation
import AVFoundation
import UIKit
import OSLog

private let audioLog = Logger(subsystem: "com.triptrack", category: "audio-route")

final class AudioRouteDetector: ObservableObject {
    /// Called on the main thread, in the order the route changed.
    var onDeviceEvent: ((BluetoothEvent) -> Void)?

    /// Main thread only, like everything that decides an event.
    private var lastKnownBluetoothDevice: String?
    /// Idempotence flag — `selector:`-style observers don't dedupe and a
    /// second `startMonitoring()` would stack a second copy. The
    /// AutoTripService side now also gates, but defense-in-depth here.
    private var isMonitoring = false

    private let center: NotificationCenter
    private let readOutput: () -> String?
    private let isSaved: (String) -> Bool

    /// Every `AVAudioSession` call of this type runs here, off the main thread.
    /// The session answers through the audio server, and while the server
    /// reconfigures (a stereo connecting, our own category change) a route
    /// read or an activation can take seconds: Sentry APPLE-IOS-18 (0.9.3,
    /// 5 Nov 2026) caught the main thread waiting 2 s in `currentRoute` under
    /// `handleRouteChange`.
    static let sessionQueue = DispatchQueue(label: "com.triptrack.audio-route", qos: .userInitiated)

    /// The seams are for tests: a private notification center keeps the
    /// simulator's own route changes out, and the reader can be slow on purpose.
    init(center: NotificationCenter = .default,
         readOutput: @escaping () -> String? = AudioRouteDetector.currentBluetoothOutputName,
         isSaved: @escaping (String) -> Bool = { SettingsManager.shared.isSavedBluetoothDevice(name: $0) }) {
        self.center = center
        self.readOutput = readOutput
        self.isSaved = isSaved
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !isMonitoring else {
            audioLog.notice("[audio.start_monitor.skip] reason=already_running")
            return
        }
        audioLog.notice("[audio.start_monitor]")
        isMonitoring = true
        // Activate audio session so we receive route change notifications in
        // background. Use `.ambient` instead of `.playback` — `.playback`
        // marks the app as a Now Playing candidate and pauses other apps
        // that don't use `.mixWithOthers`. `.ambient` with `.mixWithOthers`
        // gets us the route notifications we need without the audio
        // interruption side effects.
        Self.sessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.ambient, options: .mixWithOthers)
                try session.setActive(true)
            } catch {
                // Non-fatal: route monitoring may not work in background
            }
        }

        center.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        // Re-check audio route every time app returns to foreground
        center.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        // Check current route on start. The read queues behind the activation.
        checkCurrentRoute()
    }

    @objc private func handleAppBecameActive() {
        audioLog.notice("[audio.app_became_active] schedule_route_check_in_s=\(Int(AutoTripPolicy.audioRouteSettleDelay), privacy: .public)")
        // At unlock iOS audio routing can briefly show a non-stereo output
        // (e.g. .builtInSpeaker) for a tick before settling back on the car
        // route, which `checkCurrentRoute` would otherwise interpret as a
        // disconnect and fire a stop prompt while the engine is still
        // running and the stereo is still connected. Wait for it to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + AutoTripPolicy.audioRouteSettleDelay) { [weak self] in
            self?.checkCurrentRoute()
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        audioLog.notice("[audio.stop_monitor] last_known_bt=\"\(self.lastKnownBluetoothDevice ?? "nil", privacy: .public)\"")
        isMonitoring = false
        center.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        center.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        // Deactivate the audio session so we stop showing as a Now Playing
        // candidate / battery-warming the audio HAL when no longer needed.
        Self.sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        lastKnownBluetoothDevice = nil
    }

    // MARK: - Route Change Handling

    /// Can arrive on any thread. Nothing here touches state or the session:
    /// the work goes through `sessionQueue` and lands on main.
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            audioLog.notice("[audio.route_change.skip] reason=missing_userInfo")
            return
        }
        audioLog.notice("[audio.route_change] reason=\(AudioRouteDetector.reasonString(reason), privacy: .public)")

        switch reason {
        case .newDeviceAvailable:
            readRoute { [weak self] output in self?.applyNewDevice(output) }
        case .oldDeviceUnavailable:
            guard let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
                audioLog.notice("[audio.check_disconnect.skip] reason=no_previous_route")
                return
            }
            let names = previousRoute.outputs.filter { Self.isCarStereoPort($0.portType) }.map(\.portName)
            afterQueuedReads { [weak self] in self?.applyLostDevices(names) }
        case .categoryChange, .override, .routeConfigurationChange:
            checkCurrentRoute()
        default:
            break
        }
    }

    private static func reasonString(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "undef_\(reason.rawValue)"
        }
    }

    // MARK: - Route Pipeline

    /// Reads the route on `sessionQueue` and hands the answer to main.
    /// GCD on purpose: two route changes a few milliseconds apart must reach
    /// main in the order they happened. A serial queue hopping to the main
    /// queue keeps that order, separate `Task`s are not promised to.
    private func readRoute(then apply: @escaping (String?) -> Void) {
        let read = readOutput
        Self.sessionQueue.async {
            let output = read()
            DispatchQueue.main.async { apply(output) }
        }
    }

    /// Runs `apply` on main after every route read queued before it.
    private func afterQueuedReads(_ apply: @escaping () -> Void) {
        Self.sessionQueue.async {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func applyNewDevice(_ btDevice: String?) {
        guard isMonitoring else { return }
        guard let btDevice else {
            audioLog.notice("[audio.check_connect.skip] reason=no_bt_output")
            return
        }
        guard isSaved(btDevice) else {
            audioLog.notice("[audio.check_connect.skip] reason=not_saved device=\"\(btDevice, privacy: .public)\"")
            return
        }
        guard lastKnownBluetoothDevice != btDevice else {
            audioLog.notice("[audio.check_connect.dedup] device=\"\(btDevice, privacy: .public)\"")
            return
        }

        audioLog.notice("[audio.fire_connect] device=\"\(btDevice, privacy: .public)\"")
        lastKnownBluetoothDevice = btDevice
        onDeviceEvent?(.connected(deviceName: btDevice))
    }

    private func applyLostDevices(_ names: [String]) {
        guard isMonitoring else { return }
        for name in names {
            guard isSaved(name) else {
                audioLog.notice("[audio.check_disconnect.skip] reason=not_saved device=\"\(name, privacy: .public)\"")
                continue
            }

            if lastKnownBluetoothDevice == name {
                audioLog.notice("[audio.fire_disconnect] device=\"\(name, privacy: .public)\"")
                lastKnownBluetoothDevice = nil
                onDeviceEvent?(.disconnected(deviceName: name))
            } else {
                audioLog.notice("[audio.check_disconnect.skip] reason=not_tracked device=\"\(name, privacy: .public)\" last_known=\"\(self.lastKnownBluetoothDevice ?? "nil", privacy: .public)\"")
            }
        }
    }

    // MARK: - Route Inspection

    /// Asks the route again and settles what changed since the last answer.
    func checkCurrentRoute() {
        readRoute { [weak self] output in self?.applyCurrentRoute(output) }
    }

    private func applyCurrentRoute(_ btDevice: String?) {
        guard isMonitoring else { return }
        if let btDevice, isSaved(btDevice) {
            if lastKnownBluetoothDevice != btDevice {
                audioLog.notice("[audio.route_check.found_bt] device=\"\(btDevice, privacy: .public)\" was=\"\(self.lastKnownBluetoothDevice ?? "nil", privacy: .public)\" → fire_connect")
                lastKnownBluetoothDevice = btDevice
                onDeviceEvent?(.connected(deviceName: btDevice))
            }
        } else if let prev = lastKnownBluetoothDevice {
            audioLog.notice("[audio.route_check.lost_bt] was=\"\(prev, privacy: .public)\" current_output=\"\(btDevice ?? "nil", privacy: .public)\" → fire_disconnect")
            lastKnownBluetoothDevice = nil
            onDeviceEvent?(.disconnected(deviceName: prev))
        }
    }

    /// Returns the name of the current Bluetooth or CarPlay audio output, if any.
    /// Synchronous on purpose: `AutoTripService` decides a start with the
    /// live answer, mostly while the app is woken in the background.
    func currentBluetoothOutput() -> String? {
        readOutput()
    }

    /// The Bluetooth or CarPlay audio device the phone is playing through right now.
    ///
    /// Static because a view asking "is the stereo connected?" needs an answer,
    /// not a monitor. And it asks the AUDIO ROUTE, not `BluetoothDetector`:
    /// classic Bluetooth and CarPlay outputs are not found by BLE scanning.
    /// The route is the same source auto-record itself keys off.
    static func currentBluetoothOutputName() -> String? {
        stereoPort()?.portName
    }

    /// The stereo for a screen, read once on `sessionQueue`, so the screen
    /// never waits on the audio server.
    static func stereoOutput() async -> StereoOutput? {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: stereoPort().map {
                    StereoOutput(name: $0.portName, isCarPlay: $0.portType == .carAudio)
                })
            }
        }
    }

    /// One route answer, name and kind together. The link sheet names
    /// CarPlay «CarPlay»: AirPods are a Bluetooth output too, so the row
    /// cannot just say «Магнитола».
    struct StereoOutput: Equatable {
        let name: String
        let isCarPlay: Bool
    }

    private static func stereoPort() -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .first(where: { isCarStereoPort($0.portType) })
    }

    /// Re-exported so a view can watch the stereo come and go without
    /// importing AVFoundation for one symbol.
    static let routeChangeNotification = AVAudioSession.routeChangeNotification

    static func isCarStereoPort(_ portType: AVAudioSession.Port) -> Bool {
        portType == .bluetoothA2DP || portType == .bluetoothHFP
            || portType == .bluetoothLE || portType == .carAudio
    }
}
