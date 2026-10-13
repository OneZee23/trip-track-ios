import CoreGraphics
import SwiftUI

/// Правила жеста нижней панели — ОДНИ на «Атлас» и «Места».
///
/// Числа здесь общие не для экономии: человек учит жест один раз и переносит
/// его с вкладки на вкладку. Разойдись пороги — и шторка «Мест» отвечала бы
/// на тот же бросок иначе, чем шторка «Атласа», а объяснить это было бы
/// нечем. То же соображение, по которому таб-бар в 0.8.1 свели к одному:
/// два имени одного числа однажды расходятся.
enum SlotGesture {
    /// Скорость, с которой отпущенная панель летит по направлению жеста к
    /// соседнему положению, а не к ближайшему.
    static let flickVelocity: CGFloat = 300

    /// Сопротивление за границей: панель идёт втрое медленнее пальца.
    static let rubber: CGFloat = 0.3

    /// Доля пути между соседними положениями, на которой стоит граница.
    ///
    /// 45 %, а не половина: раскрыть список должно быть легче, чем закрыть.
    static let settleThreshold: CGFloat = 0.45

    /// Пружина всего нижнего. «Уменьшить движение» заменяет её кроссфейдом.
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.86)
    static let reducedMotion = Animation.easeOut(duration: 0.2)

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedMotion : spring
    }

    /// Граница между двумя соседними положениями.
    ///
    /// `from` — нижнее (число больше), `to` — верхнее.
    static func boundary(from: CGFloat, to: CGFloat) -> CGFloat {
        from - (from - to) * settleThreshold
    }

    /// Верх панели при пальце, утащившем её за границы.
    static func clamped(_ top: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        if top < upper { return upper - (upper - top) * rubber }
        if top > lower { return lower + (top - lower) * rubber }
        return top
    }
}
