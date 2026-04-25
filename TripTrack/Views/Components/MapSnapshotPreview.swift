import SwiftUI
import MapKit

/// Map preview using MKMapSnapshotter — renders map tiles once, caches as UIImage.
/// Best of both worlds: real map background without per-card MapKit view overhead.
struct MapSnapshotPreview: View {
    let coordinates: [CLLocationCoordinate2D]
    let tripId: UUID
    var height: CGFloat = 80
    /// Render width for the MKMapSnapshotter image. Defaults to a
    /// feed-card-sized 340pt; callers presenting in a wider slot (the share
    /// preview card) pass their slot width so the snapshot doesn't have to
    /// be aspect-cropped via `.fill` — which was making the start dot and
    /// finish flag look huge because they ended up near the cropped edge.
    var width: CGFloat = 340

    @Environment(\.colorScheme) private var scheme
    @State private var snapshot: UIImage?

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            // Placeholder: the lightweight Canvas polyline under a dimming
            // shimmer so the loading state reads as "loading" instead of as
            // a stretched, low-res version of the final image. The share
            // sheet opens with a wider slot than feed cards, which surfaced
            // the old polyline-only placeholder as the "super-zoomed, blurry"
            // flash the user was seeing right before tiles landed.
            if snapshot == nil {
                ZStack {
                    Rectangle().fill(c.cardAlt)
                    LightRoutePreview(coordinates: coordinates)
                        .opacity(0.6)
                }
                .shimmer()
                .transition(.opacity)
            }

            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: snapshot != nil)
        .task(id: cacheKey) {
            // Reset stale state before hitting the cache — without this the
            // previous snapshot image would remain visible for a frame or two
            // whenever the cache key changed (e.g. reopening the share sheet
            // at a different width), which is what caused the brief "wrong
            // resolution" flash.
            snapshot = nil
            await loadSnapshot(colors: c)
        }
    }

    private var cacheKey: String {
        "\(tripId.uuidString)-\(scheme == .dark ? "d" : "l")-w\(Int(width))-h\(Int(height))-v3"
    }

    @MainActor
    private func loadSnapshot(colors c: AppTheme.Colors) async {
        Self.ensureObserver()
        let key = cacheKey as NSString

        // L1: memory cache
        if let cached = Self.snapshotCache.object(forKey: key) {
            snapshot = cached
            return
        }

        guard coordinates.count >= 2 else { return }

        // Render via MKMapSnapshotter on background
        let region = Self.mapRegion(for: coordinates)
        let scale = UIScreen.main.scale

        let snapshotSize = CGSize(width: width, height: height)
        let isDark = scheme == .dark
        let image = await Task.detached(priority: .userInitiated) {
            await Self.renderSnapshot(
                coordinates: coordinates,
                region: region,
                size: snapshotSize,
                scale: scale,
                isDark: isDark
            )
        }.value

        guard let image else { return }
        Self.snapshotCache.setObject(image, forKey: key)
        withAnimation(.easeOut(duration: 0.35)) {
            snapshot = image
        }
    }

    // MARK: - Snapshot Rendering

    private static func renderSnapshot(
        coordinates: [CLLocationCoordinate2D],
        region: MKCoordinateRegion,
        size: CGSize,
        scale: CGFloat,
        isDark: Bool
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = scale
        options.pointOfInterestFilter = .excludingAll

        let config = MKStandardMapConfiguration(elevationStyle: .flat)
        config.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = config

        if isDark {
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        }

        let snapshotter = MKMapSnapshotter(options: options)

        guard let result = try? await snapshotter.start() else { return nil }

        // Draw route + dots on the snapshot image
        let renderer = UIGraphicsImageRenderer(size: result.image.size)
        return renderer.image { ctx in
            result.image.draw(at: .zero)

            let gc = ctx.cgContext

            // Draw polyline
            gc.setStrokeColor(UIColor(AppTheme.accent).withAlphaComponent(0.75).cgColor)
            gc.setLineWidth(2 * scale)
            gc.setLineCap(.round)
            gc.setLineJoin(.round)

            let points = coordinates.map { result.point(for: $0) }
            gc.beginPath()
            gc.move(to: points[0])
            for i in 1..<points.count {
                gc.addLine(to: points[i])
            }
            gc.strokePath()

            // Start dot (green)
            let dotRadius: CGFloat = 2.5 * scale
            let startPt = points[0]
            gc.setFillColor(UIColor.systemGreen.cgColor)
            gc.fillEllipse(in: CGRect(
                x: startPt.x - dotRadius, y: startPt.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            ))

            // End marker: checkered flag (adaptive direction)
            let endPt = points[points.count - 1]
            let poleH: CGFloat = 6 * scale
            let flagW: CGFloat = 4 * scale
            let flagH: CGFloat = 3 * scale
            let cellW = flagW / 2
            let cellH = flagH / 2

            // Flip flag downward if endpoint is near top edge
            let imageH = result.image.size.height
            let drawUp = endPt.y > poleH + flagH + 2 * scale
            let poleDir: CGFloat = drawUp ? -1 : 1

            // Flagpole
            gc.setStrokeColor(UIColor.label.cgColor)
            gc.setLineWidth(1 * scale)
            gc.beginPath()
            gc.move(to: CGPoint(x: endPt.x, y: endPt.y))
            gc.addLine(to: CGPoint(x: endPt.x, y: endPt.y + poleH * poleDir))
            gc.strokePath()

            // Checkered pattern (2x2)
            let flagOrigin: CGPoint
            if drawUp {
                flagOrigin = CGPoint(x: endPt.x, y: endPt.y - poleH)
            } else {
                flagOrigin = CGPoint(x: endPt.x, y: endPt.y + poleH)
            }
            // Black cells
            gc.setFillColor(UIColor.black.cgColor)
            gc.fill(CGRect(x: flagOrigin.x, y: flagOrigin.y, width: cellW, height: cellH))
            gc.fill(CGRect(x: flagOrigin.x + cellW, y: flagOrigin.y + cellH, width: cellW, height: cellH))
            // White cells
            gc.setFillColor(UIColor.white.cgColor)
            gc.fill(CGRect(x: flagOrigin.x + cellW, y: flagOrigin.y, width: cellW, height: cellH))
            gc.fill(CGRect(x: flagOrigin.x, y: flagOrigin.y + cellH, width: cellW, height: cellH))
        }
    }

    // MARK: - Region Calculation

    private static func mapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard coordinates.count >= 2 else {
            let c = coordinates.first ?? CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62)
            return MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - Cache

    private static let snapshotCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // ~50 MB
        return cache
    }()

    private static let memoryWarningObserver: Any = {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            snapshotCache.removeAllObjects()
        }
    }()

    /// Ensure memory warning observer is registered on first use.
    private static func ensureObserver() { _ = memoryWarningObserver }

    static func clearCache() {
        snapshotCache.removeAllObjects()
    }
}
