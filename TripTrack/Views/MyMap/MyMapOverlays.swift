import MapKit

// MARK: - Palette

enum MyMapPalette {
    static let accent = UIColor(red: 0xEB/255, green: 0x57/255, blue: 0x1E/255, alpha: 1)
    static let accentBright = UIColor(red: 0xFF/255, green: 0x6A/255, blue: 0x2B/255, alpha: 1)
    static let ink = UIColor(red: 0x14/255, green: 0x14/255, blue: 0x1A/255, alpha: 1)
}

// MARK: - Routes

/// Route segment carrying its own gradient stops for
/// `MKGradientPolylineRenderer` (same pattern as RouteMapView's
/// `SpeedPolyline`, but with Figma's My-Map palette).
final class SpeedGradientPolyline: MKPolyline {
    var gradientColors: [UIColor] = []
    var gradientLocations: [CGFloat] = []
    /// Which trip this belongs to — the map dims every other route when one
    /// trip is selected (canon «близко = линия маршрута выбранной поездки»).
    var tripId: UUID?
}

/// The selected trip's own line.
///
/// Drawn by hand rather than with `MKGradientPolylineRenderer`. That one
/// rasterises the line and lets MapKit rescale the result as you zoom, so
/// after a few pinches in and out it sat two or three times the width of the
/// heat lines right beside it — set to 3 points against their 4.6 — and it did
/// not come back on its own.
///
/// Recomputing the width from `zoomScale` on every tile is exactly what keeps
/// the fog crisp at any zoom, so the route does the same now. The speed scale
/// is four colours, not a continuous ramp, so this is four strokes — the same
/// shape as the fog's bands.
final class SelectedRouteRenderer: MKOverlayRenderer {
    private let route: SpeedGradientPolyline
    private var bands: [(color: UIColor, path: CGPath)] = []
    private var casing: CGPath?

    private static let width: CGFloat = 3.2
    /// A dark casing so the route reads as laid ON the network rather than
    /// merging into the ember underneath it.
    private static let casingExtra: CGFloat = 2.6

    init(route: SpeedGradientPolyline) {
        self.route = route
        super.init(overlay: route)
        build()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard !bands.isEmpty else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let width = Self.width / zoomScale

        if let casing {
            context.beginPath()
            context.addPath(casing)
            context.setLineWidth(width + Self.casingExtra / zoomScale)
            context.setStrokeColor(MyMapPalette.ink.withAlphaComponent(0.55).cgColor)
            context.strokePath()
        }
        for band in bands {
            context.beginPath()
            context.addPath(band.path)
            context.setLineWidth(width)
            context.setStrokeColor(band.color.cgColor)
            context.strokePath()
        }
    }

    /// Cuts the line where its colour changes, starting each new run at the
    /// shared vertex so the bands meet instead of leaving a gap.
    private func build() {
        guard route.pointCount > 1 else { return }
        let points = route.points()
        let colors = route.gradientColors
        guard !colors.isEmpty else { return }

        let whole = CGMutablePath()
        whole.move(to: point(for: points[0]))

        var runs: [(UIColor, CGMutablePath)] = []
        var currentColor: UIColor?
        for index in 0..<(route.pointCount - 1) {
            let color = colors[min(index, colors.count - 1)]
            if currentColor == nil || !(currentColor!.isEqual(color)) {
                let path = CGMutablePath()
                path.move(to: point(for: points[index]))
                runs.append((color, path))
                currentColor = color
            }
            runs[runs.count - 1].1.addLine(to: point(for: points[index + 1]))
            whole.addLine(to: point(for: points[index + 1]))
        }

        casing = whole
        bands = runs.map { ($0.0, $0.1 as CGPath) }
    }
}

// MARK: - Fog of roads

/// Ember → gold. A road driven once is a dim coal; the one you drive every
/// day is hot metal. Sampled from four stops so the six bands land on a curve
/// rather than four hard steps.
enum RoadHeatRamp {
    private static let stops: [(t: Double, r: Double, g: Double, b: Double)] = [
        // Not darker than this at the bottom: a road driven once still has to
        // be a road you can see, and a muddy ember on a night map is not one.
        (0.00, 0.75, 0.29, 0.11),
        (0.35, 0.92, 0.34, 0.12),
        (0.70, 0.98, 0.66, 0.17),
        (1.00, 1.00, 0.94, 0.76),
    ]

