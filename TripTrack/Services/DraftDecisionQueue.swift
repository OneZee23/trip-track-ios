import Foundation

enum DraftDecision: String, Codable {
    case confirm
    case discard
}

extension Notification.Name {
    /// В очередь легло решение по черновику — `MapViewModel` применит.
    static let draftTripDecisionQueued = Notification.Name("draftTripDecisionQueued")
    /// Черновик решён: подтверждён или удалён (`object` — `UUID` поездки).
    static let draftTripResolved = Notification.Name("draftTripResolved")
}

/// Решения по черновикам, пережившие перезапуск (Review Focus 3).
///
/// Кнопку уведомления нажимают и тогда, когда приложения нет на экране, а то и
/// в памяти. Решение ложится сюда, в `UserDefaults`, и применяется при
/// следующей встрече с `MapViewModel` — тот же приём, что у
/// `places.pendingHistory`.
final class DraftDecisionQueue {
    static let shared = DraftDecisionQueue()
    private static let key = "draftTrips.pendingDecisions"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Последнее решение по поездке побеждает.
    func enqueue(_ tripId: UUID, _ decision: DraftDecision) {
        var map = stored()
        map[tripId.uuidString] = decision.rawValue
        defaults.set(map, forKey: Self.key)
    }

    func drain() -> [(UUID, DraftDecision)] {
        let map = stored()
        defaults.removeObject(forKey: Self.key)
        return map.compactMap { key, value in
            guard let id = UUID(uuidString: key), let d = DraftDecision(rawValue: value) else { return nil }
            return (id, d)
        }
    }

    private func stored() -> [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}
