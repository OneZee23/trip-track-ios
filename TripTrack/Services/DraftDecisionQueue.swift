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
///
/// Порядок записей — по времени постановки (ревью раунда 1, пункт 5):
/// `applyDraftDecisions` разбирает очередь по одной — подсмотрел голову
/// (`peek`), применил, убрал (`remove`), — а без порядка «голова» была бы не
/// определена. `NSLock` защищает чтение-правку-запись `UserDefaults`:
/// `enqueue` зовут из делегата уведомлений, который система вправе вызвать не
/// на главном потоке, а `peek`/`remove`/`drain` — с главного актёра
/// (`MapViewModel`). Ни один метод не `async`, поэтому лock не держится через
/// `await` — то, что уже стоило починки `CachedSecretCatalog` (см. CLAUDE.md).
final class DraftDecisionQueue {
    static let shared = DraftDecisionQueue()
    private static let key = "draftTrips.pendingDecisions"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Последнее решение по поездке побеждает; позиция остальных записей не
    /// меняется.
    func enqueue(_ tripId: UUID, _ decision: DraftDecision) {
        lock.lock()
        defer { lock.unlock() }
        var list = read()
        if let idx = list.firstIndex(where: { $0.0 == tripId.uuidString }) {
            list[idx].1 = decision.rawValue
        } else {
            list.append((tripId.uuidString, decision.rawValue))
        }
        write(list)
    }

    /// Самая старая ещё не применённая запись — БЕЗ удаления из очереди.
    func peek() -> (UUID, DraftDecision)? {
        lock.lock()
        defer { lock.unlock() }
        for (idString, decisionString) in read() {
            if let id = UUID(uuidString: idString), let decision = DraftDecision(rawValue: decisionString) {
                return (id, decision)
            }
        }
        return nil
    }

    /// Убрать ОДНУ запись — после того как её решение применено или
    /// осознанно отброшено.
    func remove(_ tripId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var list = read()
        list.removeAll { $0.0 == tripId.uuidString }
        write(list)
    }

    /// Все записи разом, с очисткой очереди целиком. Держится ради обратной
    /// совместимости своих тестов — `MapViewModel.applyDraftDecisions`
    /// разбирает очередь через `peek`/`remove`, по одной.
    func drain() -> [(UUID, DraftDecision)] {
        lock.lock()
        defer { lock.unlock() }
        let list = read()
        write([])
        return list.compactMap { idString, decisionString in
            guard let id = UUID(uuidString: idString), let d = DraftDecision(rawValue: decisionString) else { return nil }
            return (id, d)
        }
    }

    /// Плист-совместимый массив пар `[id, decision]` — упорядоченный, в
    /// отличие от словаря, которым записи хранились до раунда 1.
    private func read() -> [(String, String)] {
        let raw = defaults.array(forKey: Self.key) as? [[String]] ?? []
        return raw.compactMap { pair in pair.count == 2 ? (pair[0], pair[1]) : nil }
    }

    private func write(_ list: [(String, String)]) {
        if list.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(list.map { [$0.0, $0.1] }, forKey: Self.key)
        }
    }
}