    static func color(at value: Double) -> UIColor {
        let t: Double = min(1, max(0, value))
        for i in 1..<stops.count where t <= stops[i].t {
            let lo = stops[i - 1]
            let hi = stops[i]
            let span: Double = hi.t - lo.t
            let k: Double = span > 0 ? (t - lo.t) / span : 0
            let red: Double = lo.r + (hi.r - lo.r) * k
            let green: Double = lo.g + (hi.g - lo.g) * k
            let blue: Double = lo.b + (hi.b - lo.b) * k
            return UIColor(red: CGFloat(red), green: CGFloat(green),
                           blue: CGFloat(blue), alpha: 1)
        }
        let last = stops[stops.count - 1]
        return UIColor(red: CGFloat(last.r), green: CGFloat(last.g),
                       blue: CGFloat(last.b), alpha: 1)
    }
}

/// Runs bucketed into a coarse map grid, each bucket one prebuilt CGPath.
///
/// MapKit asks an overlay renderer to draw one tile at a time. Without this,
/// every tile re-strokes the whole country — which is exactly what made the
/// map hitch while panning, and it got worse the more you drove.
struct MapPathChunks {
    private struct Chunk {
        let rect: MKMapRect
        let path: CGPath
    }

    private let chunks: [Chunk]

    /// ~78 km per bucket: wide enough that a motorway leg stays whole, tight
    /// enough that a city tile skips the rest of the map.
    private static let bucketSize = MKMapSize.world.width / 512
    /// A stroke can be far wider than its geometry, so a chunk whose line is
    /// just off-screen may still paint into the tile.
    private static let padding: Double = 8_000

    init(_ polylines: [MKPolyline], transform: (MKMapPoint) -> CGPoint) {
        var byBucket: [Int64: (rect: MKMapRect, path: CGMutablePath)] = [:]
        for line in polylines {
            guard line.pointCount >= 2 else { continue }
            let box = line.boundingMapRect
            let key = Int64(box.midX / Self.bucketSize) &* 1_024
                &+ Int64(box.midY / Self.bucketSize)

            var entry = byBucket[key] ?? (box, CGMutablePath())
            entry.rect = entry.rect.union(box)
            let points = line.points()
            entry.path.move(to: transform(points[0]))
            for i in 1..<line.pointCount {
                entry.path.addLine(to: transform(points[i]))
            }
            byBucket[key] = entry
        }
        chunks = byBucket.values.map {
            Chunk(rect: $0.rect.insetBy(dx: -Self.padding, dy: -Self.padding), path: $0.path)
        }
    }

    /// The paths touching `mapRect`. Resolve this ONCE per tile and reuse it
    /// across every stroke pass — the veil strokes eight times, and rescanning
    /// the whole country's buckets for each pass was eight times the work for
    /// one answer.
    func visiblePaths(in mapRect: MKMapRect) -> [CGPath] {
        chunks.compactMap { $0.rect.intersects(mapRect) ? $0.path : nil }
    }
}

/// The whole driven network as one overlay, pre-collapsed into heat bands by
/// `RoadFog`.
final class RoadFogOverlay: NSObject, MKOverlay {
    struct Tier {
        let intensity: Double
        let passes: Int
        let polylines: [MKPolyline]
        let coarse: [MKPolyline]
    }

