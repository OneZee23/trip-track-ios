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

/// Что от подсказки видно на этом масштабе.
///
/// Владелец на устройстве 16 сен: на дальнем зуме три «?» со своими строками
/// съезжаются в одну кучу поверх подписи «КРАСНОДАРСКИЙ КРАЙ». Причина
/// простая: круг задан в метрах, а значок — в точках экрана, и на стране три
/// круга по тридцать километров помещаются в один палец.
///
/// Уровней с 17 сен ДВА, а не три: строки на карте больше нет вовсе (владелец:
/// «сильно много внимания на себя берут секреты и кружки вокруг них»). Читать
/// «Где-то здесь дорога перевалит через хребет» поверх тумана человек не
/// просил — это делает карту списком дел; строка живёт в журнале и в карточке,
/// то есть там, куда за ней приходят.
///
/// Порог остался один и тот же: меньше `badgeDiameterPt` круга на экране почти
/// нет, и значок стоял бы не «в круге», а посреди карты. Тогда от подсказки
/// видно только выгравированное кольцо, а счёт несёт строка листа «N загадок
/// рядом».
enum HintBadgeLOD {
    enum Level { case none, badge }

    /// Меньше этого круг на экране — точка, и значку не к чему привязаться.
    static let badgeDiameterPt: CGFloat = 60

    static func level(diameterPt: CGFloat) -> Level {
        diameterPt >= badgeDiameterPt ? .badge : .none
    }
}

/// Один «?» размером с ноготь. НИ КРУГА, НИ СТРОКИ ЗДЕСЬ НЕТ.
///
/// До 16 сен круг рисовал `CAShapeLayer` этой вью, в ТОЧКАХ ЭКРАНА, и радиус
/// пересчитывался только на `regionDidChangeAnimated` — то есть когда камера
/// уже встала. Во время щипка круг оставался прежним кружком и потому рос и
/// сжимался относительно карты под ним: владелец увидел это на устройстве
/// («круг становится больше вместе с отдалением — криво и страшно в тумане»).
/// Теперь круг гравируется В РАСТР ТУМАНА (`FogVeilPainter.engrave`), то есть
/// живёт в метрах на земле и едет за картой тем же аффинным преобразованием,
/// что и весь туман: расти ему нечем по построению.
///
/// Строка под значком стояла здесь до 17 сен и ушла тем же приговором, что
/// снял яркость с кольца: подсказка обязана быть заметной ровно настолько,
/// чтобы по ней нажали, — а что именно ищется, отвечает уже карточка
/// (`RiddleHintCard`).
final class RiddleHintView: MKAnnotationView {
    static let reuseID = "RiddleHint"

    /// Диаметр диска в точках экрана.
    static let badgeSide: CGFloat = 22
    /// Непрозрачность всего значка: он метка на тумане, а не кнопка на панели.
    static let badgeAlpha: CGFloat = 0.75

    private let chip = UILabel()

    /// Что показывать на текущем масштабе. Считает карта (диаметр круга в
    /// точках экрана) и ставит сюда — на каждом кадре жеста, три аннотации.
    /// Применяется БЕЗУСЛОВНО, а не только на смену: скрытую аннотацию MapKit
    /// вправе показать сам (пересчёт столкновений, переиспользование вью), и
    /// проверка «значение то же» оставила бы на стране «?», который мы уже
    /// прятали. Три аннотации и три булевых поля на кадр.
    var lod: HintBadgeLOD.Level = .badge {
        didSet { applyLOD() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.badgeSide, height: Self.badgeSide)
        centerOffset = .zero
        // Не контрол MapKit: нажатие ловит один общий распознаватель карты
        // (`Coordinator.handleTap`), который и решает, что открылось. Своя
        // выборка MapKit здесь дала бы второй ответ на тот же тап.
        isEnabled = false
        // Выше подписи региона (`.defaultLow` у `RegionLabelView`): при
        // столкновении MapKit прячет ПРОИГРАВШЕГО, и уступить обязана подпись,
        // а не подсказка — иначе они рисуются друг на друге, как это и было
        // видно на стране. Ниже печати находки (`.required`): найденное
        // сильнее ненайденного.
        displayPriority = .defaultHigh
        // Круглая цель столкновения: у значка круглая форма, и прямоугольник
        // резервировал бы под ним пустые углы.
        collisionMode = .circle
        isAccessibilityElement = true
        accessibilityTraits = .button
        layer.masksToBounds = false
        clipsToBounds = false

        chip.frame = bounds
        chip.textAlignment = .center
        chip.font = .systemFont(ofSize: 13, weight: .heavy)
        chip.layer.cornerRadius = Self.badgeSide / 2
        chip.layer.borderWidth = 1
        chip.layer.masksToBounds = true
        chip.text = "?"
        chip.alpha = Self.badgeAlpha
        addSubview(chip)
        applyPalette()
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    /// Цвета значка — от палитры тумана, а не от темы экрана.
    ///
    /// Диск залит самой мглой: значок обязан читаться как её часть, а не как
    /// плашка поверх карты. Отсюда же и знак вопроса с ободком — светлые на
    /// ночной палитре, тёмные на дневной; взять их у `AppTheme` значило бы
    /// поставить тёмный «?» на тёмную мглу в тот день, когда «Атлас» сменит
    /// полярность.
    private func applyPalette() {
        let dark = FogVeilPainter.palette.isDark
        let ink = dark ? UIColor.white : UIColor(red: 0x1C/255, green: 0x21/255,
                                                 blue: 0x2C/255, alpha: 1)
        chip.backgroundColor = FogVeilPainter.veilColorTop
        chip.textColor = ink
        chip.layer.borderColor = ink.withAlphaComponent(0.45).cgColor
    }

    private func configure() {
        guard let hint = annotation as? RiddleHintAnnotation else { return }
        // Строка на карте не печатается — но VoiceOver её читает: значок «?»
        // без подписи не говорит незрячему ничего вовсе.
        accessibilityLabel = hint.line
        applyPalette()
        applyLOD()
    }

    private func applyLOD() {
        let hidden = lod == .none
        if isHidden != hidden { isHidden = hidden }
        if chip.isHidden != hidden { chip.isHidden = hidden }
    }

    /// Отклик В МОМЕНТ КАСАНИЯ (канон «нажатие обязано отвечать»): диск
    /// приседает и возвращается.
    ///
    /// Пружиной, а не цепочкой анимаций со сном: жест можно передумать, и
    /// приложение не имеет права доигрывать. `PressableCardStyle` сюда не
    /// дотянуться — это `MKAnnotationView`, а не SwiftUI.
    func flashPress() {
        chip.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.chip.transform = .identity
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}
