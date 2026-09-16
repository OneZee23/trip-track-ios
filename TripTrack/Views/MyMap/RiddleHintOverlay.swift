import MapKit

/// Подсказка нерешённой загадки: круг на тумане, «?» в нём и одна строка.
///
/// Точка загадки НЕ показывается — в этом весь смысл: «где-то в этом круге
/// дорога упирается в море». Радиус — 5–30 км по плотности открытых дорог
/// вокруг (в городе круг мельче, в степи крупнее), центр круга смещён от самой
/// загадки, чтобы она не оказалась ровно в середине.
struct RiddleHint: Identifiable, Equatable {
    /// `Riddle.id` — «<type>:<geohash7>».
    let id: String
    let type: RiddleType
    /// Центр КРУГА, а не загадки.
    let centre: CLLocationCoordinate2D
    let radiusMetres: Double

    static func == (lhs: RiddleHint, rhs: RiddleHint) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
            && lhs.centre.latitude == rhs.centre.latitude
            && lhs.centre.longitude == rhs.centre.longitude
            && lhs.radiusMetres == rhs.radiusMetres
    }

    // MARK: - Сколько их

    /// Не больше трёх одновременно (спека §2.2), ближайшие к ОТКРЫТОЙ
    /// территории.
    static let maxShown = 3

    /// Три ближайшие нерешённые загадки — или меньше.
    ///
    /// Близость считается до центроидов открытых регионов
    /// (`RevealedLayer.regionCentroids`), а не до дома и не до последней
    /// поездки: подсказка обязана лежать там, куда человек ездит, а «дом» —
    /// это другой вопрос, со своим согласием (`JourneySuggester.shouldAskHome`).
    ///
    /// Открытого нет вовсе — нет и подсказок: круг «где-то в этом круге» на
    /// карте, где ничего не открыто, это не загадка, а случайная точка мира.
    static func plan(
        riddles: [Riddle],
        solvedRiddleIds: Set<String>,
        centroids: [CLLocationCoordinate2D],
        layer: RevealedLayer,
        limit: Int = RiddleHint.maxShown
    ) -> [RiddleHint] {
        guard !centroids.isEmpty, limit > 0 else { return [] }
        let unsolved = riddles.filter { !solvedRiddleIds.contains($0.id) }
        guard !unsolved.isEmpty else { return [] }

        var ranked: [(riddle: Riddle, distance: CLLocationDistance)] = []
        ranked.reserveCapacity(unsolved.count)
        for riddle in unsolved {
            ranked.append((riddle, distanceToNearest(of: riddle.coordinate, among: centroids)))
        }
        // Ничья по расстоянию решается id, а не порядком в бандле: два маяка на
        // одном мысу иначе менялись бы местами от перезапуска к перезапуску.
        ranked.sort { lhs, rhs in
            if lhs.distance == rhs.distance { return lhs.riddle.id < rhs.riddle.id }
            return lhs.distance < rhs.distance
        }

        var hints: [RiddleHint] = []
        for entry in ranked.prefix(limit) {
            let roads = openRunsWithin50km(of: entry.riddle.coordinate, in: layer)
            let radius = radiusMetres(roadsWithin50km: roads)
            let centre = offsetCentre(
                for: entry.riddle.id, around: entry.riddle.coordinate, radius: radius)
            hints.append(RiddleHint(
                id: entry.riddle.id, type: entry.riddle.type,
                centre: centre, radiusMetres: radius))
        }
        return hints
    }

    static func distanceToNearest(
        of coordinate: CLLocationCoordinate2D, among others: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return others.reduce(Double.infinity) { best, other in
            min(best, point.distance(
                from: CLLocation(latitude: other.latitude, longitude: other.longitude)))
        }
    }

    // MARK: - Радиус

    static let minRadiusMetres: Double = 5_000
    static let maxRadiusMetres: Double = 30_000
    /// При стольких открытых прогонах вокруг круг сжимается до минимума.
    static let denseRoads: Double = 200

    /// Формула плана: `min(30, max(5, 5 + 25 · (1 − roads/200)))` километров.
    ///
    /// Смысл — «насколько тесно человеку тут искать»: в городе, где вокруг
    /// сотни открытых кусков дороги, круг в тридцать километров накрыл бы
    /// полобласти и не сказал бы ничего; в степи пятикилометровый круг был бы
    /// прямым указанием координаты.
    static func radiusMetres(roadsWithin50km: Int) -> Double {
        let density = Double(max(0, roadsWithin50km)) / denseRoads
        let km = 5 + 25 * (1 - density)
        return min(maxRadiusMetres, max(minRadiusMetres, km * 1_000))
    }

    /// Сколько ОТКРЫТЫХ ПРОГОНОВ лежит в пятидесяти километрах от точки.
    ///
    /// Это не плотность дорог мира (её мы не знаем — карта чужая, дорожного
    /// графа у нас нет), а плотность ОТКРЫТОГО: прогоны слоя — те же куски
    /// дороги, которыми нарисован туман, длиной в тайл и короче. Считать их
    /// честнее, чем мерить километры: город даёт много коротких прогонов, а
    /// трасса — один длинный, и именно такая разница здесь и нужна.
    ///
    /// Сравниваются КОРОБКИ прогонов, а не точки: у зрелой библиотеки прогонов
    /// десятки тысяч, и поднимать вершины ради числа, которое потом зажимается
    /// в 5–30 км, незачем.
    static func openRunsWithin50km(
        of coordinate: CLLocationCoordinate2D, in layer: RevealedLayer
    ) -> Int {
        let metre = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let reach = 50_000 * metre
        let centre = MKMapPoint(coordinate)
        let box = MKMapRect(x: centre.x - reach, y: centre.y - reach,
                            width: reach * 2, height: reach * 2)
        return layer.polylines(for: .fine).reduce(0) { count, line in
            count + (line.boundingMapRect.intersects(box) ? 1 : 0)
        }
    }

    // MARK: - Смещение центра

    /// Центр круга — смещённая от загадки точка, не больше чем на половину
    /// радиуса.
    ///
    /// Иначе круг был бы прицелом: середина — это и есть ответ, и любой, кто
    /// увидел круг дважды, нашёл бы точку без дороги. Смещение ДЕТЕРМИНИРОВАНО
    /// (хеш от id загадки, а не `random`): круг обязан стоять на месте между
    /// запусками, между пересчётами и на втором телефоне — иначе он читался бы
    /// как «загадка переехала».
    ///
    /// Доля смещения — от четверти до половины радиуса: ноль оставил бы точку
    /// ровно в середине, а больше половины увёл бы саму загадку за край круга.
    static func offsetCentre(
        for id: String, around coordinate: CLLocationCoordinate2D, radius: Double
    ) -> CLLocationCoordinate2D {
        let seed = hash(id)
        let angle = Double(seed % 10_000) / 10_000 * 2 * .pi
        let fraction = 0.25 + Double((seed >> 20) % 10_000) / 10_000 * 0.25
        let distance = radius * fraction
        let dLat = distance * cos(angle) / 111_320
        let cosLat = max(0.01, cos(coordinate.latitude * .pi / 180))
        let dLon = distance * sin(angle) / (111_320 * cosLat)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLon
        )
    }

    /// FNV-1a. Своя, а не `hashValue`: тот в Swift солится при каждом запуске
    /// процесса, и круг переезжал бы после каждого убийства приложения.
    static func hash(_ string: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100000001b3
        }
        return value
    }
}

