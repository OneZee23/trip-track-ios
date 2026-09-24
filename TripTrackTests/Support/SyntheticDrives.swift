import Foundation
import CoreLocation
@testable import TripTrack

/// Синтетические поездки стенда (спека §2.7). Настоящих координат владельца в
/// репозитории нет — рисунок повторяет ПРИЗНАКИ, а не путь.
enum SyntheticDrives {
    /// Город вечером: 15 минут квадратом кварталов (по умолчанию 800 × 800 м)
    /// на 10 м/с; каждые 70 с — 40 с неба получше (45 м) и 30 с похуже (90 м).
    /// `side: 400` — для сравнения с настоящим путём в `TrackReplayTests`.
    ///
    /// Старый конвейер (65 м) отбрасывает грубый фикс ДО фильтра — это и есть
    /// 8 сентября. Новый его не отбрасывает: `TripManager.handleNewLocation`
    /// кормит фильтром КАЖДЫЙ принятый фикс (~707-я строка), грубые тоже, а
    /// хранимая позиция доверенной точки — это позиция ФИЛЬТРА, а не сырая.
    /// Если угол квадрата целиком лежит внутри плохого окна, старый конвейер
    /// тридцать секунд едет по прямой (фильтр не видел ничего между двумя
    /// хорошими точками по разные стороны угла), а новый огибает тот же угол
    /// по грубым фиксам — и огибает ВЕРНЕЕ: на кварталах 400 м новый читает
    /// примерно на 1.5 % больше старого, и это расхождение — в сторону
    /// настоящего пути (`SyntheticDrives.trueDistance`), а не от него
    /// (решение владельца по спеке §2.2; держит `TrackReplayTests`).
    static func cityEvening(seconds: Int = 900, side: Double = 800) -> [CLLocation] {
        (0...seconds).map { t in
            let (east, north, course) = gridPosition(metres: Double(t) * 10, side: side)
            let bad = t % 70 >= 40
            let wobble = Double((t * 53) % 21 - 10) * (bad ? 1.5 : 0.5)
            return TrackTestKit.fix(east: east + wobble, north: north - wobble, speed: 10, course: course,
                                    after: Double(t), accuracy: bad ? 90 : 45)
        }
    }

    /// Путь, который машина проехала НА САМОМ ДЕЛЕ — без дыр, без дрожания,
    /// без фильтра: 10 м/с × время. Точка сравнения для `side: 400`: одометр
    /// обязан приближаться к этому числу, а не удаляться от него.
    static func trueDistance(seconds: Int = 900) -> Double { Double(seconds) * 10 }

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

    /// Позиция на квадратном кольце стороной `side`, обход против часовой.
    private static func gridPosition(metres: Double, side: Double) -> (Double, Double, Double) {
        let d = metres.truncatingRemainder(dividingBy: side * 4)
        switch d {
        case ..<side: return (d, 0, 90)
        case ..<(2 * side): return (side, d - side, 0)
        case ..<(3 * side): return (side - (d - 2 * side), side, 270)
        default: return (0, side - (d - 3 * side), 180)
        }
    }
}
