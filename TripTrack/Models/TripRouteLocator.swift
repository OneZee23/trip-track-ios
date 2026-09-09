import Foundation
import CoreLocation

/// Где на маршруте находится это место — и сколько до него от старта.
///
/// Отвечает на вопрос, ради которого затевались контрольные точки: «сколько
/// времени и километров до моря». Одна и та же считалка обслуживает три случая:
/// палец по карте на записанной поездке, кнопку на Live Activity на ходу и
/// фотографию, которую надо поставить на маршрут по времени съёмки.
enum TripRouteLocator {

    /// Найденное место на треке.
    struct Fix: Equatable {
        /// Индекс точки трека — по нему UI достаёт всё остальное.
        let index: Int
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
        /// Метры от старта ПО ТРЕКУ, а не по прямой.
        let distanceFromStart: Double
        let elapsedFromStart: TimeInterval

        static func == (lhs: Fix, rhs: Fix) -> Bool {
            lhs.index == rhs.index
        }
    }

    /// Ближе этого к пальцу — считаем попаданием в маршрут.
    static let tapRadius: Double = 120

    /// Два попадания считаются РАЗНЫМИ проездами, если между ними столько времени.
    ///
    /// Дорога «туда и обратно» рисуется по одним и тем же улицам, и палец, ткнутый
    /// у моря, попадает сразу в оба проезда. Геометрия их не различает вовсе —
    /// различает только время.
    static let distinctPassGap: TimeInterval = 10 * 60

    // MARK: - По месту

    /// Все проезды маршрута рядом с этой точкой, по времени.
    ///
    /// Возвращает список, а не один ответ, именно из-за «туда и обратно»: выбрать
    /// за человека, какой из двух проездов он имел в виду, нельзя — 2:14 и 5:30
    /// это разные ответы на его вопрос. Один элемент в списке значит, что
    /// выбирать не из чего.
    static func passes(
        near coordinate: CLLocationCoordinate2D,
        in points: [TrackPoint],
        radius: Double = tapRadius,
        startDate: Date? = nil
    ) -> [Fix] {
        guard points.count > 1 else { return [] }

        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let prefix = distancePrefix(points)
        let origin = startDate ?? points[0].timestamp

        // Ближайшая точка в каждом отдельном проезде: идём по треку и держим
        // лучшего кандидата, пока попадания идут подряд по времени.
        var result: [Fix] = []
        var bestIndex: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        var lastHitTime: Date?

        func flush() {
            guard let index = bestIndex else { return }
            result.append(fix(at: index, in: points, prefix: prefix, origin: origin))
            bestIndex = nil
            bestDistance = .greatestFiniteMagnitude
        }

        for (i, point) in points.enumerated() {
            let metres = target.distance(
                from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            guard metres <= radius else { continue }

            if let last = lastHitTime,
               point.timestamp.timeIntervalSince(last) > distinctPassGap {
                flush()
            }
            lastHitTime = point.timestamp

            if metres < bestDistance {
                bestDistance = metres
                bestIndex = i
            }
        }
        flush()

        return result
    }

    // MARK: - По времени

    /// Где мы были в этот момент. Для кнопки на ходу и для фотографии.
    ///
    /// Момент вне поездки ответа не имеет: снимок, сделанный назавтра, не
    /// принадлежит маршруту, и ставить его на трек нельзя.
    /// `startDate` — старт поездки как его знает сама поездка. Живая отметка
    /// считает время от `entity.startDate`, и если считать здесь от первой точки,
    /// у автопоездки (старт отодвигается назад при обнаружении) два пути дали
    /// бы два разных времени для одного места.
    static func fix(at moment: Date, in points: [TrackPoint], startDate: Date? = nil) -> Fix? {
        guard let first = points.first, let last = points.last else { return nil }
        guard moment >= first.timestamp, moment <= last.timestamp else { return nil }

        // Точки идут по времени, поэтому двоичный поиск.
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp < moment { low = mid + 1 } else { high = mid }
        }
        // Соседняя точка может оказаться ближе по времени.
        var index = low
        if index > 0 {
            let before = moment.timeIntervalSince(points[index - 1].timestamp)
            let after = points[index].timestamp.timeIntervalSince(moment)
            if before < after { index -= 1 }
        }
        return fix(at: index, in: points, prefix: distancePrefix(points), origin: startDate ?? first.timestamp)
    }

    // MARK: - Общее

    /// Накопленный путь до каждой точки — тем же пятиметровым шагом, каким
    /// считается одометр поездки.
    ///
    /// Иначе «до моря 143 км» и «всего 210 км» жили бы по разным правилам, и
    /// сумма отрезков не сходилась бы с итогом. Считается один раз на весь трек:
    /// отметок и фотографий на поездке бывает много.
    static func distancePrefix(_ points: [TrackPoint]) -> [Double] {
        var prefix = [Double](repeating: 0, count: points.count)
        guard points.count > 1 else { return prefix }

        var total: Double = 0
        var anchor = points[0]
        for i in 1..<points.count {
            let metres = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                .distance(from: CLLocation(latitude: points[i].latitude, longitude: points[i].longitude))
            if metres >= TripDistanceGate.minStep {
                let dt = points[i].timestamp.timeIntervalSince(anchor.timestamp)
                if TripDistanceGate.isPlausibleSegment(meters: metres, dt: dt) {
                    total += metres
                }
                anchor = points[i]
            }
            prefix[i] = total
        }
        return prefix
    }

    static func fix(at index: Int, in points: [TrackPoint], prefix: [Double], origin: Date? = nil) -> Fix {
        let point = points[index]
        return Fix(
            index: index,
            coordinate: point.coordinate,
            timestamp: point.timestamp,
            distanceFromStart: prefix[index],
            elapsedFromStart: max(0, point.timestamp.timeIntervalSince(origin ?? points[0].timestamp))
        )
    }
}