/// Слова загадки — одной дверью.
///
/// Строка приходит из бандла по ТИПУ загадки, и зовут её оба места показа —
/// подсказка на тумане и карточка решённой печати. Неизвестный тип (старый
/// ключ, чужая версия бандла) даёт общую строку-заглушку, а не пустоту.
enum RiddleCopy {
    /// Тип известен — строка по типу из бандла; неизвестен (старый ключ,
    /// чужая версия бандла) — общая строка-заглушка, а не пустота.
    static func line(
        for type: RiddleType?, _ lang: LanguageManager.Language
    ) -> String {
        guard let type else { return AppStrings.mapRiddleHintLine(lang) }
        return AppStrings.riddleLine(lang, type: type)
    }

    /// Тип загадки из ключа находки («bridge:u0h2w1q» → `.bridge`).
    ///
    /// Разбором, а не колонкой: у `Discovery` своего поля типа нет и не будет —
    /// тип это половина ключа по построению (`Riddle.id`), и вторая копия
    /// однажды разошлась бы с первой.
    static func type(ofRiddleKey key: String) -> RiddleType? {
        guard let separator = key.firstIndex(of: ":") else { return RiddleType(rawValue: key) }
        return RiddleType(rawValue: String(key[key.startIndex..<separator]))
    }
}