    let tiers: [Tier]
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(fog: RoadFog) {
        var built: [Tier] = []
        var box = MKMapRect.null
        for tier in fog.tiers {
            let polylines = tier.runs.compactMap { run -> MKPolyline? in
                guard run.count > 1 else { return nil }
                let line = MKPolyline(coordinates: run, count: run.count)
                box = box.isNull ? line.boundingMapRect : box.union(line.boundingMapRect)
                return line
            }
            let coarse = tier.coarseRuns.compactMap { run -> MKPolyline? in
                guard run.count > 1 else { return nil }
                return MKPolyline(coordinates: run, count: run.count)
            }
            built.append(Tier(
                intensity: tier.intensity, passes: tier.passes,
                polylines: polylines, coarse: coarse
            ))
        }
        self.tiers = built
        self.boundingMapRect = box.isNull ? .world : box
        self.coordinate = MKMapPoint(x: box.midX, y: box.midY).coordinate
        super.init()
    }

    var allPolylines: [MKPolyline] { tiers.flatMap(\.polylines) }
    var allCoarsePolylines: [MKPolyline] { tiers.flatMap(\.coarse) }
}

/// Draws the network: one stroke per heat band, coldest first.
///
/// Widths are screen-space and nothing else. The first cut also carried a
/// ground-space floor (700 m) so one layer could read as territory from far
/// away — but a floor in metres is a floor at EVERY zoom, so up close every
/// street became a 700 m orange blob and the streets vanished under it.
/// Showing territory is the fog-of-war veil's job now; the heat lines stay
/// lines, which is also how Strava's heatmap behaves at every zoom.
final class RoadFogRenderer: MKOverlayRenderer {
    private let fog: RoadFogOverlay
    private var fine: [MapPathChunks] = []
    private var coarse: [MapPathChunks] = []

    private static let minWidth: CGFloat = 2.0
    private static let maxWidth: CGFloat = 4.6
    /// Below this the thinned geometry is indistinguishable and much cheaper.
    static let coarseZoom: MKZoomScale = 0.0015

    init(fog: RoadFogOverlay) {
        self.fog = fog
        super.init(overlay: fog)
        // Only after `super.init` does `point(for:)` have a transform, and it
        // is fixed for the renderer's life — so the paths are built once here
        // rather than inside every tile callback.
        fine = fog.tiers.map { MapPathChunks($0.polylines) { self.point(for: $0) } }
        coarse = fog.tiers.map { MapPathChunks($0.coarse) { self.point(for: $0) } }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let thinned = zoomScale < Self.coarseZoom

        // Coldest first, so the roads you actually live on sit on top.
        for (index, tier) in fog.tiers.enumerated() {
            let paths = (thinned ? coarse[index] : fine[index]).visiblePaths(in: mapRect)
            guard !paths.isEmpty else { continue }
            let color = RoadHeatRamp.color(at: tier.intensity)
            let width = (Self.minWidth
                + (Self.maxWidth - Self.minWidth) * CGFloat(tier.intensity)) / zoomScale

            // A glow under EVERYTHING is what turned the first cut into a
            // wash. Only the roads that earned it get one.
            if tier.intensity > 0.45 {
                context.beginPath()
                paths.forEach(context.addPath)
                context.setLineWidth(width * 3)
                context.setStrokeColor(color.withAlphaComponent(0.14).cgColor)
                context.strokePath()
            }

            context.beginPath()
            paths.forEach(context.addPath)
            context.setLineWidth(width)
            context.setStrokeColor(
                color.withAlphaComponent(0.80 + 0.20 * CGFloat(tier.intensity)).cgColor)
            context.strokePath()
        }
    }
}

// MARK: - Fog of war

/// The dark over everywhere you have not been. Roads you have driven cut a
/// soft corridor through it, so the map reads as a thing you uncovered rather
/// than a thing you were given.
///
/// It covers the whole world on purpose: a corner with no veil would read as
/// explored.
final class FogOfWarOverlay: NSObject, MKOverlay {
    let revealed: [MKPolyline]
    let coarse: [MKPolyline]
    let coordinate: CLLocationCoordinate2D
    var boundingMapRect: MKMapRect { .world }

    init(fog: RoadFogOverlay) {
        revealed = fog.allPolylines
        coarse = fog.allCoarsePolylines
        coordinate = fog.coordinate
        super.init()
    }
}

final class FogOfWarRenderer: MKOverlayRenderer {
    private let veil: FogOfWarOverlay
    private var fine: MapPathChunks?
    private var coarse: MapPathChunks?

