import SwiftUI
import CoreLocation

/// Dark "poster" route render for the trip-detail hero (Figma 6.1.0,
/// section 05 «ОТКРЫТИЕ ПОЕЗДКИ»). MapKit tiles can't be recolored to the
/// navy poster style, so the hero draws the route itself on a gradient
/// canvas: speed-colored polyline, green start / red end dots and the
/// pixel-car sprite. The real interactive map stays one tap away via the
/// fullscreen cover the parent attaches.
///
/// Perf contract: callers pass PRE-DOWNSAMPLED coordinates (≤ ~300 points,
/// speeds aligned by index). During route playback the parent re-renders at
/// display-link rate, so everything per-frame here must stay O(points-drawn).
struct PosterRouteCanvas: View {
    /// Which Figma surface the canvas reproduces: the navy detail poster
    /// (117:1049) or the light «map» surface of the cinema replay (117:533,
    /// full-bleed #E8E1D3 under dark chrome gradients).
    enum Style {
        case poster
        case cinema
    }

    let coordinates: [CLLocationCoordinate2D]
    /// m/s, index-aligned with `coordinates`. Empty → flat accent route
    /// (social trips: the preview polyline carries no per-point speeds —
    /// Figma shows a speed-colored route even on others' posters, but the
    /// DTO has no speed series; accent-colored is the documented deviation
    /// until the backend ships per-point speeds).
    var speeds: [Double] = []
    /// Interpolated playback head. Non-nil while «Прожить заново» runs.
    var playbackCoord: CLLocationCoordinate2D? = nil
    /// Index of the last passed original coordinate during playback.
    var playbackTrailIndex: Int = -1
    var style: Style = .poster
    /// Draw the pixel-car sprite. Defaults to true so the trip-detail
    /// poster and replay render exactly as before; feed cards pass false
    /// (Figma FeedCard 115:38 draws a bare route).
    var showsCar: Bool = true

