import MapKit

/// Находка на «Атласе» — печать.
///
/// `MKAnnotation`, а не оверлей, и это решение спеки (§2): печать обязана быть
/// НАД туманом, постоянного размера, нажимаемой и видимой VoiceOver. Оверлей
/// здесь невозможен физически — экранная вуаль сидит под контейнером
/// аннотаций (`VeilSeat.belowAnnotations`), то есть ПОВЕРХ всех оверлеев, и
/// нарисованная оверлеем печать оказалась бы под непрозрачным туманом.
///
/// Подпись для VoiceOver приходит ГОТОВОЙ строкой: язык знает экран, а не
/// карта, — тот же приём, что у `RegionLabelAnnotation`.
final class SealAnnotation: NSObject, MKAnnotation {
    let discovery: Discovery
    /// «Печать: загадка» — собрано экраном через `AppStrings`.
    let accessibilityText: String

    var coordinate: CLLocationCoordinate2D { discovery.coordinate }
    var id: UUID { discovery.id }
    var kind: DiscoveryKind { discovery.kind }

    init(discovery: Discovery, accessibilityText: String) {
        self.discovery = discovery
        self.accessibilityText = accessibilityText
        super.init()
    }
}

/// Медальон на карте.
///
/// Рисует его `SealPainter` — сюда приезжает готовая картинка, и вью не знает
/// ни про цвета, ни про символы. Кластеризуется (`SealCluster`) и НИКОГДА не
/// уступает место: `displayPriority = .required` — печать это ответ на «что я
/// тут нашёл», и правило столкновений, которое её прячет, — не ответ.
final class SealView: MKAnnotationView {
    static let reuseID = "Seal"
    static let clusterID = "SealCluster"

    private let medallion = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: SealPainter.size, height: SealPainter.size)
        centerOffset = .zero
        clusteringIdentifier = Self.clusterID
        displayPriority = .required
        collisionMode = .circle
        isAccessibilityElement = true
        accessibilityIdentifier = "map_seal"
        accessibilityTraits = .button

        medallion.frame = bounds
        medallion.contentMode = .center
        addSubview(medallion)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Печать, снятая посреди своей анимации появления, вернулась бы из
        // очереди полупрозрачной — и осталась бы такой навсегда.
        layer.removeAllAnimations()
        alpha = 1
    }

    private func configure() {
        guard let seal = annotation as? SealAnnotation else { return }
        medallion.image = SealPainter.image(
            kind: seal.kind, symbol: seal.discovery.symbol,
            scale: traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        )
        accessibilityLabel = seal.accessibilityText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}

/// «3» — печати, слипшиеся на мелком масштабе.
///
/// Кольцо у кластера — цвета БОЛЬШИНСТВА: три загадки и веха читаются как
/// бирюзовая горсть, и это правда про то, что под ней. Белой обводки, как у
/// кластера поездок, здесь нет нарочно — печать это тёмный медальон, и её
/// горсть обязана оставаться медальоном.
final class SealClusterView: MKAnnotationView {
    static let reuseID = "SealClusterView"

    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: SealPainter.size, height: SealPainter.size)
        collisionMode = .circle
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityIdentifier = "map_seal_cluster"

        backgroundColor = SealPainter.disc
        layer.cornerRadius = SealPainter.size / 2
        layer.borderWidth = SealPainter.ringWidth

        label.frame = bounds
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .heavy)
        addSubview(label)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    private func configure() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let members = cluster.memberAnnotations.compactMap { $0 as? SealAnnotation }
        let colour = SealPainter.ring(for: Self.majorityKind(of: members))
        layer.borderColor = colour.cgColor
        label.textColor = colour
        let count = cluster.memberAnnotations.count
        label.text = count > 99 ? "99+" : "\(count)"
        accessibilityLabel = label.text
    }

    /// Чей цвет носит горсть. Ничья разрешается по редкости — секрет, загадка,
    /// веха: из двух равных долей человеку интереснее та, которой почти не
    /// бывает. Чистая функция, чтобы ничья не решалась порядком аннотаций,
    /// который задаёт MapKit.
    static func majorityKind(of seals: [SealAnnotation]) -> DiscoveryKind {
        guard !seals.isEmpty else { return .riddle }
        var counts: [DiscoveryKind: Int] = [:]
        for seal in seals { counts[seal.kind, default: 0] += 1 }
        // Порядок редкости: первым проверяется самое редкое, и «строго
        // больше» оставляет ничью за ним.
        let order: [DiscoveryKind] = [.secret, .riddle, .milestone]
        var best = order[0]
        var bestCount = -1
        for kind in order where (counts[kind] ?? 0) > bestCount {
            best = kind
            bestCount = counts[kind] ?? 0
        }
        return best
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}

/// «Печать проступает»: прорезь в тумане вокруг новой находки.
///
/// Чистыми функциями и отдельно от `FogRevealAnimation` нарочно: у той вопрос
/// «машина открывает дорогу прямо сейчас» (150 м, 0.7 с, шестьдесят кадров в
/// секунду всю поездку), у этой — «на открытом Атласе появилась печать» (120 м,
/// 0.6 с, один раз). Числа разные, и сведённые в одну константу они разъехались
/// бы при первой же правке любой из двух.
///
/// Растра это НЕ касается: прорезь режет вуаль маской
/// (`VeilRevealMask`), как и у машины, — перерисовывать восьмимегабайтную
/// картинку ради полусекунды нельзя.
enum SealRevealAnimation {
    static let duration: Double = 0.6
    /// Радиус прорези в метрах на земле.
    static let radiusMetres: Double = 120

    /// `reduceMotion` даёт единицу сразу: человек, попросивший не двигать
    /// картинку, получает открытое место, а не отказ от него.
    static func progress(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        guard duration > 0 else { return 1 }
        let t = min(1, max(0, elapsed / duration))
        return 1 - pow(1 - t, 3)
    }

    static func isDone(elapsed: TimeInterval, reduceMotion: Bool) -> Bool {
        reduceMotion || elapsed >= duration
    }
}
