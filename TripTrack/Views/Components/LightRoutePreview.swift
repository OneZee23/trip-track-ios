import SwiftUI
import MapKit

/// Lightweight route preview using Canvas instead of MKMapView.
/// Much faster to render in feed cards — no UIKit overhead.
struct LightRoutePreview: View {
    let coordinates: [CLLocationCoordinate2D]
    var accentColor: Color = .orange

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        Canvas { context, size in
            guard coordinates.count >= 2 else { return }

            // Skip RDP if already simplified (e.g. previewCoordinates from feed cards ~20 points)
            let simplified: [CLLocationCoordinate2D]
            if coordinates.count > 30 {
                simplified = GeometryUtils.simplifyRDP(coordinates, epsilon: 0.00003)
            } else {
                simplified = coordinates
            }
            guard simplified.count >= 2 else { return }

            // Compute bounding box
            var minLat = simplified[0].latitude
            var maxLat = simplified[0].latitude
            var minLon = simplified[0].longitude
            var maxLon = simplified[0].longitude
            for coord in simplified {
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

            // Draw route path
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

            // Start dot (green)
            let startPt = toPoint(simplified[0])
            let dotSize: CGFloat = 5
            context.fill(
                Path(ellipseIn: CGRect(x: startPt.x - dotSize/2, y: startPt.y - dotSize/2, width: dotSize, height: dotSize)),
                with: .color(.green)
            )

            // End marker: checkered flag (adaptive direction)
            let endPt = toPoint(simplified[simplified.count - 1])
            let poleH: CGFloat = 10
            let flagW: CGFloat = 7
            let flagH: CGFloat = 5
            let cellW = flagW / 2
            let cellH = flagH / 2

            // Flip flag downward if endpoint is near top edge
            let drawUp = endPt.y > poleH + flagH + 2

            // Flagpole
            var polePath = Path()
            polePath.move(to: CGPoint(x: endPt.x, y: endPt.y))
            polePath.addLine(to: CGPoint(x: endPt.x, y: endPt.y + (drawUp ? -poleH : poleH)))
            context.stroke(polePath, with: .color(.primary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Checkered pattern (2x2)
            let flagOrigin = drawUp
                ? CGPoint(x: endPt.x, y: endPt.y - poleH)
                : CGPoint(x: endPt.x, y: endPt.y + poleH)
            context.fill(Path(CGRect(x: flagOrigin.x, y: flagOrigin.y, width: cellW, height: cellH)), with: .color(.black))
            context.fill(Path(CGRect(x: flagOrigin.x + cellW, y: flagOrigin.y + cellH, width: cellW, height: cellH)), with: .color(.black))
            context.fill(Path(CGRect(x: flagOrigin.x + cellW, y: flagOrigin.y, width: cellW, height: cellH)), with: .color(.white))
            context.fill(Path(CGRect(x: flagOrigin.x, y: flagOrigin.y + cellH, width: cellW, height: cellH)), with: .color(.white))
        }
        .background(c.cardAlt)
    }

}
