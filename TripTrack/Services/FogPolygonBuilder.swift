import MapKit

// MARK: - Data Model

/// Overlay that covers the entire world — used for fog of war rendering.
final class FogOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect: MKMapRect = .world

    struct RevealCenter {
        let geohash: String
        let mapPoint: MKMapPoint
        let radiusInPoints: Double
        var animationProgress: Double = 1.0 // 0→1; 1 = fully revealed
    }

    /// Thread-safe snapshot: renderer reads this from background thread, main thread swaps atomically.
    private(set) var centersByPrefix: [String: [RevealCenter]]
    let maxRadiusInPoints: Double

    /// Indices of centers currently animating (progress < 1.0).
    fileprivate var animatingIndices: [Int] = []
    fileprivate var centers: [RevealCenter]

    init(visitedHashes: Set<String>) {
        var builtCenters: [RevealCenter] = []
        builtCenters.reserveCapacity(visitedHashes.count)
        var byPrefix: [String: [RevealCenter]] = [:]
        var maxRadius: Double = 0

        for hash in visitedHashes {
            let coord = GeohashEncoder.centerCoordinate(of: hash)
            let mapPt = MKMapPoint(coord)

            let metersPerPoint = Self.MKMapPointsPerMeterAtLatitude(coord.latitude)
            let radius = 900.0 * metersPerPoint
            maxRadius = max(maxRadius, radius)

            let center = RevealCenter(geohash: hash, mapPoint: mapPt, radiusInPoints: radius)
            builtCenters.append(center)

            let prefix = String(hash.prefix(4))
            byPrefix[prefix, default: []].append(center)
        }

        self.centers = builtCenters
        self.centersByPrefix = byPrefix
        self.maxRadiusInPoints = maxRadius
        super.init()
    }

    /// Mark centers whose geohashes are in `newHashes` with animationProgress = 0.
    func markNewCenters(_ newHashes: Set<String>) {
        animatingIndices = []
        for i in centers.indices where newHashes.contains(centers[i].geohash) {
            centers[i].animationProgress = 0.0
            animatingIndices.append(i)
        }
        rebuildPrefixIndex()
    }

    /// Update animating centers with per-center start times. Returns true if any still animating.
    @discardableResult
    func updateAnimationProgress(_ progress: Double) -> Bool {
        var stillAnimating = false
        for i in animatingIndices {
            centers[i].animationProgress = min(1.0, progress)
            if centers[i].animationProgress < 1.0 { stillAnimating = true }
        }
        if !stillAnimating { animatingIndices = [] }
        // Swap prefix index atomically so renderer always reads a consistent snapshot
        rebuildPrefixIndex()
        return stillAnimating
    }

    private func rebuildPrefixIndex() {
        var byPrefix: [String: [RevealCenter]] = [:]
        for center in centers {
            let prefix = String(center.geohash.prefix(4))
            byPrefix[prefix, default: []].append(center)
        }
        centersByPrefix = byPrefix
    }

    /// Helper: meters → MKMapPoints at a given latitude.
    private static func MKMapPointsPerMeterAtLatitude(_ latitude: Double) -> Double {
        let worldWidth = MKMapSize.world.width
        let circumference = 2.0 * .pi * 6_371_000.0 * cos(latitude * .pi / 180.0)
        guard circumference > 0 else { return worldWidth / (2.0 * .pi * 6_371_000.0) }
        return worldWidth / circumference
    }
}

// MARK: - Renderer

/// Fills each MapKit tile with dark fog, then punches soft radial gradient holes for visited areas.
final class FogOverlayRenderer: MKOverlayRenderer {
    static let fogColor = UIColor(white: 0.12, alpha: 0.75)

    /// Cached gradient — created once, reused across all draw calls.
    private static let revealGradient: CGGradient = {
        let cs = CGColorSpaceCreateDeviceGray()
        // In destinationOut: alpha=1 fully clears fog, alpha=0 leaves fog intact
        let components: [CGFloat] = [
            1.0, 1.0,   // location 0.0: white, fully opaque → clears fog
            1.0, 0.85,  // location 0.5: still mostly clearing
            1.0, 0.4,   // location 0.75: transitioning
            1.0, 0.0,   // location 1.0: transparent → fog remains
        ]
        let locations: [CGFloat] = [0.0, 0.5, 0.75, 1.0]
        return CGGradient(colorSpace: cs, colorComponents: components, locations: locations, count: 4)!
    }()

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let fogOverlay = overlay as? FogOverlay else { return }

        // 1. Fill entire tile with fog
        let drawRect = rect(for: mapRect)
        context.setFillColor(Self.fogColor.cgColor)
        context.fill(drawRect)

        // 2. Find relevant reveal centers near this tile
        let centers = relevantCenters(for: mapRect, from: fogOverlay)
        guard !centers.isEmpty else { return }

        // 3. Punch soft holes
        context.setBlendMode(.destinationOut)

