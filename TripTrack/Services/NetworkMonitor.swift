import Foundation
import Network
import Combine

/// Монитор сетевого подключения
class NetworkMonitor: ObservableObject {
    @Published var isOffline = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: queue)
        
        // Проверяем сразу
        let path = monitor.currentPath
        isOffline = path.status != .satisfied
    }
    
    deinit {
        monitor.cancel()
    }
}