/// «?» в середине круга и одна строка под ним.
final class RiddleHintAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let hintId: String
    let radiusMetres: Double
    /// `AppStrings.riddleLine` — собрана экраном, который знает язык.
    let line: String

    init(hint: RiddleHint, line: String) {
        self.coordinate = hint.centre
        self.hintId = hint.id
        self.radiusMetres = hint.radiusMetres
        self.line = line
        super.init()
    }
}

/// Пунктирный круг и «?».
///
/// Круг рисуется СЛОЕМ АННОТАЦИИ, а не `MKOverlay` с рендерером: экранная
/// вуаль сидит под контейнером аннотаций и поверх контейнера оверлеев, поэтому
/// оверлейный круг лежал бы под непрозрачным туманом и не был бы виден вовсе.
/// По той же причине его не отдают в растр вуали: круг меняет радиус на каждом
/// зуме, а растр — восемь мегабайт на кадр.
///
/// Рамка вью маленькая (сам «?»), а круг выходит далеко за неё и не
/// обрезается: `masksToBounds` выключен. Так хит-тест «Атласа» видит крошечную
/// цель вместо чашки в полэкрана — впрочем, тапа у подсказки в этой волне нет
/// вовсе (волна 4).
final class RiddleHintView: MKAnnotationView {
    static let reuseID = "RiddleHint"

    private let circle = CAShapeLayer()
    private let chip = UILabel()
    private let caption = UILabel()

    /// Радиус круга В ТОЧКАХ ЭКРАНА — считает карта по зуму и ставит сюда.
    var radiusPoints: CGFloat = 0 {
        didSet {
            guard radiusPoints != oldValue else { return }
            layoutCircle()
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 26, height: 26)
        centerOffset = .zero
        // Не контрол: у подсказки в этой волне нет действия, а перехваченный
        // ею тап не дошёл бы до дороги под кругом.
        isEnabled = false
        displayPriority = .defaultHigh
        collisionMode = .circle
        isAccessibilityElement = true
        layer.masksToBounds = false
        clipsToBounds = false

        circle.fillColor = nil
        circle.strokeColor = SealPainter.ring(for: .riddle).withAlphaComponent(0.8).cgColor
        circle.lineWidth = 1.5
        circle.lineDashPattern = [6, 6]
        circle.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer.addSublayer(circle)

        chip.frame = bounds
        chip.textAlignment = .center
        chip.font = .systemFont(ofSize: 15, weight: .heavy)
        chip.textColor = SealPainter.ring(for: .riddle)
        chip.backgroundColor = SealPainter.disc
        chip.layer.cornerRadius = 13
        chip.layer.borderWidth = 1.5
        chip.layer.borderColor = SealPainter.ring(for: .riddle).withAlphaComponent(0.8).cgColor
        chip.layer.masksToBounds = true
        chip.text = "?"
        addSubview(chip)

        caption.font = .systemFont(ofSize: 11, weight: .semibold)
        caption.textColor = UIColor.white.withAlphaComponent(0.85)
        caption.textAlignment = .center
        caption.numberOfLines = 2
        caption.layer.shadowColor = UIColor.black.cgColor
        caption.layer.shadowOpacity = 0.8
        caption.layer.shadowRadius = 3
        caption.layer.shadowOffset = .zero
        addSubview(caption)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    private func configure() {
        guard let hint = annotation as? RiddleHintAnnotation else { return }
        caption.text = hint.line
        accessibilityLabel = hint.line
        let width: CGFloat = 190
        let height = caption.sizeThatFits(CGSize(width: width, height: 60)).height
        caption.frame = CGRect(x: bounds.midX - width / 2, y: bounds.maxY + 6,
                               width: width, height: height)
        layoutCircle()
    }

    private func layoutCircle() {
        guard radiusPoints > 1 else {
            circle.path = nil
            return
        }
        let box = CGRect(x: bounds.midX - radiusPoints, y: bounds.midY - radiusPoints,
                         width: radiusPoints * 2, height: radiusPoints * 2)
        circle.path = UIBezierPath(ovalIn: box).cgPath
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}