        for c in centers {
            let cgPt = cgPoint(for: c.mapPoint)
            let fullRadius = cgDistance(for: c.radiusInPoints, at: c.mapPoint)
            let cgRadius = fullRadius * c.animationProgress

            // Performance: skip sub-pixel or zero-progress circles
            guard cgRadius > 0 else { continue }
            let screenRadius = cgRadius * zoomScale
            if screenRadius < 2.0 { continue }

            if screenRadius < 4.0 {
                // Tiny circle — solid fill instead of gradient (cheaper)
                context.setFillColor(CGColor(gray: 1, alpha: 0.8))
                context.fillEllipse(in: CGRect(
                    x: cgPt.x - cgRadius, y: cgPt.y - cgRadius,
                    width: cgRadius * 2, height: cgRadius * 2
                ))
            } else {
                // Full radial gradient for smooth edges
                context.drawRadialGradient(
                    Self.revealGradient,
                    startCenter: cgPt, startRadius: 0,
                    endCenter: cgPt, endRadius: cgRadius,
                    options: []
                )
            }
        }
    }

    // MARK: - Spatial Lookup

    /// Find reveal centers whose gradient circles intersect this MapKit tile.
    private func relevantCenters(for mapRect: MKMapRect, from overlay: FogOverlay) -> [FogOverlay.RevealCenter] {
        let maxR = overlay.maxRadiusInPoints
        guard maxR > 0 else { return [] }

        // Expand tile by max radius to catch circles centered outside but extending in
        let buffered = mapRect.insetBy(dx: -maxR, dy: -maxR)

        // Convert buffered corners to lat/lon to find geohash4 prefixes
        let corners = [
            MKMapPoint(x: buffered.minX, y: buffered.minY).coordinate,
            MKMapPoint(x: buffered.maxX, y: buffered.minY).coordinate,
            MKMapPoint(x: buffered.minX, y: buffered.maxY).coordinate,
            MKMapPoint(x: buffered.maxX, y: buffered.maxY).coordinate,
        ]
        let minLat = corners.map(\.latitude).min()!
        let maxLat = corners.map(\.latitude).max()!
        let minLon = corners.map(\.longitude).min()!
        let maxLon = corners.map(\.longitude).max()!

        // Grid-sample at geohash4 resolution (~0.18° lat, ~0.35° lon)
        var prefixes = Set<String>()
        var lat = minLat
        while lat <= maxLat + 0.18 {
            var lon = minLon
            while lon <= maxLon + 0.35 {
                let h = GeohashEncoder.encode(
                    latitude: min(max(lat, -90), 90),
                    longitude: min(max(lon, -180), 180),
                    precision: 4
                )
                prefixes.insert(h)
                lon += 0.17
            }
            lat += 0.09
        }

        // Collect centers from matching buckets
        var result: [FogOverlay.RevealCenter] = []
        for prefix in prefixes {
            guard let centers = overlay.centersByPrefix[prefix] else { continue }
            for c in centers {
                if buffered.contains(c.mapPoint) {
                    result.append(c)
                }
            }
        }
        return result
    }

    // MARK: - Coordinate Helpers

    private func cgPoint(for mapPoint: MKMapPoint) -> CGPoint {
        let r = rect(for: MKMapRect(origin: mapPoint, size: MKMapSize(width: 0, height: 0)))
        return r.origin
    }

    private func cgDistance(for mapDistance: Double, at mapPoint: MKMapPoint) -> CGFloat {
        let end = MKMapPoint(x: mapPoint.x + mapDistance, y: mapPoint.y)
        let startCG = cgPoint(for: mapPoint)
        let endCG = cgPoint(for: end)
        return abs(endCG.x - startCG.x)
    }
}

// MARK: - Builder

enum FogPolygonBuilder {
    private static var cachedHashCount: Int = -1
    private static var cachedOverlay: FogOverlay?

    static func build(visitedHashes: Set<String>, visibleRect: MKMapRect) -> FogOverlay? {
        guard !visitedHashes.isEmpty else { return nil }

        if visitedHashes.count == cachedHashCount,
           let cached = cachedOverlay {
            return cached
        }

        let overlay = FogOverlay(visitedHashes: visitedHashes)
        cachedHashCount = visitedHashes.count
        cachedOverlay = overlay
        return overlay
    }

    /// Build and mark new tiles for animation. Returns (overlay, newHashes).
    static func buildAnimated(visitedHashes: Set<String>, visibleRect: MKMapRect) -> (overlay: FogOverlay, newHashes: Set<String>)? {
        guard !visitedHashes.isEmpty else { return nil }

        let previousHashes = Set(cachedOverlay?.centers.map(\.geohash) ?? [])
        let newHashes = visitedHashes.subtracting(previousHashes)

        let overlay = FogOverlay(visitedHashes: visitedHashes)
        if !newHashes.isEmpty {
            overlay.markNewCenters(newHashes)
        }
        cachedHashCount = visitedHashes.count
        cachedOverlay = overlay
        return (overlay, newHashes)
    }

    static func clearCache() {
        cachedHashCount = -1
        cachedOverlay = nil
    }
}
