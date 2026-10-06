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

    /// Immutable route snapshot for several lookups on the same trip. The
    /// odometer prefix belongs to the route, not to each photo that asks for it.
    struct Index {
        private let points: [TrackPoint]
        private let prefix: [Double]
        private let startDate: Date?

        init(points: [TrackPoint], startDate: Date? = nil) {
            self.points = points
            self.prefix = TripRouteLocator.distancePrefix(points)
            self.startDate = startDate
        }

        func passes(near coordinate: CLLocationCoordinate2D, radius: Double = TripRouteLocator.tapRadius) -> [Fix] {
            TripRouteLocator.passes(near: coordinate, in: points, prefix: prefix,
                                    radius: radius, startDate: startDate)
        }

        func fix(at moment: Date) -> Fix? {
            TripRouteLocator.fix(at: moment, in: points, prefix: prefix, startDate: startDate)
        }

        /// Keep the existing reading rule: EXIF's first nearby pass, then
        /// capture time if that coordinate has no pass on this trip.
        func fix(for photo: TripPhoto) -> Fix? {
            if let coordinate = photo.exifCoordinate,
               let pass = passes(near: coordinate, radius: 300).first {
                return pass
            }
            return photo.capturedAt.flatMap { fix(at: $0) }
        }
    }

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
        return passes(near: coordinate, in: points, prefix: distancePrefix(points),
                      radius: radius, startDate: startDate)
    }

    private static func passes(
        near coordinate: CLLocationCoordinate2D,
        in points: [TrackPoint],
        prefix: [Double],
        radius: Double,
        startDate: Date?
    ) -> [Fix] {
        guard points.count > 1 else { return [] }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
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
        guard let first = points.first, let last = points.last,
              moment >= first.timestamp, moment <= last.timestamp else { return nil }
        return fix(at: moment, in: points, prefix: distancePrefix(points), startDate: startDate)
    }

    private static func fix(at moment: Date, in points: [TrackPoint], prefix: [Double], startDate: Date?) -> Fix? {
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
        return fix(at: index, in: points, prefix: prefix, origin: startDate ?? first.timestamp)
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

        // Якорь — только точка, которой одометр верит. Грубые и достроенные
        // получают накопленное к ним число, но сами его не двигают: иначе
        // «до моря 143 км» у отметки разошлось бы с «всего 210 км» поездки.
        guard var anchorIndex = points.firstIndex(where: \.countsForDistance) else { return prefix }
        var total: Double = 0
        for i in (anchorIndex + 1)..<points.count {
            defer { prefix[i] = total }
            guard points[i].countsForDistance else { continue }
            let anchor = points[anchorIndex]
            guard points[i].recordingSegmentIndex == anchor.recordingSegmentIndex else {
                anchorIndex = i
                continue
            }
            let metres = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                .distance(from: CLLocation(latitude: points[i].latitude, longitude: points[i].longitude))
            if metres >= TripDistanceGate.minStep {
                let dt = points[i].timestamp.timeIntervalSince(anchor.timestamp)
                if TripDistanceGate.isPlausibleSegment(meters: metres, dt: dt) {
                    total += metres
                }
                anchorIndex = i
            }
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
