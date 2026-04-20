import Foundation
import Combine

/// Central cache manager — owns all caching layers and NetworkMonitor.
/// Future sync boundary: when backend is added, this becomes the single point
/// for tracking "what changed locally since last sync".
final class CacheManager: ObservableObject {
    static let shared = CacheManager()

    let networkMonitor = NetworkMonitor()

    /// Fires once when network transitions from offline → online.
    /// Services subscribe to this for retry logic (e.g., geocoding).
    let networkRestored: AnyPublisher<Void, Never>

    /// Fires when Wi-Fi transitions from disconnected → connected (ignores initial value).
    let wifiConnected: AnyPublisher<Void, Never>

    var isOffline: Bool {
        networkMonitor.isOffline
    }

    var isOnWiFi: Bool {
        networkMonitor.isOnWiFi
    }

    private init() {
        networkRestored = networkMonitor.$isOffline
            .removeDuplicates()
            .filter { !$0 }
            .dropFirst()
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()

        wifiConnected = networkMonitor.$isOnWiFi
            .removeDuplicates()
            .filter { $0 }
            .dropFirst()
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
