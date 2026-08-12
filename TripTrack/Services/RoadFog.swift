import Foundation
import CoreLocation

/// The fog of roads — the thing the map is actually about.
///
/// Drawing every trip as its own line fails twice over. Sixty traces of the
/// same street, each scattered by GPS, stack into a smear that hides the
/// street; and drawing sixty copies of one road costs sixty times what one
/// copy does. Both are settled here, before the renderer ever sees the data.
///
/// The model follows Strava's global heatmap: rasterise PATHS rather than
/// points, count each activity at most once per cell, then normalise the
/// counts against their own distribution instead of against fixed thresholds,
/// so the ramp fits the person rather than a guess about how much they drive.
///
/// Two deliberate departures from Strava. The grid stays geographic (~150 m)
/// instead of per-tile-pixel, because this is one person's map drawn as
/// vectors, not a tile server. And the normalisation blends the CDF with a log
/// curve: Strava equalises over millions of pixels with a wide spread of
/// values, while a personal map has a handful of distinct pass counts, and a
/// pure CDF over a handful of steps is a staircase, not a ramp.
///
/// Geometry is deduplicated on the same grid: the first trip through a cell
/// owns the line there, later ones only add heat. So the drawn network grows
/// with the roads you have opened, not with how often you drove them — which
/// is both the look we want and the reason it stays fast.
struct RoadFog {
    /// One band of the heat ramp, already cut into continuous runs.
    struct Tier {
        /// Position on the ember→gold ramp, 0…1.
        let intensity: Double
        /// Lowest pass count that lands in this band.
        let passes: Int
        /// Full-detail geometry.
        let runs: [[CLLocationCoordinate2D]]
        /// The same geometry thinned for far zoom, where a 150 m vertex is
        /// smaller than a pixel and only costs time.
        let coarseRuns: [[CLLocationCoordinate2D]]
    }

    var tiers: [Tier] = []
    /// Distinct ~150 m cells touched, per atlas region index — the length of
    /// road you have actually opened there, as opposed to kilometres driven.
    var openedCellsByRegion: [Int: Int] = [:]
    /// Most passes any one cell has seen — the top of the ramp.
    var maxPasses: Int = 0

    var isEmpty: Bool { tiers.allSatisfy(\.runs.isEmpty) }

    /// Side of a grid cell, in km. One cell opened ≈ one cell-length of road,
    /// which is what «Дороги края» counts.
    static let cellKm = 0.15
    /// How many bands the ramp is quantised into. Six reads as a gradient
    /// while keeping the renderer down to six strokes.
    static let tierCount = 6

    // MARK: - Grid

    /// ~150 m of latitude. Longitude cells narrow towards the poles, which is
    /// the same thing Mercator pixels do, so the grid matches what is drawn.
    static let cellDegrees = 0.00135
    /// Vertex spacing for the far-zoom / mask geometry (~500 m).
    static let coarseDegrees = 0.0045
    /// Beyond this a «segment» is a paused-recording gap or a GPS glitch, not
    /// a road. Lighting it would draw a straight line across a whole country.
    private static let maxSegmentCells = 220.0

    @inline(__always)
    static func cellKey(_ latitude: Double, _ longitude: Double) -> Int64 {
        let y = Int64((latitude / cellDegrees).rounded(.down))
        let x = Int64((longitude / cellDegrees).rounded(.down))
        return y &* 4_000_000 &+ x
    }

    /// How close to an edge still counts as being in the cell beyond it, as a
    /// fraction of the cell. A third of ~150 m is about the width of a road
    /// plus its GPS error.
    private static let touchMargin = 0.33

    /// The cell a point is in, plus any cell whose edge it is hugging. Used
    /// for heat only — geometry is claimed on the containing cell alone, or a
    /// side street 150 m away would be swallowed by its neighbour's margin.
    @inline(__always)
    static func touchedCells(
        _ latitude: Double, _ longitude: Double, _ body: (Int64) -> Void
    ) {
        let y = latitude / cellDegrees
        let x = longitude / cellDegrees
        let yi = Int64(y.rounded(.down)), xi = Int64(x.rounded(.down))
        body(yi &* 4_000_000 &+ xi)

        let fy = y - y.rounded(.down), fx = x - x.rounded(.down)
        let dy: Int64? = fy < touchMargin ? -1 : (fy > 1 - touchMargin ? 1 : nil)
        let dx: Int64? = fx < touchMargin ? -1 : (fx > 1 - touchMargin ? 1 : nil)
        if let dy { body((yi &+ dy) &* 4_000_000 &+ xi) }
        if let dx { body(yi &* 4_000_000 &+ (xi &+ dx)) }
        if let dy, let dx { body((yi &+ dy) &* 4_000_000 &+ (xi &+ dx)) }
    }

    // MARK: - Building

    /// A route resampled onto the grid: one point per cell it crosses, cut
    /// wherever the recording teleported.
    private typealias Strand = (points: [CLLocationCoordinate2D], cells: [Int64])