    /// Full width of the corridor a road clears, in metres — so ±70 m.
    ///
    /// This was 240 (±120 m), picked against sparse test data where the roads
    /// were kilometres apart. In an actual city, where you have driven a lot
    /// of streets a couple of hundred metres from each other, corridors that
    /// wide merge into one another and the whole town comes out «opened» —
    /// which is why the fog looked like it simply was not there. Tight enough
    /// to leave the blocks between the streets you drove still dark is the
    /// entire point of it.
    private static let revealMetres: Double = 140
    /// From a country away the corridor has to survive as something wider than
    /// a hairline, or the veil swallows the whole map.
    private static let minRevealPoints: CGFloat = 8
    private static let veilColor = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
    private static let veilAlpha: CGFloat = 0.70

    /// How much of the veil to draw at this zoom, 0…1.
    ///
    /// From a country away the veil says nothing — the region fills already
    /// show what is opened, and a flat 70% dark over half of Russia is not
    /// information, it is a dark map. What it DOES do at that scale is make
    /// MapKit's tile-by-tile compositing impossible to miss: one tile arriving
    /// late is a bright rectangle the size of an oblast. That is what
    /// «подгружается фрагментом» was.
    ///
    /// So it fades out above region scale, where it has a job, and is gone by
    /// the time you are looking at a country.
    static func strength(at zoomScale: MKZoomScale) -> CGFloat {
        let full: MKZoomScale = 2e-4    // ≈300 km across the screen
        let none: MKZoomScale = 5e-5    // ≈1200 km
        if zoomScale >= full { return 1 }
        if zoomScale <= none { return 0 }
        return CGFloat((zoomScale - none) / (full - none))
    }

    /// Widest-and-faintest to narrowest-and-solid: `.destinationOut` passes
    /// turn a hard stroke into a feathered hole.
    ///
    /// Each pass multiplies what the last one left, so the alphas are derived
    /// from the curve the edge should follow rather than picked by hand — four
    /// hand-picked steps drew visible terraces around every road, like a
    /// contour map. The passes cannot be subsetted for the same reason: drop
    /// the last one and the middle of the corridor never clears.
    private static func featherTable(passes: Int) -> [(width: CGFloat, alpha: CGFloat)] {
        var out: [(CGFloat, CGFloat)] = []
        var remaining: CGFloat = 1
        for step in 0..<passes {
            let t = CGFloat(step + 1) / CGFloat(passes)
            let width = 1 - 0.82 * CGFloat(step) / CGFloat(max(passes - 1, 1))
            // Veil still standing inside this radius: 1 at the outer edge,
            // 0 at the core.
            let target = pow(1 - t, 1.7)
            let alpha = remaining > 0 ? min(1, max(0, 1 - target / remaining)) : 1
            remaining = target
            out.append((width, alpha))
        }
        return out
    }

    private static let feather = featherTable(passes: 8)
    /// Feathering you cannot see is not worth eight strokes of the whole
    /// visible network. From far out the corridor is a dozen points wide and
    /// three steps are indistinguishable from eight.
    private static let coarseFeather = featherTable(passes: 3)

