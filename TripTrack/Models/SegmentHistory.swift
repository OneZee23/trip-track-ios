import Foundation

/// История сегмента: «вы ехали этот отрезок 3 раза: 4:58, 5:12, 5:40» —
/// считает по проездам обеих его отметок, когда обе стали местами (0.6.8).
///
/// Ничего не хранится, как и у `TripSegmentMetrics`: проезды уже лежат в
/// `PlacePassEntity`, и второй счёт поверх них однажды разошёлся бы с первым.
enum SegmentHistory {

    /// Секунды каждого проезда отрезка по поездкам, по возрастанию.
    ///
    /// Для КАЖДОЙ поездки, где есть проезд обоих мест, берётся минимальная
    /// положительная разница между проездом `to` и более ранним проездом
    /// `from` — тот же приём, что «туда и обратно» даёт одно число, а не два:
    /// несколько проездов одного места внутри поездки (заезд в магазин и
    /// обратно) не должны раздувать историю сегмента лишними записями.
    /// Поездка, где ближайший проезд `to` раньше любого проезда `from` (ехали
    /// в обратную сторону), в результат не попадает.
    static func times(fromPasses: [PlacePass], toPasses: [PlacePass]) -> [TimeInterval] {
        let fromByTrip = Dictionary(grouping: fromPasses, by: \.tripId)
        let toByTrip = Dictionary(grouping: toPasses, by: \.tripId)

        var result: [TimeInterval] = []
        for (tripId, tos) in toByTrip {
            guard let froms = fromByTrip[tripId] else { continue }
            var best: TimeInterval?
            for to in tos {
                for from in froms {
                    let delta = to.elapsedFromStart - from.elapsedFromStart
                    guard delta > 0 else { continue }
                    if best == nil || delta < best! {
                        best = delta
                    }
                }
            }
            if let best {
                result.append(best)
            }
        }
        return result.sorted()
    }

    /// «4:58», «0:42», «12:05» — часы:минуты, минуты всегда двумя цифрами.
    /// Секунд здесь нет нарочно: история отвечает на «сколько это обычно
    /// занимает», и точность до секунды на дороге такого вопроса не бывает.
    ///
    /// Неполная минута ОТБРАСЫВАЕТСЯ, а не округляется: тем же счётом живут
    /// `Trip.formattedTimeHuman` и `CheckpointReading.clock`, и одно и то же
    /// число секунд обязано читаться одинаково во всех трёх местах — иначе
    /// история отрезка оказалась бы на минуту длиннее, чем «От старта» у его
    /// собственных отметок.
    static func clock(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
