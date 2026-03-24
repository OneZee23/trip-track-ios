import SwiftUI
import MapKit
import CoreLocation

/// Кастомный маркер позиции с направлением
struct PositionMarker: View {
    let coordinate: CLLocationCoordinate2D
    let heading: Double
    let isSimulated: Bool
    
    var body: some View {
        ZStack {
            // Внешнее свечение
            Circle()
                .fill((isSimulated ? Color.orange : Color.blue).opacity(0.2))
                .frame(width: 40, height: 40)
            
            // Средний круг
            Circle()
                .fill(.white)
                .frame(width: 24, height: 24)
            
            // Внутренний круг
            Circle()
                .fill(isSimulated ? .orange : .blue)
                .frame(width: 18, height: 18)
            
            // Стрелка направления
            Image(systemName: "location.north.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(heading))
        }
    }
}

/// Для использования на карте (iOS 17+)
@available(iOS 17, *)
struct PositionAnnotation: MapContent {
    let location: LocationUpdate?
    let isSimulated: Bool
    
    var body: some MapContent {
        if let loc = location {
            Annotation("", coordinate: loc.coordinate) {
                PositionMarker(
                    coordinate: loc.coordinate,
                    heading: loc.course,
                    isSimulated: isSimulated
                )
            }
        }
    }
}