    init(veil: FogOfWarOverlay) {
        self.veil = veil
        super.init(overlay: veil)
        fine = MapPathChunks(veil.revealed) { self.point(for: $0) }
        coarse = MapPathChunks(veil.coarse) { self.point(for: $0) }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let strength = Self.strength(at: zoomScale)
        guard strength > 0.01 else { return }
        guard let chunks = (zoomScale < RoadFogRenderer.coarseZoom ? coarse : fine) else { return }
        let rect = self.rect(for: mapRect)
        let paths = chunks.visiblePaths(in: mapRect)
        let fill = Self.veilColor.withAlphaComponent(Self.veilAlpha * strength).cgColor

        // Most tiles are nowhere near a road you have driven: solid veil and
        // nothing else. Filling those directly — no transparency layer, no
        // stroke passes — is what stops a wide view from arriving one tile at
        // a time. The veil covers the whole world, so most tiles take this
        // path.
        guard !paths.isEmpty else {
            context.setFillColor(fill)
            context.fill(rect)
            return
        }

        // The holes are punched with `.destinationOut`, which erases whatever
        // is already in the context — so the veil gets its own transparency
        // layer and cannot reach the overlays drawn before it. Allocating that
        // offscreen buffer is the expensive part, which is why only the tiles
        // that actually need holes pay for it.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(fill)
        context.fill(rect)

        // Metres per map point is a function of latitude, so it is taken from
        // THIS tile rather than from the middle of the network — otherwise a
        // corridor drawn in Murmansk is sized for Sochi.
        let metre = MKMapPointsPerMeterAtLatitude(
            MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate.latitude)
        let width = max(CGFloat(Self.revealMetres * metre), Self.minRevealPoints / zoomScale)
        let feather = width * zoomScale < 26 ? Self.coarseFeather : Self.feather

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.destinationOut)
        for pass in feather {
            context.beginPath()
            paths.forEach(context.addPath)
            context.setLineWidth(width * pass.width)
            context.setStrokeColor(UIColor(white: 0, alpha: pass.alpha).cgColor)
            context.strokePath()
        }
        context.setBlendMode(.normal)
        context.endTransparencyLayer()
    }
}

// MARK: - Regions

/// An administrative region drawn on the map. One class, three looks — the
/// filled territory you have opened, the traced border of the one you tapped,
/// and the dashed outline of a region still dark.
final class RegionPolygon: MKPolygon {
    enum Style {
        case opened      // filled, quiet border
        case selected    // filled, bright border
        case locked      // dashed border, almost no fill
    }

    var regionId: String = ""
    var style: Style = .opened
}

final class RegionPolygonRenderer: MKPolygonRenderer {
    private let style: RegionPolygon.Style

    init(region: RegionPolygon) {
        self.style = region.style
        super.init(polygon: region)
        switch style {
        // The fills are deliberately faint. They sit under the fog-of-war
        // veil, whose job is to say what is open and what is dark; a heavier
        // wash on top of that just flattens the corridors back out.
        case .opened:
            fillColor = MyMapPalette.accent.withAlphaComponent(0.06)
            strokeColor = MyMapPalette.accent.withAlphaComponent(0.38)
            lineWidth = 1.2
        case .selected:
            fillColor = MyMapPalette.accent.withAlphaComponent(0.09)
            strokeColor = MyMapPalette.accentBright
            lineWidth = 2.4
        case .locked:
            fillColor = UIColor.white.withAlphaComponent(0.035)
            strokeColor = UIColor.white.withAlphaComponent(0.5)
            lineWidth = 1.8
            lineDashPattern = [6, 5]
        }
        lineJoin = .round
    }

    /// The selected border gets the same soft halo the routes have, so the
    /// region you tapped reads as lit rather than merely outlined.
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        if style == .selected {
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(9 / zoomScale)
            context.setLineJoin(.round)
            context.setStrokeColor(MyMapPalette.accent.withAlphaComponent(0.22).cgColor)
            context.strokePath()
            context.restoreGState()
        }
        super.draw(mapRect, zoomScale: zoomScale, in: context)
    }
}

// MARK: - Cities

/// City dot: constant-screen-size annotation with its name beside it.
final class CityDotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let cityName: String
    /// 0…1 — how much of the city you have covered. Drives the dot size, so a
    /// place you know well reads heavier than one you clipped once.
    let coverage: Double

    init(coordinate: CLLocationCoordinate2D, cityName: String, coverage: Double) {
        self.coordinate = coordinate
        self.cityName = cityName
        self.coverage = coverage
    }
}

final class CityDotView: MKAnnotationView {
    static let reuseID = "CityDot"

