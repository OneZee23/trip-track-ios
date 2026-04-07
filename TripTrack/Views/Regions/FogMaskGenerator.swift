import MapKit
import UIKit

enum FogMaskGenerator {
    struct Result {
        let image: UIImage
        let mapRect: MKMapRect
    }

    // MARK: - Cache

    private static let lock = NSLock()
    private static var cachedResult: Result?
    private static var cachedGeohashSet: Set<String> = []

    private static let generationVersion: Int = 4 // bump to invalidate cache on algorithm change
    private static var cachedVersion: Int = 0

    /// Generate mask with caching — only regenerates when geohash set changes.
    static func generateCached(geohashes: Set<String>) -> Result? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedResult, geohashes == cachedGeohashSet, cachedVersion == generationVersion {
            return cached
        }
        let result = generate(geohashes: geohashes)
        cachedResult = result
        cachedGeohashSet = geohashes
        cachedVersion = generationVersion
        return result
    }

    /// Clear cached mask (e.g., on memory warning).
    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedResult = nil
        cachedGeohashSet = []
    }

    /// Generates a soft fog reveal mask from geohash6 tiles.
    /// Each tile center gets a radial gradient that feathers into fog.
    static func generate(geohashes: Set<String>) -> Result? {
        guard !geohashes.isEmpty else { return nil }

        // 1. Collect tile centers as MKMapPoints + compute tile size for radius
        var centers: [MKMapPoint] = []
        var unionRect = MKMapRect.null
        var tileWidth: Double = 0
        var tileHeight: Double = 0

        for hash in geohashes {
            let box = GeohashEncoder.decode(hash)
            let center = CLLocationCoordinate2D(
                latitude: (box.lat.lowerBound + box.lat.upperBound) / 2,
                longitude: (box.lon.lowerBound + box.lon.upperBound) / 2
            )
            let point = MKMapPoint(center)
            centers.append(point)

            // Compute tile size from first hash
            if tileWidth == 0 {
                let topLeft = MKMapPoint(CLLocationCoordinate2D(
                    latitude: box.lat.upperBound, longitude: box.lon.lowerBound
                ))
                let bottomRight = MKMapPoint(CLLocationCoordinate2D(
                    latitude: box.lat.lowerBound, longitude: box.lon.upperBound
                ))
                tileWidth = bottomRight.x - topLeft.x
                tileHeight = bottomRight.y - topLeft.y
            }

            let pointRect = MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1))
            unionRect = unionRect.union(pointRect)
        }

        // 2. Reveal radius = much larger than tile for smooth blending
        let revealRadiusMapPoints = max(tileWidth, tileHeight) * 3.0

        // 3. Expand bounding rect by reveal radius
        let expansion = revealRadiusMapPoints * 3.0
        unionRect = unionRect.insetBy(dx: -expansion, dy: -expansion)

        // 4. Image sizing (max 2048px)
        let aspectRatio = unionRect.size.width / unionRect.size.height
        let maxDimension: CGFloat = 2048
        let imageWidth: CGFloat
        let imageHeight: CGFloat
        if aspectRatio > 1 {
            imageWidth = maxDimension
            imageHeight = maxDimension / CGFloat(aspectRatio)
        } else {
            imageHeight = maxDimension
            imageWidth = maxDimension * CGFloat(aspectRatio)
        }
        let imageSize = CGSize(width: max(imageWidth, 1), height: max(imageHeight, 1))
        let radiusInPixels = CGFloat(revealRadiusMapPoints / unionRect.size.width) * imageSize.width

        // 5. Spatial dedup — one center per visual cell to avoid overdraw
        let cellSize = revealRadiusMapPoints * 0.4
        var seen = Set<UInt64>()
        var reducedCenters: [MKMapPoint] = []
        for p in centers {
            let cx = UInt64(p.x / cellSize)
            let cy = UInt64(p.y / cellSize)
            let key = cx &* 1_000_000_007 &+ cy
            if seen.insert(key).inserted {
                reducedCenters.append(p)
            }
        }

        // 6. Render soft radial gradients
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let image = renderer.image { ctx in
            let cgCtx = ctx.cgContext

            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let gradient = CGGradient(
                colorSpace: colorSpace,
                colorComponents: [1, 1,  1, 1,  1, 0.9,  1, 0.5,  1, 0.15,  1, 0],  // (gray, alpha) pairs — wide solid core, gentle fade
                locations: [0, 0.3, 0.5, 0.7, 0.9, 1.0],
                count: 6
            ) else { return }

            for point in reducedCenters {
                let px = CGFloat((point.x - unionRect.origin.x) / unionRect.size.width) * imageSize.width
                let py = CGFloat((point.y - unionRect.origin.y) / unionRect.size.height) * imageSize.height
                let center = CGPoint(x: px, y: py)

                cgCtx.drawRadialGradient(
                    gradient,
                    startCenter: center, startRadius: 0,
                    endCenter: center, endRadius: radiusInPixels,
                    options: []
                )
            }
        }

        return Result(image: image, mapRect: unionRect)
    }
}
