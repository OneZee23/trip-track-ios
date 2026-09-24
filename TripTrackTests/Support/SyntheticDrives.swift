import Foundation
import CoreLocation
@testable import TripTrack

/// Синтетические поездки стенда (спека §2.7). Настоящих координат владельца в
/// репозитории нет — рисунок повторяет ПРИЗНАКИ, а не путь.
enum SyntheticDrives {
    /// Город вечером: 15 минут квадратом кварталов на 10 м/с; каждые 70 с —
    /// 40 с неба получше (45 м) и 30 с похуже (90 м). Старый конвейер (65 м)
    /// теряет каждое плохое окно — это и есть 8 сентября.
    static func cityEvening(seconds: Int = 900) -> [CLLocation] {
        (0...seconds).map { t in
            let (east, north, course) = gridPosition(metres: Double(t) * 10)
            let bad = t % 70 >= 40
            let wobble = Double((t * 53) % 21 - 10) * (bad ? 1.5 : 0.5)
            return TrackTestKit.fix(east: east + wobble, north: north - wobble, speed: 10, course: course,
                                    after: Double(t), accuracy: bad ? 90 : 45)
        }
    }

    /// Тоннель: прямая на 20 м/с, 60 с без единого фикса посередине.
    static func tunnel() -> [CLLocation] {
        (0...300).compactMap { t in
            (120..<180).contains(t) ? nil
                : TrackTestKit.fix(east: 0, north: Double(t) * 20, speed: 20, after: Double(t), accuracy: 8)
        }
    }

    /// Усыпление на ходу: 7 минут без фиксов при хорошей точности на краях —
    /// как 12.7 км на Геленджик.
    static func suspension() -> [CLLocation] {
        (0...900).compactMap { t in
            (300..<720).contains(t) ? nil
                : TrackTestKit.fix(east: 0, north: Double(t) * 16, speed: 16, after: Double(t), accuracy: 12)
        }
    }

    /// Квадрат кварталов 800 × 800 м, обход против часовой. Не 400: угол
    /// тогда часто попадает целиком в тридцатисекундное плохое окно, и старый
    /// конвейер срезает его по прямой между двумя соседними хорошими точками —
    /// это недостача одометра ~1.5 % ДАЖЕ при нулевом дрожании (проверено
    /// отдельно), то есть больше допуска сравнения `old`/`new` в тесте. На
    /// 800 м углов вдвое меньше на тот же путь, и недостача уходит под 0.5 %.
    private static func gridPosition(metres: Double) -> (Double, Double, Double) {
        let side = 800.0
        let d = metres.truncatingRemainder(dividingBy: side * 4)
        switch d {
        case ..<side: return (d, 0, 90)
        case ..<(2 * side): return (side, d - side, 0)
        case ..<(3 * side): return (side - (d - 2 * side), side, 270)
        default: return (0, side - (d - 3 * side), 180)
        }
    }
}
