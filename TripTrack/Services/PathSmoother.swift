import Foundation
import CoreLocation

/// Сглаживание траектории с помощью Catmull-Rom сплайнов
struct PathSmoother {
    static func smooth(
        points: [CLLocationCoordinate2D],
        segmentsPerPoint: Int = 5
    ) -> [CLLocationCoordinate2D] {
        guard points.count >= 2 else { return points }
        
        // Если точек мало, просто возвращаем их
        if points.count < 4 {
            return points
        }
        
        var smoothed: [CLLocationCoordinate2D] = []
        
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[min(points.count - 1, i + 1)]
            let p3 = points[min(points.count - 1, i + 2)]
            
            for j in 0..<segmentsPerPoint {
                let t = Double(j) / Double(segmentsPerPoint)
                smoothed.append(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: t))
            }
        }
        
        if let last = points.last {
            smoothed.append(last)
        }
        
        return smoothed
    }
    
    private static func catmullRom(
        p0: CLLocationCoordinate2D,
        p1: CLLocationCoordinate2D,
        p2: CLLocationCoordinate2D,
        p3: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        let t2 = t * t
        let t3 = t2 * t
        
        let lat = 0.5 * (
            (2 * p1.latitude) +
            (-p0.latitude + p2.latitude) * t +
            (2 * p0.latitude - 5 * p1.latitude + 4 * p2.latitude - p3.latitude) * t2 +
            (-p0.latitude + 3 * p1.latitude - 3 * p2.latitude + p3.latitude) * t3
        )
        
        let lon = 0.5 * (
            (2 * p1.longitude) +
            (-p0.longitude + p2.longitude) * t +
            (2 * p0.longitude - 5 * p1.longitude + 4 * p2.longitude - p3.longitude) * t2 +
            (-p0.longitude + 3 * p1.longitude - 3 * p2.longitude + p3.longitude) * t3
        )
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
