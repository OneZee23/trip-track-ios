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

        // Начальное значение — ОПТИМИСТИЧНОЕ, и это не лень.
        //
        // `monitor.currentPath` сразу после `start` ещё не знает ответа и
        // отдаёт неудовлетворённый путь, то есть «офлайн» на долю секунды
        // после каждого запуска. Пока по этому флагу рисовался только баннер
        // «Ленты», цена была одним лишним кадром. С 0.8.2 по нему вкладка
        // «Места» подменяет плитки карты своей бумагой
        // (`canReplaceMapContent`), и ложный офлайн на старте оставлял карту
        // пустой (поймано кадром на симуляторе). Первое настоящее состояние
        // приносит `pathUpdateHandler` миллисекундами позже.
        isOnWiFi = monitor.currentPath.usesInterfaceType(.wifi)
    }
    
    deinit {
        monitor.cancel()
    }
}
