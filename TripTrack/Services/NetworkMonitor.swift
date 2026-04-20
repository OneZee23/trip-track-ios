import Foundation
import Network
import Combine

/// Монитор сетевого подключения
class NetworkMonitor: ObservableObject {
    @Published var isOffline = false
    @Published var isOnWiFi: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOffline = path.status != .satisfied
                self?.isOnWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: queue)

        // Проверяем сразу
        let path = monitor.currentPath
        isOffline = path.status != .satisfied
        isOnWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
    }
    
    deinit {
        monitor.cancel()
    }
}
