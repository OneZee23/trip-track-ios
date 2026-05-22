import Foundation
import CoreBluetooth
import OSLog

private let btLog = Logger(subsystem: "com.triptrack", category: "bluetooth")

enum BluetoothEvent {
    case connected(deviceName: String)
    case disconnected(deviceName: String)
}

final class BluetoothDetector: NSObject, ObservableObject {
    @Published var isBluetoothAvailable: Bool = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning: Bool = false

    var onDeviceEvent: ((BluetoothEvent) -> Void)?

    private var centralManager: CBCentralManager?
    private var monitoredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedDeviceNames: Set<String> = []
    private var retryCount: [UUID: Int] = [:]
    private static let maxRetries = 3

    struct DiscoveredDevice: Identifiable, Equatable {
        let id: String // peripheral UUID
        let name: String
        let rssi: Int

        static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
            lhs.id == rhs.id
        }
    }

    override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard centralManager == nil else {
            btLog.notice("[bt.start_monitor.skip] reason=already_running")
            return
        }
        btLog.notice("[bt.start_monitor]")
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "com.onezee.TripTrack.bluetooth",
            CBCentralManagerOptionShowPowerAlertKey: false
        ])
    }

    func stopMonitoring() {
        btLog.notice("[bt.stop_monitor] tracked_devices=\(self.connectedDeviceNames.count, privacy: .public)")
        stopScanning()
        centralManager = nil
        monitoredPeripherals.removeAll()
        connectedDeviceNames.removeAll()
    }

    // MARK: - Scanning (foreground, for settings UI)

    /// Whether a scan was requested before CBCentralManager was ready
    private var pendingScan = false

    func startScanning() {
        // Ensure central manager exists
        if centralManager == nil {
            startMonitoring()
        }

        guard let manager = centralManager else { return }

        // If BT is not powered on yet, defer scan until centralManagerDidUpdateState
        guard manager.state == .poweredOn else {
            pendingScan = true
            isScanning = true // Show spinner in UI while waiting
            return
        }

        beginScan(manager: manager)
    }

    private func beginScan(manager: CBCentralManager) {
        pendingScan = false
        discoveredDevices.removeAll()
        isScanning = true
        manager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Auto-stop scan after 30 seconds
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await MainActor.run { self?.stopScanning() }
        }
    }

    func stopScanning() {
        guard isScanning else { return }
        centralManager?.stopScan()
        isScanning = false
    }

    // MARK: - Saved Device Matching

    private func isSavedDevice(name: String) -> Bool {
        SettingsManager.shared.isSavedBluetoothDevice(name: name)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothDetector: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        btLog.notice("[bt.state_changed] state=\(BluetoothDetector.stateString(central.state), privacy: .public) pendingScan=\(self.pendingScan, privacy: .public) connected_count=\(self.connectedDeviceNames.count, privacy: .public)")

        Task { @MainActor [weak self] in
            self?.isBluetoothAvailable = central.state == .poweredOn
        }

        // Start deferred scan if BT just became available
        if central.state == .poweredOn && pendingScan {
            beginScan(manager: central)
        }

        if central.state == .poweredOff {
            // Treat as disconnect for all connected saved devices
            for name in connectedDeviceNames {
                btLog.notice("[bt.synthetic_disconnect] reason=bluetooth_powered_off device=\"\(name, privacy: .public)\"")
                onDeviceEvent?(.disconnected(deviceName: name))
            }
            connectedDeviceNames.removeAll()
        }
    }

    private static func stateString(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "undef_\(state.rawValue)"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }

        let device = DiscoveredDevice(
            id: peripheral.identifier.uuidString,
            name: name,
            rssi: RSSI.intValue
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                self.discoveredDevices[index] = device
            } else {
                self.discoveredDevices.append(device)
            }
        }

        // If this is a saved device, try to connect for monitoring
        if isSavedDevice(name: name) {
            monitoredPeripherals[peripheral.identifier] = peripheral
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let name = peripheral.name, isSavedDevice(name: name) else {
            btLog.notice("[bt.didConnect.skip] reason=not_saved device=\"\(peripheral.name ?? "<nil>", privacy: .public)\"")
            return
        }
        retryCount.removeValue(forKey: peripheral.identifier)
        guard !connectedDeviceNames.contains(name) else {
            btLog.notice("[bt.didConnect.dedup] device=\"\(name, privacy: .public)\" already_tracked=true")
            return
        }
        btLog.notice("[bt.didConnect] device=\"\(name, privacy: .public)\" uuid=\(peripheral.identifier.uuidString, privacy: .public)")
        connectedDeviceNames.insert(name)
        onDeviceEvent?(.connected(deviceName: name))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let name = peripheral.name, isSavedDevice(name: name) else {
            btLog.notice("[bt.didDisconnect.skip] reason=not_saved device=\"\(peripheral.name ?? "<nil>", privacy: .public)\" error=\(error?.localizedDescription ?? "nil", privacy: .public)")
            return
        }
        btLog.notice("[bt.didDisconnect] device=\"\(name, privacy: .public)\" uuid=\(peripheral.identifier.uuidString, privacy: .public) error=\(error?.localizedDescription ?? "nil", privacy: .public)")
        connectedDeviceNames.remove(name)
        onDeviceEvent?(.disconnected(deviceName: name))

        // Attempt to reconnect for continued monitoring
        if centralManager?.state == .poweredOn {
            btLog.notice("[bt.didDisconnect.reconnect_attempt] device=\"\(name, privacy: .public)\"")
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        let count = (retryCount[id] ?? 0) + 1
        let name = peripheral.name ?? "<unnamed>"
        guard count <= Self.maxRetries else {
            btLog.notice("[bt.didFailToConnect.give_up] device=\"\(name, privacy: .public)\" retries=\(count - 1, privacy: .public) error=\(error?.localizedDescription ?? "nil", privacy: .public)")
            retryCount.removeValue(forKey: id)
            return
        }
        retryCount[id] = count
        let delay = TimeInterval(count * 5) // backoff: 5s, 10s, 15s
        btLog.notice("[bt.didFailToConnect.retry] device=\"\(name, privacy: .public)\" attempt=\(count, privacy: .public) delay_s=\(Int(delay), privacy: .public) error=\(error?.localizedDescription ?? "nil", privacy: .public)")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard self?.centralManager?.state == .poweredOn else { return }
            central.connect(peripheral, options: nil)
        }
    }

    // MARK: - State Restoration

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
        btLog.notice("[bt.willRestoreState] restored_peripherals=\(peripherals.count, privacy: .public)")
        for peripheral in peripherals {
            btLog.notice("[bt.willRestoreState.peripheral] name=\"\(peripheral.name ?? "<nil>", privacy: .public)\" uuid=\(peripheral.identifier.uuidString, privacy: .public)")
            monitoredPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = nil
        }
    }
}
