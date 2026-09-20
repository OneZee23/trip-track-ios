import Foundation

/// «420 км · 5 ч 30 мин · вчера 09:00» — итог на кнопке «Записать». Части
/// приходят уже напечатанными (расстояние — из `Measure`, время в пути и
/// дата — своими форматтерами): эта функция только их соединяет, чтобы
/// разделитель между частями был один на всё приложение, а не переизобретён
/// в каждом месте показа.
enum ManualTripSummaryLine {
    static func compose(distance: String, duration: String, when: String) -> String {
        [distance, duration, when].joined(separator: " · ")
    }
}
