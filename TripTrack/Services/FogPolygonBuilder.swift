import MapKit

/// Custom MKPolygon subclass to distinguish fog overlay from other polygons.
final class FogPolygon: MKPolygon {}

enum FogPolygonBuilder {
    /// Sepia fog color — "terra incognita" old map theme.
    static let fogColor = UIColor(red: 0.24, green: 0.17, blue: 0.10, alpha: 0.95)

    // MARK: - Cache

    private static var cachedHashCount: Int = -1
    private static var cachedRectCenter: MKMapPoint = MKMapPoint()
    private static var cachedPolygon: FogPolygon?

    /// Build fog polygon covering `visibleRect` with holes for visited geohash6 tiles.
    ///
    /// - Parameters:
    ///   - visitedHashes: Set of geohash6 strings for revealed tiles.
    ///   - visibleRect: Current map visible area (will be expanded ×2 as buffer).
    /// - Returns: `FogPolygon` with interior holes, or `nil` if no hashes provided.
    static func build(visitedHashes: Set<String>, visibleRect: MKMapRect) -> FogPolygon? {
        guard !visitedHashes.isEmpty else { return nil }

        let buffered = visibleRect.insetBy(
            dx: -visibleRect.size.width * 0.5,
            dy: -visibleRect.size.height * 0.5
        )
        let center = MKMapPoint(
            x: buffered.midX,
            y: buffered.midY
        )

        // Check cache: same hash count and center within ~30% of visible width
        let threshold = visibleRect.size.width * 0.3
        if visitedHashes.count == cachedHashCount,
           abs(center.x - cachedRectCenter.x) < threshold,
           abs(center.y - cachedRectCenter.y) < threshold,
           let cached = cachedPolygon {
            return cached
        }

        // Build interior polygons (holes) for each visited tile in the buffered rect
        var holes: [MKPolygon] = []
        holes.reserveCapacity(visitedHashes.count)

        for hash in visitedHashes {
            let box = GeohashEncoder.decode(hash)
            let minLat = box.lat.lowerBound
            let maxLat = box.lat.upperBound
            let minLon = box.lon.lowerBound
            let maxLon = box.lon.upperBound

            // Quick check: does tile intersect the buffered rect?
            let tileOrigin = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
            let tileEnd = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
            let tileRect = MKMapRect(
                origin: MKMapPoint(x: min(tileOrigin.x, tileEnd.x), y: min(tileOrigin.y, tileEnd.y)),
                size: MKMapSize(width: abs(tileEnd.x - tileOrigin.x), height: abs(tileEnd.y - tileOrigin.y))
            )
            guard buffered.intersects(tileRect) else { continue }

            var coords = [
                CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
                CLLocationCoordinate2D(latitude: minLat, longitude: maxLon),
            ]
            holes.append(MKPolygon(coordinates: &coords, count: 4))
        }

        // Outer polygon: buffered visible rect
        let outerMinPt = MKMapPoint(x: buffered.minX, y: buffered.minY)
        let outerMaxPt = MKMapPoint(x: buffered.maxX, y: buffered.maxY)
        let outerMinCoord = outerMinPt.coordinate
        let outerMaxCoord = outerMaxPt.coordinate

        var outer = [
            CLLocationCoordinate2D(latitude: outerMinCoord.latitude, longitude: outerMinCoord.longitude),
            CLLocationCoordinate2D(latitude: outerMaxCoord.latitude, longitude: outerMinCoord.longitude),
            CLLocationCoordinate2D(latitude: outerMaxCoord.latitude, longitude: outerMaxCoord.longitude),
            CLLocationCoordinate2D(latitude: outerMinCoord.latitude, longitude: outerMaxCoord.longitude),
        ]

        let polygon = FogPolygon(coordinates: &outer, count: 4, interiorPolygons: holes)

        // Update cache
        cachedHashCount = visitedHashes.count
        cachedRectCenter = center
        cachedPolygon = polygon

        return polygon
    }

    /// Clear the polygon cache (e.g., after territory rebuild).
    static func clearCache() {
        cachedHashCount = -1
        cachedPolygon = nil
    }
}