    private let dot = UIView()
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 8, height: 8)
        isEnabled = false
        displayPriority = .defaultHigh
        collisionMode = .circle

        dot.layer.borderWidth = 1.6
        dot.layer.borderColor = UIColor.white.cgColor
        dot.backgroundColor = MyMapPalette.accent
        addSubview(dot)

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.92)
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.75
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        addSubview(label)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    private func configure() {
        guard let city = annotation as? CityDotAnnotation else { return }
        let size = 6 + CGFloat(min(1, city.coverage)) * 4
        dot.frame = CGRect(x: (8 - size) / 2, y: (8 - size) / 2, width: size, height: size)
        dot.layer.cornerRadius = size / 2
        label.text = city.cityName
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 12, y: -label.bounds.height / 2 + 4)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}

// MARK: - Trips

/// One trip on the map. Clusters into «12» when zoomed out — the canon's
/// answer to a map covered in hairlines you cannot read.
final class TripPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let tripId: UUID
    let photoFilename: String?

    init(coordinate: CLLocationCoordinate2D, tripId: UUID, photoFilename: String?) {
        self.coordinate = coordinate
        self.tripId = tripId
        self.photoFilename = photoFilename
    }
}

final class TripPinView: MKAnnotationView {
    static let reuseID = "TripPin"
    static let clusterID = "TripCluster"

    private let plate = UIView()
    private let thumb = UIImageView()
    private let glyph = TripGlyphView()
    private var loadToken: UUID?
    private var isSelectedTrip = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        centerOffset = .zero
        clusteringIdentifier = Self.clusterID
        displayPriority = .defaultLow
        collisionMode = .circle
        isAccessibilityElement = true
        accessibilityIdentifier = "map_trip_pin"

        plate.frame = bounds
        plate.layer.cornerRadius = 9
        plate.layer.cornerCurve = .continuous
        plate.backgroundColor = .white
        plate.layer.shadowColor = UIColor.black.cgColor
        plate.layer.shadowOpacity = 0.35
        plate.layer.shadowRadius = 4
        plate.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(plate)

        thumb.frame = plate.bounds.insetBy(dx: 2, dy: 2)
        thumb.layer.cornerRadius = 7
        thumb.layer.cornerCurve = .continuous
        thumb.clipsToBounds = true
        thumb.contentMode = .scaleAspectFill
        plate.addSubview(thumb)

        glyph.frame = plate.bounds.insetBy(dx: 2, dy: 2)
        glyph.backgroundColor = .clear
        plate.addSubview(glyph)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken = nil
        thumb.image = nil
        glyph.isHidden = false
        setSelectedAppearance(false)
    }

    /// The selected trip's pin grows and turns accent (canon
    /// «trip-pin-active»).
    ///
    /// The flag is REMEMBERED rather than only painted. MapKit re-assigns
    /// `annotation` whenever it re-evaluates clustering, which runs
    /// `configure()` again — and that used to reset the look to unselected, so
    /// the trip you had just opened sat there as a plain white pin.
    func setSelectedAppearance(_ selected: Bool) {
        isSelectedTrip = selected
        applySelectedAppearance()
    }

    private func applySelectedAppearance() {
        // Out of the cluster while selected, or the trip you just opened is
        // swallowed by a «9» badge and there is nothing on the map to say
        // which one it is.
        clusteringIdentifier = isSelectedTrip ? nil : Self.clusterID
        plate.backgroundColor = isSelectedTrip ? MyMapPalette.accentBright : .white
        glyph.tint = isSelectedTrip ? .white : MyMapPalette.accent
        glyph.setNeedsDisplay()
        let scale: CGFloat = isSelectedTrip ? 1.28 : 1
        transform = CGAffineTransform(scaleX: scale, y: scale)
        displayPriority = isSelectedTrip ? .required : .defaultLow
        // Lets the UI tour tell an opened trip's pin from the rest, which is
        // otherwise only a colour.
        accessibilityValue = isSelectedTrip ? "selected" : "unselected"
    }

    private func configure() {
        guard let pin = annotation as? TripPinAnnotation else { return }
        applySelectedAppearance()
        guard let filename = pin.photoFilename else {
            glyph.isHidden = false
            return
        }
        let token = UUID()
        loadToken = token
        Task { @MainActor in
            guard let image = await PhotoStorageService.loadThumbnail(filename: filename, maxSize: 64),
                  loadToken == token else { return }
            thumb.image = image
            glyph.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}

/// Fallback mark for a trip with no photo: the same zigzag trail the empty
/// state uses, so a pin without a picture still says «поездка».
private final class TripGlyphView: UIView {
    var tint: UIColor = MyMapPalette.accent

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let w = rect.width, h = rect.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * 0.16, y: h * 0.66))
        path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.34))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.28))
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        context.setStrokeColor(tint.cgColor)
        path.stroke()
    }
}

