import MapKit

// MARK: - Palette

enum MyMapPalette {
    static let accent = UIColor(red: 0xC2/255, green: 0x45/255, blue: 0x2B/255, alpha: 1)
    static let accentBright = UIColor(red: 0xE0/255, green: 0x5A/255, blue: 0x38/255, alpha: 1)
    static let ink = UIColor(red: 0x14/255, green: 0x14/255, blue: 0x1A/255, alpha: 1)
}

// MARK: - Region labels

/// Название открытого региона поверх тумана.
///
/// Заливок и контуров у регионов больше нет: `RegionPolygon` во всех трёх
/// стилях (открытый, выбранный, «закрытый» пунктиром) ушёл в 0.7.0 целиком.
/// Пунктирная рамка непосещённого региона — это игровая карта территорий, а
/// туман не показывает границ того, чего ты не видел; а заливка открытого
/// спорила с самой вуалью — та уже говорит, что открыто, а что нет.
///
/// Остаётся имя, и только у того, что открыто. Стоит оно не в географическом
/// центре края, а в середине ОТКРЫТОЙ его части (`RevealedLayer.regionCentroids`):
/// подпись обязана стоять там, где человек был.
final class RegionLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let regionId: String
    let title: String?

    init(regionId: String, coordinate: CLLocationCoordinate2D, title: String) {
        self.regionId = regionId
        self.coordinate = coordinate
        self.title = title
        super.init()
    }
}

final class RegionLabelView: MKAnnotationView {
    static let reuseID = "RegionLabel"

    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        // Не контрол: тап здесь обязан дойти до дороги под подписью.
        isEnabled = false
        // Ниже всех: имя края уступает и пину поездки, и точке города — оно
        // фон, а не объект.
        displayPriority = .defaultLow
        collisionMode = .rectangle

        label.font = .systemFont(ofSize: 9, weight: .semibold)
        // Капитель: имя региона читается как гравюра на тумане, а не как
        // подпись Apple поверх карты.
        label.textColor = UIColor.white.withAlphaComponent(0.75)
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.8
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero
        addSubview(label)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    private func configure() {
        guard let region = annotation as? RegionLabelAnnotation else { return }
        // Заглавные буквы приходят ГОТОВЫМИ: `uppercased()` без языка портит
        // турецкое «i», а языка у аннотации нет — её собирает карта, которая
        // язык знает.
        let name = region.title ?? ""
        label.attributedText = NSAttributedString(string: name, attributes: [.kern: 1.6])
        label.sizeToFit()
        frame = CGRect(x: 0, y: 0, width: label.bounds.width, height: label.bounds.height)
        label.frame = bounds
        accessibilityLabel = name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
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