    /// Walks every trip twice: once to learn how busy each cell is, once to
    /// claim the geometry and cut it into runs of constant heat.
    static func build(
        trips: [(id: UUID, coordinates: [CLLocationCoordinate2D])],
        regionForSegment: (CLLocationCoordinate2D) -> Int?
    ) -> RoadFog {
        // Everything downstream works on the resampled route, never on the
        // raw vertices. Preview polylines are RDP-simplified, so one «segment»
        // can be ten kilometres long — and deciding to keep or drop geometry a
        // whole segment at a time meant one fresh cell anywhere along a
        // motorway kept the entire motorway. That is what put five parallel
        // ribbons of the same commute on screen.
        let sampled = trips.map { strands(of: $0.coordinates) }

        // MARK: Pass 1 — passes per cell
        //
        // A trip's cells arrive contiguously, so remembering which trip last
        // touched a cell counts DISTINCT trips without a set per cell.
        var passes: [Int64: Int] = [:]
        var lastTrip: [Int64: Int] = [:]
        var openedCells: [Int: Int] = [:]
        var openedSeen = Set<Int64>()

        for (ordinal, strands) in sampled.enumerated() {
            for strand in strands {
                for (index, core) in strand.cells.enumerated() {
                    let point = strand.points[index]
                    // Heat is counted on a slightly widened footprint. A
                    // street running along a cell boundary — and city streets
                    // run north-south and east-west, so plenty of them do —
                    // splits its passes between the two sides, and the road
                    // you drive every day comes out alternately hot and cold
                    // along its own length.
                    touchedCells(point.latitude, point.longitude) { key in
                        guard lastTrip[key] != ordinal else { return }
                        lastTrip[key] = ordinal
                        passes[key] = (passes[key] ?? 0) + 1
                    }
                    // Opened road counts the cell itself. The widened
                    // footprint is there to steady the colour, not to inflate
                    // the kilometres.
                    if openedSeen.insert(core).inserted,
                       let region = regionForSegment(point) {
                        openedCells[region, default: 0] += 1
                    }
                }
            }
        }
        guard !passes.isEmpty else { return RoadFog() }

        // MARK: Normalisation
        let intensityByPasses = normalise(passes)
        let maxPasses = passes.values.max() ?? 1

        // MARK: Pass 2 — claim geometry, cut into runs
        var runsByTier = [[[CLLocationCoordinate2D]]](repeating: [], count: tierCount)
        var claimed = Set<Int64>()
        claimed.reserveCapacity(passes.count)

        for strands in sampled {
            for strand in strands {
                let steps = strand.cells.count - 1
                guard steps >= 1 else { continue }
                var keep = [Bool](repeating: false, count: steps)
                var tierOf = [Int](repeating: 0, count: steps)

                for i in 0..<steps {
                    let a = strand.cells[i], b = strand.cells[i + 1]
                    // Claim both ends regardless — a step that is not drawn
                    // still means this road is now spoken for.
                    let freshA = claimed.insert(a).inserted
                    let freshB = claimed.insert(b).inserted
                    keep[i] = freshA || freshB
                    let busiest = max(passes[a] ?? 1, passes[b] ?? 1)
                    tierOf[i] = tierIndex(intensityByPasses[busiest] ?? 0)
                }

                // A kept step next to a dropped one would leave a cell-wide
                // hole where this trip's line hands over to whichever trip
                // claimed the road first. Reaching one step past each end
                // closes it.
                var draw = keep
                for i in 0..<steps where keep[i] {
                    if i > 0 { draw[i - 1] = true }
                    if i + 1 < steps { draw[i + 1] = true }
                }

                var run: [CLLocationCoordinate2D] = []
                var runTier = -1
                func flush() {
                    if run.count > 1, runTier >= 0 { runsByTier[runTier].append(run) }
                    run = []
                    runTier = -1
                }
                for i in 0..<steps {
                    guard draw[i] else {
                        flush()
                        continue
                    }
                    if tierOf[i] != runTier {
                        flush()
                        // Start at the shared vertex so the bands meet instead
                        // of leaving a gap where the colour changes.
                        run = [strand.points[i]]
                        runTier = tierOf[i]
                    }
                    run.append(strand.points[i + 1])
                }
                flush()
            }
        }

        // MARK: Assemble
        var tiers: [Tier] = []
        for index in 0..<tierCount {
            let runs = runsByTier[index]
            guard !runs.isEmpty else { continue }
            let floor = intensityByPasses
                .filter { tierIndex($0.value) == index }
                .keys.min() ?? 1
            tiers.append(Tier(
                intensity: (Double(index) + 0.5) / Double(tierCount),
                passes: floor,
                runs: runs,
                coarseRuns: runs.map { decimate($0, minDegrees: coarseDegrees) }
            ))
        }

        return RoadFog(tiers: tiers, openedCellsByRegion: openedCells, maxPasses: maxPasses)
    }

    // MARK: - Normalisation

