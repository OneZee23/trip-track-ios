import Foundation
import AVFoundation
import UIKit
import OSLog

private let audioLog = Logger(subsystem: "com.triptrack", category: "audio-route")

final class AudioRouteDetector: ObservableObject {
    var onDeviceEvent: ((BluetoothEvent) -> Void)?

    private var lastKnownBluetoothDevice: String?
    /// Idempotence flag — `selector:`-style observers don't dedupe and a
    /// second `startMonitoring()` would stack a second copy. The
    /// AutoTripService side now also gates, but defense-in-depth here.
    private var isMonitoring = false

    init() {}

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
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            // Non-fatal: route monitoring may not work in background
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        // Re-check audio route every time app returns to foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        // Check current route on start
        checkCurrentRoute()
    }

    @objc private func handleAppBecameActive() {
        audioLog.notice("[audio.app_became_active] schedule_route_check_in_s=\(Int(AutoTripPolicy.audioRouteSettleDelay), privacy: .public)")
        // At unlock iOS audio routing can briefly show a non-BT output
        // (e.g. .builtInSpeaker) for a tick before settling back on the BT
        // route, which `checkCurrentRoute` would otherwise interpret as a
        // disconnect and fire a stop prompt while the engine is still
        // running and BT is still actually connected. Wait for it to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + AutoTripPolicy.audioRouteSettleDelay) { [weak self] in
            self?.checkCurrentRoute()
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        audioLog.notice("[audio.stop_monitor] last_known_bt=\"\(self.lastKnownBluetoothDevice ?? "nil", privacy: .public)\"")
        isMonitoring = false
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        // Deactivate the audio session so we stop showing as a Now Playing
        // candidate / battery-warming the audio HAL when no longer needed.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        lastKnownBluetoothDevice = nil
    }

    // MARK: - Route Change Handling

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
            checkForBluetoothConnection()
        case .oldDeviceUnavailable:
            checkForBluetoothDisconnection(userInfo: userInfo)
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

    private func checkForBluetoothConnection() {
        guard let btDevice = currentBluetoothOutput() else {
            audioLog.notice("[audio.check_connect.skip] reason=no_bt_output")
            return
        }
        guard isSavedDevice(name: btDevice) else {
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

    private func checkForBluetoothDisconnection(userInfo: [AnyHashable: Any]) {
        guard let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            audioLog.notice("[audio.check_disconnect.skip] reason=no_previous_route")
            return
        }

        let previousBTOutputs = previousRoute.outputs.filter { isBluetoothPort($0.portType) }
        for output in previousBTOutputs {
            let name = output.portName
            guard isSavedDevice(name: name) else {
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

    func checkCurrentRoute() {
        if let btDevice = currentBluetoothOutput(), isSavedDevice(name: btDevice) {
            if lastKnownBluetoothDevice != btDevice {
                audioLog.notice("[audio.route_check.found_bt] device=\"\(btDevice, privacy: .public)\" was=\"\(self.lastKnownBluetoothDevice ?? "nil", privacy: .public)\" → fire_connect")
                lastKnownBluetoothDevice = btDevice
                onDeviceEvent?(.connected(deviceName: btDevice))
            }
        } else if let prev = lastKnownBluetoothDevice {
            audioLog.notice("[audio.route_check.lost_bt] was=\"\(prev, privacy: .public)\" current_output=\"\(self.currentBluetoothOutput() ?? "nil", privacy: .public)\" → fire_disconnect")
            lastKnownBluetoothDevice = nil
            onDeviceEvent?(.disconnected(deviceName: prev))
        }
    }

    /// Returns the name of the current Bluetooth audio output, if any
    func currentBluetoothOutput() -> String? {
        let route = AVAudioSession.sharedInstance().currentRoute
        return route.outputs.first(where: { isBluetoothPort($0.portType) })?.portName
    }

    private func isBluetoothPort(_ portType: AVAudioSession.Port) -> Bool {
        portType == .bluetoothA2DP || portType == .bluetoothHFP || portType == .bluetoothLE
    }

    private func isSavedDevice(name: String) -> Bool {
        SettingsManager.shared.isSavedBluetoothDevice(name: name)
    }
}
