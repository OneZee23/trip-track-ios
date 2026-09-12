import Foundation

/// История места, посчитанная из проездов — на лету, нигде не хранится
/// (иначе счёт разошёлся бы с проездами, как одометр до `TripDistanceGate`).
struct PlaceStats: Equatable {

    /// Одно направление движения через место: «→ к морю 2:14 · 5 проездов».
    struct Direction: Equatable {
        /// Курс-представитель группы, градусы.
        let course: Double
        let count: Int
        /// Медиана `elapsedFromStart` — «обычно занимает от старта поездки».
        let median: TimeInterval
        let best: TimeInterval
        let worst: TimeInterval
        let lastAt: Date
    }

    let passCount: Int
    let firstAt: Date?
    let lastAt: Date?
    /// Ровно один проезд — «первый раз здесь».
    var isFirstTime: Bool { passCount == 1 }
    /// ≥ `frequentGuestPasses` проездов за `frequentGuestWindow` — «частый
    /// гость». Подпись, не награда: опыта и значков это не даёт.
    let isFrequentGuest: Bool
    /// По числу проездов, потом по свежести.
    let directions: [Direction]

    /// «Одно направление» — курс в ±45° от курса самого свежего проезда группы.
    static let directionTolerance: Double = 45
    static let frequentGuestPasses = 5
    static let frequentGuestWindow: TimeInterval = 90 * 86_400

    static func build(from passes: [PlacePass], now: Date = Date()) -> PlaceStats {
        let sorted = passes.sorted { $0.timestamp < $1.timestamp }
        let recent = passes.filter { now.timeIntervalSince($0.timestamp) <= frequentGuestWindow }.count
        return PlaceStats(
            passCount: passes.count,
            firstAt: sorted.first?.timestamp,
            lastAt: sorted.last?.timestamp,
            isFrequentGuest: recent >= frequentGuestPasses,
            directions: cluster(passes))
    }

    /// Группировка по курсу. Опорный курс каждой группы — курс самого свежего
    /// ещё не разобранного проезда: то, как человек ездит СЕЙЧАС, важнее
    /// того, как ездил год назад. Проезды без курса в группы не попадают.
    private static func cluster(_ passes: [PlacePass]) -> [Direction] {
        var pool = passes.filter(\.hasCourse).sorted { $0.timestamp > $1.timestamp }
        var result: [Direction] = []
        while let anchor = pool.first {
            let group = pool.filter { angularDistance($0.course, anchor.course) <= directionTolerance }
            pool.removeAll { g in group.contains { $0.id == g.id } }
            let times = group.map(\.elapsedFromStart).sorted()
            result.append(Direction(
                course: anchor.course, count: group.count,
                median: median(times), best: times[0], worst: times[times.count - 1],
                lastAt: anchor.timestamp))
        }
        return result.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.lastAt > $1.lastAt
        }
    }

    private static func median(_ sorted: [TimeInterval]) -> TimeInterval {
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    /// Разница курсов по короткой дуге, 0…180.
    static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}
