import SwiftUI
import CoreLocation

struct RoutePreviewView: View {
    let coordinates: [CLLocationCoordinate2D]
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark gradient background
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 13/255, green: 17/255, blue: 23/255),
                                Color(red: 22/255, green: 27/255, blue: 34/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Subtle blue radial glow
                RadialGradient(
                    colors: [AppTheme.blue.opacity(0.06), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.5
                )

                if coordinates.count >= 2 {
                    routePath(in: geometry.size)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func routePath(in size: CGSize) -> some View {
        let padding: CGFloat = 20
        let drawableWidth = size.width - padding * 2
        let drawableHeight = size.height - padding * 2

        // Downsample for performance
        let sampled = downsample(coordinates, maxPoints: 50)

        let lats = sampled.map(\.latitude)
        let lons = sampled.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let rangeLat = max(maxLat - minLat, 0.001)
        let rangeLon = max(maxLon - minLon, 0.001)

        let points: [CGPoint] = sampled.map { coord in
            let x = padding + ((coord.longitude - minLon) / rangeLon) * drawableWidth
            let y = padding + ((maxLat - coord.latitude) / rangeLat) * drawableHeight
            return CGPoint(x: x, y: y)
        }

        Canvas { context, _ in
            guard points.count >= 2 else { return }

            // Wide glow
            var glowPath = Path()
            glowPath.move(to: points[0])
            for i in 1..<points.count {
                glowPath.addLine(to: points[i])
            }
            context.stroke(
                glowPath,
                with: .color(AppTheme.blue.opacity(0.15)),
                style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
            )

            // Main line
            var mainPath = Path()
            mainPath.move(to: points[0])
            for i in 1..<points.count {
                mainPath.addLine(to: points[i])
            }
            context.stroke(
                mainPath,
                with: .color(AppTheme.blue.opacity(0.9)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 4])
            )

            // Start dot (green)
            let start = points[0]
            context.fill(
                Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)),
                with: .color(AppTheme.green.opacity(0.9))
            )

            // End dot (red)
            let end = points[points.count - 1]
            context.fill(
                Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)),
                with: .color(AppTheme.red.opacity(0.9))
            )
        }
    }

    private func downsample(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > maxPoints else { return coords }
        let step = Double(coords.count) / Double(maxPoints)
        var result: [CLLocationCoordinate2D] = []
        for i in 0..<maxPoints {
            let index = Int(Double(i) * step)
            result.append(coords[min(index, coords.count - 1)])
        }
        // Always include last point
        if let last = coords.last {
            result[result.count - 1] = last
        }
        return result
    }
}