// MARK: - Route endpoints

/// Where the selected drive began and where it ended.
///
/// The line alone says which roads, never which way — «просто путь и всё».
/// Green for the start, white for the finish, because that is already what the
/// share poster and every route thumbnail in the app mean by those two dots.
final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let isStart: Bool
    let title: String?

    init(coordinate: CLLocationCoordinate2D, isStart: Bool, title: String) {
        self.coordinate = coordinate
        self.isStart = isStart
        self.title = title
        super.init()
    }
}

final class RouteEndpointView: MKAnnotationView {
    static let reuseID = "RouteEndpoint"
    private static let start = UIColor(red: 0x5A/255, green: 0xC8/255, blue: 0x3C/255, alpha: 1)

    private let dot = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 18, height: 18)
        centerOffset = .zero
        // Never clustered and never hidden: two dots are the whole answer to
        // «откуда и куда», and a collision rule that drops one is no answer.
        displayPriority = .required
        collisionMode = .circle
        // Not a control — a tap here should still reach the road underneath.
        isEnabled = false
        isAccessibilityElement = true

        dot.frame = bounds.insetBy(dx: 3, dy: 3)
        dot.layer.cornerRadius = dot.bounds.width / 2
        addSubview(dot)

        backgroundColor = .white
        layer.cornerRadius = 9
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    private func configure() {
        guard let endpoint = annotation as? RouteEndpointAnnotation else { return }
        dot.backgroundColor = endpoint.isStart ? Self.start : MyMapPalette.ink
        accessibilityLabel = endpoint.title
        accessibilityIdentifier = endpoint.isStart ? "map_route_start" : "map_route_finish"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}

// MARK: - Country chips

/// «🇷🇺 Россия» — shown only at far zoom, over the countries you have driven
/// in. Anchored to the middle of your own regions there, not to the country's
/// geographic centre, so the chip sits where your life actually is.
final class CountryChipAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let countryCode: String

    init(coordinate: CLLocationCoordinate2D, countryCode: String, name: String) {
        self.coordinate = coordinate
        self.countryCode = countryCode
        self.title = name
    }
}

final class CountryChipView: MKAnnotationView {
    static let reuseID = "CountryChip"

    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isEnabled = false
        displayPriority = .required
        collisionMode = .rectangle

        backgroundColor = .white
        layer.cornerRadius = 13
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)

        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = MyMapPalette.ink
        addSubview(label)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    private func configure() {
        guard let chip = annotation as? CountryChipAnnotation else { return }
        label.text = "\(RegionAtlas.flag(for: chip.countryCode)) \(chip.title ?? "")"
        label.sizeToFit()
        let width = label.bounds.width + 26
        frame = CGRect(x: 0, y: 0, width: width, height: 26)
        label.frame = CGRect(x: 13, y: 0, width: label.bounds.width, height: 26)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}

/// «12» — white disc, accent ring, accent count. Tap zooms inside.
final class TripClusterView: MKAnnotationView {
    static let reuseID = "TripClusterView"

    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        collisionMode = .circle
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityIdentifier = "map_cluster"

        backgroundColor = .white
        layer.cornerRadius = 14
        layer.borderWidth = 2
        layer.borderColor = MyMapPalette.accent.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        label.frame = bounds
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 13, weight: .heavy)
        label.textColor = MyMapPalette.accent
        addSubview(label)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    private func configure() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count
        label.text = count > 99 ? "99+" : "\(count)"
        let width: CGFloat = count > 99 ? 36 : 28
        frame = CGRect(x: 0, y: 0, width: width, height: 28)
        layer.cornerRadius = 14
        label.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}