    /// Strava's move: the heat you see is where a cell ranks against every
    /// other cell you have driven, not an absolute count. Someone who drives
    /// one commute gets the same full ramp as someone with a decade of trips.
    ///
    /// The log term is ours. With five distinct pass counts a pure CDF puts
    /// «once» at the bottom and everything else near the top, and the ramp
    /// collapses to two colours; mixing in the absolute log share spreads the
    /// repeated roads back out.
    private static func normalise(_ passes: [Int64: Int]) -> [Int: Double] {
        var histogram: [Int: Int] = [:]
        for count in passes.values { histogram[count, default: 0] += 1 }
        let total = Double(passes.count)
        let ceiling = histogram.keys.max() ?? 1

        // Nothing repeated — no ranking to make. Put the whole network at one
        // clearly-lit step rather than at the dim bottom of a ramp it never
        // climbs.
        guard ceiling > 1 else {
            return histogram.keys.reduce(into: [:]) { $0[$1] = 0.55 }
        }

        var result: [Int: Double] = [:]
        var below = 0
        let logCeiling = log(Double(ceiling))
        for level in histogram.keys.sorted() {
            let count = histogram[level] ?? 0
            let cdf = (Double(below) + Double(count) / 2) / total
            let logShare = log(Double(level)) / logCeiling
            result[level] = min(1, 0.45 * cdf + 0.55 * logShare)
            below += count
        }
        return result
    }

    static func tierIndex(_ intensity: Double) -> Int {
        min(tierCount - 1, max(0, Int(intensity * Double(tierCount))))
    }

    // MARK: - Geometry

    /// Resamples a route onto the grid: one point per cell crossed, in order,
    /// split wherever a leg is long enough to be a paused-recording gap rather
    /// than a road. Points sit exactly on the original line, so the drawn
    /// network still follows the street — it is only the DECISIONS (claim,
    /// heat, colour) that become per-cell instead of per-vertex.
    private static func strands(of coords: [CLLocationCoordinate2D]) -> [Strand] {
        guard coords.count >= 2 else { return [] }
        var out: [Strand] = []
        var points: [CLLocationCoordinate2D] = []
        var cells: [Int64] = []

        func flush() {
            if cells.count > 1 { out.append((points, cells)) }
            points = []
            cells = []
        }

        for i in 1..<coords.count {
            let a = coords[i - 1], b = coords[i]
            guard segmentCells(a, b) <= maxSegmentCells else {
                flush()
                continue
            }
            walkCells(a, b) { key, coordinate in
                // Also swallows the vertex shared by two segments.
                guard cells.last != key else { return }
                cells.append(key)
                points.append(coordinate)
            }
        }
        flush()
        return out
    }

    /// How many cells a segment spans — the step count, and the teleport test.
    @inline(__always)
    private static func segmentCells(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> Double {
        max(abs(b.latitude - a.latitude), abs(b.longitude - a.longitude)) / cellDegrees
    }

    /// Every cell a segment crosses, in order. Preview polylines are
    /// RDP-simplified, so a straight motorway leg can leave kilometres between
    /// vertices — attributing that whole leg to the cell under its midpoint
    /// (which is what the first cut did) both under-counted opened road and
    /// left the rest of the motorway unclaimed, so every later trip redrew it.
    @inline(__always)
    private static func walkCells(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D,
        _ body: (Int64, CLLocationCoordinate2D) -> Void
    ) {
        let span = segmentCells(a, b)
        guard span.isFinite, span <= maxSegmentCells else { return }
        // 1.5 samples per cell so a diagonal leg does not step over cells.
        let steps = max(1, min(512, Int((span * 1.5).rounded(.up))))
        let dLat = b.latitude - a.latitude
        let dLon = b.longitude - a.longitude
        var previous: Int64 = .min

        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let latitude = a.latitude + dLat * t
            let longitude = a.longitude + dLon * t
            guard latitude.isFinite, longitude.isFinite else { return }
            let key = cellKey(latitude, longitude)
            guard key != previous else { continue }
            previous = key
            body(key, CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }

    /// Radial-distance thinning. Good enough for a mask and for a view where
    /// half a kilometre is five points, and a fraction of the cost of RDP.
    static func decimate(
        _ run: [CLLocationCoordinate2D], minDegrees: Double
    ) -> [CLLocationCoordinate2D] {
        guard run.count > 2 else { return run }
        let threshold = minDegrees * minDegrees
        var out: [CLLocationCoordinate2D] = [run[0]]
        for point in run.dropFirst() {
            let last = out[out.count - 1]
            let dLat = point.latitude - last.latitude
            let dLon = point.longitude - last.longitude
            if dLat * dLat + dLon * dLon >= threshold { out.append(point) }
        }
        // The end of a road is not optional — without this a short run
        // collapses to a single point and disappears.
        if let end = run.last, let kept = out.last,
           end.latitude != kept.latitude || end.longitude != kept.longitude {
            out.append(end)
        }
        return out.count > 1 ? out : run
    }
}
