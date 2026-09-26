import Foundation
import CoreLocation

/// Экран места, приведённый к тому, что рисует вёрстка (макет «Места» 0.8.1,
/// S4): плитки дней, подпись «откуда → куда» и сколько проездов показывать
/// сразу. Чистыми функциями — те же соображения, что у `PlacesPresentation`:
/// «что человек увидит» проверяется числом, а открытым экраном проверяется
/// только то, что он не упал.
enum PlaceScreen {

    /// Плитка «Последних проездов»: ДЕНЬ, а не проезд.
    ///
    /// «Туда и обратно» в одно воскресенье — это один день с двумя проездами,
    /// и две одинаковые плитки «13 сент.» подряд читались бы сбоем показа.
    struct DateTile: Identifiable, Equatable {
        /// Начало дня — по нему плитка и подписывается.
        let day: Date
        /// Сколько проездов в этот день. Единица подписи не получает: «1 раз»
        /// под каждой плиткой — четыре одинаковых слова в ряд ни о чём.
        let count: Int
        var id: Date { day }
    }

    /// Плиток ровно пять: шестая не влезает в ширину экрана, не сжав число до
    /// нечитаемого, а пять дней — это уже «как часто я тут бываю».
    static let dateTiles = 5

    /// Проездов в списке до «Все N проездов». Пять — столько же, сколько
    /// плиток дней: список сразу под ними, и два разных числа рядом просили бы
    /// их сравнивать.
    static let visiblePasses = 5

    /// Последние дни с проездами, свежие первыми.
    static func tiles(from passes: [PlacePass], calendar: Calendar = .current,
                      limit: Int = dateTiles) -> [DateTile] {
        var counts: [Date: Int] = [:]
        for pass in passes {
            let day = calendar.startOfDay(for: pass.timestamp)
            counts[day, default: 0] += 1
        }
        return counts.keys.sorted(by: >).prefix(limit).map { DateTile(day: $0, count: counts[$0] ?? 0) }
    }

    /// «Краснодар → Горячий Ключ» — концы поездки этого проезда.
    ///
    /// Оба конца в одном городе дают ОДНО имя без стрелки: круг по городу с
    /// возвратом во двор — это не дорога из Краснодара в Краснодар, и стрелка
    /// между двумя одинаковыми словами обещает путь, которого нет. Ни одного
    /// имени в кэше геокодера — `nil`, и строка падает на дату: координата из
    /// семи знаков вместо города не объясняет ничего (правило 0.8.0).
    static func route(from start: String?, to end: String?) -> String? {
        let a = start?.trimmingCharacters(in: .whitespaces)
        let b = end?.trimmingCharacters(in: .whitespaces)
        switch (a?.isEmpty == false ? a : nil, b?.isEmpty == false ? b : nil) {
        case let (from?, to?): return from == to ? from : "\(from) → \(to)"
        case let (from?, nil): return from
        case let (nil, to?): return to
        case (nil, nil): return nil
        }
    }

    /// Концы поездки, по которым подписывается проезд. Берутся у превью — те
    /// же первая и последняя точки, что читает подсказка мест (0.8.0): точек
    /// поездки ради подписи в списке не поднимают.
    static func endpoints(of preview: [CLLocationCoordinate2D])
    -> (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)? {
        guard let start = preview.first, let end = preview.last, preview.count > 1 else { return nil }
        return (start, end)
    }
}
