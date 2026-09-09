import CoreLocation

/// Shared geometry utilities for route simplification.
enum GeometryUtils {

    // MARK: - Курс

    /// Насколько разошлись два курса, с учётом того, что 359° и 1° — соседи.
    /// Отрицательный курс у CoreLocation значит «не знаю»; тогда разницы нет.
    static func courseDelta(_ a: Double, _ b: Double) -> Double {
        guard a >= 0, b >= 0 else { return 0 }
        var delta = abs(a - b).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta = 360 - delta }
        return delta
    }

    // MARK: - Ramer-Douglas-Peucker

    /// Simplify a polyline using the Ramer-Douglas-Peucker algorithm.
    /// Epsilon is in degrees (~0.00003 ≈ 3m at mid-latitudes).
    static func simplifyRDP(
        _ coords: [CLLocationCoordinate2D],
        epsilon: Double
    ) -> [CLLocationCoordinate2D] {
        guard coords.count > 2,
              let first = coords.first,
              let last = coords.last else { return coords }

        var maxDist = 0.0
        var maxIndex = 0

        for i in 1..<(coords.count - 1) {
            let d = perpendicularDistance(point: coords[i], lineStart: first, lineEnd: last)
            if d > maxDist {
                maxDist = d
                maxIndex = i
            }
        }

        if maxDist > epsilon {
            let left = simplifyRDP(Array(coords[...maxIndex]), epsilon: epsilon)
            let right = simplifyRDP(Array(coords[maxIndex...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    // MARK: - Выборка по значимости формы

    /// Выбрать ровно `budget` точек так, чтобы форма пострадала меньше всего.
    ///
    /// Отличается от «каждой N-й» тем, на что тратит бюджет. Равномерная
    /// выборка отмеряет точки по счёту, а счёт с 0.6.5 идёт по времени — то
    /// есть прямая и разворот получают поровну. На часовой поездке это одна
    /// точка в двенадцать секунд: разворот в три приёма укладывается в две,
    /// и в реплее двор пролетает по прямой.
    ///
    /// Здесь точки раздаются туда, где линия ВЫГИБАЕТСЯ. Берём самый
    /// выпирающий участок, ставим точку в его вершину, участок распадается на
    /// два — и так пока не кончится бюджет. Прямая съедает одну точку на
    /// любую длину, а на серию манёвров уходит столько, сколько там углов.
    ///
    /// Тот же приём, что у Дугласа-Пёкера, но с другого конца: тот отвечает на
    /// «какая ошибка допустима», а здесь ответ нужен на «сколько точек можно» —
    /// когда потолок задан не глазом, а ценой отрисовки.
    static func significantIndices(
        _ coords: [CLLocationCoordinate2D],
        budget: Int
    ) -> [Int] {
        guard coords.count > budget, budget >= 2 else { return Array(coords.indices) }

        struct Segment {
            let start: Int
            let end: Int
            let peak: Int
            let deviation: Double
        }

        func segment(from start: Int, to end: Int) -> Segment? {
            guard end - start > 1 else { return nil }
            var peak = start + 1
            var deviation = -1.0
            for i in (start + 1)..<end {
                let d = perpendicularDistance(point: coords[i], lineStart: coords[start], lineEnd: coords[end])
                if d > deviation {
                    deviation = d
                    peak = i
                }
            }
            return Segment(start: start, end: end, peak: peak, deviation: deviation)
        }

        var kept: Set<Int> = [0, coords.count - 1]
        var pending: [Segment] = []
        if let whole = segment(from: 0, to: coords.count - 1) { pending.append(whole) }

        while kept.count < budget, !pending.isEmpty {
            var worst = 0
            for i in 1..<pending.count where pending[i].deviation > pending[worst].deviation {
                worst = i
            }
            let chosen = pending.remove(at: worst)
            // Ровная линия: делить дальше нечего, остаток бюджета не нужен.
            guard chosen.deviation > 0 else { break }

            kept.insert(chosen.peak)
            if let left = segment(from: chosen.start, to: chosen.peak) { pending.append(left) }
            if let right = segment(from: chosen.peak, to: chosen.end) { pending.append(right) }
        }

        return kept.sorted()
    }

    /// Simplify coordinates and return the kept indices (useful when parallel arrays like speeds must stay aligned).
    static func simplifyIndices(
        _ coords: [CLLocationCoordinate2D],
        startIndex: Int,
        endIndex: Int,
        epsilon: Double
    ) -> Set<Int> {
        guard endIndex - startIndex > 1 else {
            return [startIndex, endIndex]
        }

        var maxDist = 0.0
        var maxIndex = startIndex

        for i in (startIndex + 1)..<endIndex {
            let d = perpendicularDistance(point: coords[i], lineStart: coords[startIndex], lineEnd: coords[endIndex])
            if d > maxDist {
                maxDist = d
                maxIndex = i
            }
        }

        if maxDist > epsilon {
            let left = simplifyIndices(coords, startIndex: startIndex, endIndex: maxIndex, epsilon: epsilon)
            let right = simplifyIndices(coords, startIndex: maxIndex, endIndex: endIndex, epsilon: epsilon)
            return left.union(right)
        } else {
            return [startIndex, endIndex]
        }
    }

    /// Default gap threshold in meters for splitting routes into segments.
    static let defaultGapThreshold: Double = 1_000

    // MARK: - Gap Splitting

    /// Split a coordinate array into continuous segments, breaking at gaps > threshold meters.
    /// Uses Haversine formula to avoid CLLocation allocations.
    static func splitByGaps(
        _ coords: [CLLocationCoordinate2D],
        threshold: Double
    ) -> [[CLLocationCoordinate2D]] {
        guard coords.count >= 2 else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = [coords[0]]
        for i in 1..<coords.count {
            if haversineDistance(coords[i - 1], coords[i]) > threshold {
                if current.count >= 2 { segments.append(current) }
                current = [coords[i]]
            } else {
                current.append(coords[i])
            }
        }
        if current.count >= 2 { segments.append(current) }
        return segments
    }

    /// Haversine distance in meters between two coordinates.
    static func haversineDistance(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        let R = 6_371_000.0 // Earth radius in meters
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    // MARK: - Perpendicular Distance

    /// Distance from a point to a line segment defined by two endpoints, in coordinate degrees.
    static func perpendicularDistance(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        let lenSq = dx * dx + dy * dy

        guard lenSq > 0 else {
            let px = point.longitude - lineStart.longitude
            let py = point.latitude - lineStart.latitude
            return sqrt(px * px + py * py)
        }

        let t = max(0, min(1, (
            (point.longitude - lineStart.longitude) * dx +
            (point.latitude - lineStart.latitude) * dy
        ) / lenSq))

        let px = point.longitude - (lineStart.longitude + t * dx)
        let py = point.latitude - (lineStart.latitude + t * dy)
        return sqrt(px * px + py * py)
    }
}
