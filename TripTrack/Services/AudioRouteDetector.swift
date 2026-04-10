import Foundation
import AVFoundation
import UIKit

final class AudioRouteDetector: ObservableObject {
    var onDeviceEvent: ((BluetoothEvent) -> Void)?

    private var lastKnownBluetoothDevice: String?

    init() {}

    // MARK: - Lifecycle

    func startMonitoring() {
        // Activate audio session so we receive route change notifications in background
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: .mixWithOthers)
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
        checkCurrentRoute()
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        lastKnownBluetoothDevice = nil
    }

    // MARK: - Route Change Handling

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

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

    private func checkForBluetoothConnection() {
        guard let btDevice = currentBluetoothOutput() else { return }
        guard isSavedDevice(name: btDevice) else { return }
        guard lastKnownBluetoothDevice != btDevice else { return }

        lastKnownBluetoothDevice = btDevice
        onDeviceEvent?(.connected(deviceName: btDevice))
    }

    private func checkForBluetoothDisconnection(userInfo: [AnyHashable: Any]) {
        guard let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            return
        }

        let previousBTOutputs = previousRoute.outputs.filter { isBluetoothPort($0.portType) }
        for output in previousBTOutputs {
            let name = output.portName
            guard isSavedDevice(name: name) else { continue }

            if lastKnownBluetoothDevice == name {
                lastKnownBluetoothDevice = nil
                onDeviceEvent?(.disconnected(deviceName: name))
            }
        }
    }

    // MARK: - Route Inspection

    func checkCurrentRoute() {
        if let btDevice = currentBluetoothOutput(), isSavedDevice(name: btDevice) {
            if lastKnownBluetoothDevice != btDevice {
                lastKnownBluetoothDevice = btDevice
                onDeviceEvent?(.connected(deviceName: btDevice))
            }
        } else if let prev = lastKnownBluetoothDevice {
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