    /// Poster canvas gradient (Figma: 141.63° #29364F 7% → #161B2C 79%).
    private static let bgGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0x29/255, green: 0x36/255, blue: 0x4F/255), location: 0.07),
            .init(color: Color(red: 0x16/255, green: 0x1B/255, blue: 0x2C/255), location: 0.79)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Cinema «map» surface (Figma 117:533 #E8E1D3).
    private static let cinemaBg = Color(red: 0xE8/255, green: 0xE1/255, blue: 0xD3/255)

    private static let startDotColor = Color(red: 0x2E/255, green: 0xAE/255, blue: 0x50/255)
    private static let endDotColor = Color(red: 0xDC/255, green: 0x3C/255, blue: 0x32/255)

    var body: some View {
        ZStack {
            switch style {
            case .poster: Self.bgGradient
            case .cinema: Self.cinemaBg
            }

            if coordinates.count > 1 {
                Canvas { context, size in
                    drawRoute(context: &context, size: size)
                }
            } else {
                Image(systemName: "map")
                    .font(.largeTitle)
                    .foregroundStyle(style == .poster ? .white.opacity(0.2) : .black.opacity(0.2))
            }
        }
    }

    // MARK: - Drawing

    private func drawRoute(context: inout GraphicsContext, size: CGSize) {
        let projected = Self.project(coordinates, into: size, padding: 36)
        guard projected.count > 1 else { return }

        // Route polyline — grouped into same-speed-zone subpaths so each
        // zone strokes with its band color (green→yellow→orange→red, same
        // scale as the real map render / legend). Speeds empty → one accent
        // stroke.
        let stroke = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        if speeds.count == coordinates.count, !speeds.isEmpty {
            // Segment (i-1 → i) takes the zone of point i; consecutive
            // same-zone segments merge into a single stroked path, and each
            // group re-anchors on the previous point so the line never gaps.
            var i = 1
            while i < projected.count {
                let zone = SpeedColorScale.zone(forSpeedMS: speeds[i])
                var path = Path()
                path.move(to: projected[i - 1])
                var j = i
                while j < projected.count, SpeedColorScale.zone(forSpeedMS: speeds[j]) == zone {
                    path.addLine(to: projected[j])
                    j += 1
                }
                context.stroke(path, with: .color(SpeedColorScale.bands[zone].color), style: stroke)
                i = j
            }
        } else {
            var path = Path()
            path.move(to: projected[0])
            for pt in projected.dropFirst() { path.addLine(to: pt) }
            context.stroke(path, with: .color(AppTheme.accent), style: stroke)
        }

        // Playback trail — overlay from start to the head, so «Прожить
        // заново» reads as the trip re-driving itself over the speed-colored
        // ghost of the full route. White ink on the navy poster, dark ink on
        // the light cinema surface.
        var headPoint: CGPoint? = nil
        if let playCoord = playbackCoord {
            headPoint = Self.projectSingle(playCoord, like: coordinates, into: size, padding: 36)
            let lastIdx = min(max(playbackTrailIndex, 0), projected.count - 1)
            var trail = Path()
            trail.move(to: projected[0])
            if lastIdx >= 1 {
                for j in 1...lastIdx { trail.addLine(to: projected[j]) }
            }
            if let head = headPoint { trail.addLine(to: head) }
            let trailColor: Color = style == .poster
                ? .white.opacity(0.92)
                : Color(red: 0x12/255, green: 0x12/255, blue: 0x14/255).opacity(0.8)
            context.stroke(
                trail,
                with: .color(trailColor),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }

        // Start / end dots (9px — green bottom of the trip, red at the end).
        let dot: CGFloat = 9
        context.fill(
            Path(ellipseIn: CGRect(x: projected[0].x - dot/2, y: projected[0].y - dot/2, width: dot, height: dot)),
            with: .color(Self.startDotColor)
        )
        if let last = projected.last {
            context.fill(
                Path(ellipseIn: CGRect(x: last.x - dot/2, y: last.y - dot/2, width: dot, height: dot)),
                with: .color(Self.endDotColor)
            )
        }

        // Pixel-car sprite (30pt). Mid-route rotated 22° when idle (Figma);
        // during playback it rides the head, rotated along the segment.
        if showsCar {
            let car = context.resolve(Image("PixelCar").interpolation(.none))
            let carSize: CGFloat = 30
            // The sprite asset is non-square — drawing into a square rect
            // squashes it. Fit by the longer side.
            let aspect = car.size.width > 0 ? car.size.height / car.size.width : 1
            let carW: CGFloat = aspect <= 1 ? carSize : carSize / aspect
            let carH: CGFloat = aspect <= 1 ? carSize * aspect : carSize
            let carPoint: CGPoint
            let rotation: Angle
            if let head = headPoint {
                carPoint = head
                let refIdx = min(max(playbackTrailIndex, 0), projected.count - 2)
                let a = projected[refIdx]
                let b = projected[refIdx + 1]
                rotation = .radians(atan2(b.y - a.y, b.x - a.x))
            } else {
                carPoint = projected[projected.count / 2]
                rotation = .degrees(22)
            }
            var carCtx = context
            carCtx.translateBy(x: carPoint.x, y: carPoint.y)
            carCtx.rotate(by: rotation)
            carCtx.draw(car, in: CGRect(x: -carW/2, y: -carH/2, width: carW, height: carH))
        }
    }

    // MARK: - Projection

    /// Equirectangular fit with cos(midLat) correction so E-W distances
    /// don't stretch at high latitudes (LightRoutePreview skips this — a
    /// full-bleed 380pt poster makes the distortion visible).
    private struct BoundingBox {
        let midLat: Double
        let midLon: Double
        let cosLat: Double
        let scale: Double
        /// Route crosses the ±180° antimeridian (raw lon span > 180° means
        /// the SHORT arc wraps — e.g. Chukotka's Egvekinot–Iultin road).
        /// Longitudes are then unwrapped onto a continuous 0…360 branch so
        /// the bbox/scale doesn't collapse and the path doesn't smear a
        /// straight line across the whole canvas.
        let wrapsAntimeridian: Bool

        init?(coords: [CLLocationCoordinate2D], size: CGSize, padding: CGFloat) {
            guard let first = coords.first else { return nil }
            var minLat = first.latitude, maxLat = first.latitude
            var minLon = first.longitude, maxLon = first.longitude
            for c in coords {
                minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
                minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
            }
            wrapsAntimeridian = (maxLon - minLon) > 180
            if wrapsAntimeridian {
                minLon = Self.unwrap(first.longitude)
                maxLon = minLon
                for c in coords {
                    let lon = Self.unwrap(c.longitude)
                    minLon = min(minLon, lon); maxLon = max(maxLon, lon)
                }
            }
            midLat = (minLat + maxLat) / 2
            midLon = (minLon + maxLon) / 2
            cosLat = max(0.01, cos(midLat * .pi / 180))
            let xSpan = max((maxLon - minLon) * cosLat, 1e-6)
            let ySpan = max(maxLat - minLat, 1e-6)
            let drawW = Double(size.width - padding * 2)
            let drawH = Double(size.height - padding * 2)
            guard drawW > 0, drawH > 0 else { return nil }
            scale = min(drawW / xSpan, drawH / ySpan)
        }

        /// [-180, 0) → [180, 360) — the continuous branch around +180°.
        private static func unwrap(_ lon: Double) -> Double {
            lon < 0 ? lon + 360 : lon
        }

        func point(for coord: CLLocationCoordinate2D, in size: CGSize) -> CGPoint {
            let lon = wrapsAntimeridian ? Self.unwrap(coord.longitude) : coord.longitude
            let x = Double(size.width) / 2 + (lon - midLon) * cosLat * scale
            let y = Double(size.height) / 2 - (coord.latitude - midLat) * scale
            return CGPoint(x: x, y: y)
        }
    }

    private static func project(
        _ coords: [CLLocationCoordinate2D], into size: CGSize, padding: CGFloat
    ) -> [CGPoint] {
        guard let box = BoundingBox(coords: coords, size: size, padding: padding) else { return [] }
        return coords.map { box.point(for: $0, in: size) }
    }

    /// Projects one extra coordinate (the interpolated playback head) with
    /// the SAME bounding box as the base route so it lands on the line.
    private static func projectSingle(
        _ coord: CLLocationCoordinate2D, like base: [CLLocationCoordinate2D],
        into size: CGSize, padding: CGFloat
    ) -> CGPoint? {
        guard let box = BoundingBox(coords: base, size: size, padding: padding) else { return nil }
        return box.point(for: coord, in: size)
    }

    /// Public projection helper for overlays that must pin to the same
    /// coordinate space the canvas draws in (replay speed bubble): projects
    /// `coord` with `route`'s bounding box at the canvas's own 36pt padding.
    /// Pass the canvas's rendered size.
    static func overlayPoint(
        for coord: CLLocationCoordinate2D,
        route: [CLLocationCoordinate2D],
        in size: CGSize
    ) -> CGPoint? {
        projectSingle(coord, like: route, into: size, padding: 36)
    }
}
