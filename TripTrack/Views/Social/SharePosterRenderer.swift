import SwiftUI
import MapKit

/// Builds the map layer behind a share card: real tiles for the route's
/// region, plus the route projected with the snapshotter's OWN projection so
/// the line sits on the roads it was driven on (re-deriving the projection
/// ourselves drifted visibly on long routes).
///
/// One snapshot per (trip, format) is cached for the session — flipping
/// between «Постер» and «Сторис» twice shouldn't re-download tiles.
enum SharePosterRenderer {
    private static let cache = NSCache<NSString, CacheBox>()

    private final class CacheBox {
        let value: SharePosterMap
        init(_ value: SharePosterMap) { self.value = value }
    }

    static func map(
        for coordinates: [CLLocationCoordinate2D],
        tripId: UUID,
        format: SharePosterFormat
    ) async -> SharePosterMap? {
        guard format.showsMap, coordinates.count > 1 else { return nil }
        let key = "\(tripId.uuidString)-\(format.rawValue)" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }

        // Render at export resolution: the preview is the same image scaled
        // down, so the card the user approves is pixel-for-pixel the card
        // that gets shared.
        // Points + 2× scale rather than points at 1×: MapKit rasterises its
        // labels and road casings for the trait's scale, and the 1× pass was
        // visibly softer at the same output resolution.
        let size = format.renderPointSize
        let scale = SharePosterFormat.renderScale
        // Cold tile fetches come back empty often enough that a single
        // attempt regularly yields a blank grid (same failure the feed-card
        // snapshots hit). Retry with a short ladder before giving up to the
        // navy fallback.
        let result = await Task.detached(priority: .userInitiated) { () -> SharePosterMap? in
            let options = MKMapSnapshotter.Options()
            options.region = region(for: coordinates)
            options.size = size
            options.scale = scale
            options.pointOfInterestFilter = .excludingAll
            let config = MKStandardMapConfiguration(elevationStyle: .flat)
            config.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = config
            // Dark tiles — the card is a dark surface, and a daylight map
            // under white type needs a scrim so heavy it hides the map.
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

            var snapshot: MKMapSnapshotter.Snapshot?
            for delay in [UInt64(0), 700_000_000, 2_000_000_000] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                if Task.isCancelled { return nil }
                snapshot = try? await MKMapSnapshotter(options: options).start()
                if snapshot != nil { break }
            }
            guard let snap = snapshot else { return nil }
            let imageSize = snap.image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return nil }
            let points = coordinates.map { c -> CGPoint in
                let p = snap.point(for: c)
                return CGPoint(x: p.x / imageSize.width, y: p.y / imageSize.height)
            }
            return SharePosterMap(image: snap.image, points: points)
        }.value

        if let result { cache.setObject(CacheBox(result), forKey: key) }
        return result
    }

    /// Route bounds with headroom so the track never touches the edges and
    /// the bottom caption doesn't sit on top of it.
    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // 1.6× the bounding box, with a floor so a 200m hop doesn't zoom to
        // building level.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
