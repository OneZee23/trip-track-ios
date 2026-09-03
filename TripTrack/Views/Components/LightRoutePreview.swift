import SwiftUI
import MapKit

/// Lightweight route preview using Canvas instead of MKMapView.
/// Much faster to render in feed cards — no UIKit overhead.
struct LightRoutePreview: View {
    /// Один или несколько маршрутов в общей рамке.
    ///
    /// Несколько нужны карточке-входу «Карта» в чужом профиле (0.6.3): там это
    /// тизер всей карты, а не одной поездки. Реализация одна, потому что общая
    /// рамка, масштаб и упрощение у них ровно те же — форк дал бы два места,
    /// где маршрут рисуется по-разному.
    let routes: [[CLLocationCoordinate2D]]
    var accentColor: Color = .orange

    init(coordinates: [CLLocationCoordinate2D], accentColor: Color = .orange) {
        self.routes = [coordinates]
        self.accentColor = accentColor
    }

    init(routes: [[CLLocationCoordinate2D]], accentColor: Color = .orange) {
        self.routes = routes.filter { $0.count >= 2 }
        self.accentColor = accentColor
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        Canvas { context, size in
            // Skip RDP if already simplified (e.g. previewCoordinates from feed cards ~20 points)
            let simplifiedRoutes: [[CLLocationCoordinate2D]] = routes.compactMap { coordinates in
                guard coordinates.count >= 2 else { return nil }
                let s = coordinates.count > 30
                    ? GeometryUtils.simplifyRDP(coordinates, epsilon: 0.00003)
                    : coordinates
                return s.count >= 2 ? s : nil
            }
            guard let first = simplifiedRoutes.first?.first else { return }

            // Compute bounding box across EVERY route, so they share one frame
            var minLat = first.latitude
            var maxLat = first.latitude
            var minLon = first.longitude
            var maxLon = first.longitude
            for coord in simplifiedRoutes.flatMap({ $0 }) {
                minLat = min(minLat, coord.latitude)
                maxLat = max(maxLat, coord.latitude)
                minLon = min(minLon, coord.longitude)
                maxLon = max(maxLon, coord.longitude)
            }

            let latRange = maxLat - minLat
            let lonRange = maxLon - minLon
            guard latRange > 0 || lonRange > 0 else { return }

            // Add padding
            let padding: CGFloat = 16
            let drawW = size.width - padding * 2
            let drawH = size.height - padding * 2

            // Scale to fit, maintaining aspect ratio
            let latScale = latRange > 0 ? drawH / latRange : 1
            let lonScale = lonRange > 0 ? drawW / lonRange : 1
            let scale = min(latScale, lonScale)

            let centerX = size.width / 2
            let centerY = size.height / 2
            let midLat = (minLat + maxLat) / 2
            let midLon = (minLon + maxLon) / 2

            func toPoint(_ coord: CLLocationCoordinate2D) -> CGPoint {
                let x = centerX + (coord.longitude - midLon) * scale
                let y = centerY - (coord.latitude - midLat) * scale
                return CGPoint(x: x, y: y)
            }

            // Draw every route inside the shared frame
            for simplified in simplifiedRoutes {
                var path = Path()
                path.move(to: toPoint(simplified[0]))
                for i in 1..<simplified.count {
                    path.addLine(to: toPoint(simplified[i]))
                }
                context.stroke(
                    path,
                    with: .color(accentColor.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }

            // Концевые точки — только у ОДИНОЧНОГО маршрута. На десятке
            // маршрутов двадцать разноцветных точек читаются как сыпь, а не как
            // старт и финиш.
            guard simplifiedRoutes.count == 1, let simplified = simplifiedRoutes.first else { return }

            // Start dot (green)
            let startPt = toPoint(simplified[0])
            let dotSize: CGFloat = 5
            context.fill(
                Path(ellipseIn: CGRect(x: startPt.x - dotSize/2, y: startPt.y - dotSize/2, width: dotSize, height: dotSize)),
                with: .color(.green)
            )

            // End dot (red). Used to be a checkered flag on a 10pt pole: it
            // overhung the route bounds, needed an adaptive flip near the top
            // edge, and at thumbnail scale (70×46 in История) read as noise
            // rather than a finish. Canon mirrors the green start dot.
            let endPt = toPoint(simplified[simplified.count - 1])
            context.fill(
                Path(ellipseIn: CGRect(x: endPt.x - dotSize/2, y: endPt.y - dotSize/2, width: dotSize, height: dotSize)),
                with: .color(.red)
            )
        }
        .background(c.cardAlt)
    }

}
