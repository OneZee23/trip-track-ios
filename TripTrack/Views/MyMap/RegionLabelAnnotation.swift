import MapKit

/// Название региона или страны поверх тумана «Атласа».
///
/// Координата — из БАНДЛА (`RegionAtlas.Region.center` / `MapCountry.center`),
/// не из открытой части слоя: имя обязано стоять в географическом центре
/// края, а не гулять вслед за тем, куда именно в этот раз проехала машина.
///
/// Заглавные буквы и строка километров приходят ГОТОВЫМИ (`RegionLabelModel`
/// их собирает) — у аннотации нет языка, его знает карта, которая её строит;
/// тот же приём, что у `SealAnnotation.accessibilityText`.
final class RegionLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    /// ISO 3166-2 у региона (`"RU-KDA"`), alpha-2 у страны (`"RU"`) — не
    /// путать с `MKAnnotation.title`, который несёт уже локализованное имя.
    let labelId: String
    let isCountry: Bool
    /// У региона всегда `true` — список уже отфильтрован по открытым
    /// километрам. У страны решает яркость подписи (`RegionLabelView`).
    let isVisited: Bool
    let name: String
    /// «N км» — только у посещённого региона. У страны всегда `nil`: сумма
    /// открытого по её регионам нигде не хранится, а считать её заново здесь
    /// значило бы завести ВТОРОЙ счёт рядом с `RevealedLayer.regionKm`.
    let kmLine: String?
    /// Bbox региона/страны из бандла — по нему `RegionLabelLOD` решает,
    /// показывать подпись на этом масштабе или нет.
    let bounds: GeoBounds

    var title: String? { name }

    init(
        labelId: String, coordinate: CLLocationCoordinate2D, isCountry: Bool, isVisited: Bool,
        name: String, kmLine: String?, bounds: GeoBounds
    ) {
        self.labelId = labelId
        self.coordinate = coordinate
        self.isCountry = isCountry
        self.isVisited = isVisited
        self.name = name
        self.kmLine = kmLine
        self.bounds = bounds
        super.init()
    }
}

// MARK: - Геометрия

extension GeoBounds {
    /// Меньшая сторона bbox на экране, в точках, на данном масштабе.
    ///
    /// Считается в координатах `MKMapPoint`, теми же, в которых уже живёт
    /// весь туман (`RegionPathIndex`, `FogVeilRenderer`) — `zoomScale` и есть
    /// множитель «точка карты → точка экрана», второго счёта заводить незачем.
    /// Меркатор не линеен, но для bbox края (не полушария) плоская погрешность
    /// ничтожна рядом с порогом в 140 pt.
    func minSidePt(zoomScale: MKZoomScale) -> CGFloat {
        let sw = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: minLon))
        let ne = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
        let width = abs(ne.x - sw.x)
        let height = abs(ne.y - sw.y)
        return CGFloat(min(width, height)) * CGFloat(zoomScale)
    }
}

// MARK: - Модель

/// Собирает `RegionLabelAnnotation` из атласа и слоя открытого — чистыми
/// функциями, без обращения к `RegionAtlas.shared`, чтобы тест кормил их
/// синтетическими регионами и странами напрямую.
enum RegionLabelModel {
    /// Только регионы, где что-то открыто (`visitedRegionIds`) — тот же
    /// набор, что красит заливку (`FogVeilOverlay.visitedRegions`), а не
    /// второй, независимо посчитанный.
    static func regionLabels(
        regions: [RegionAtlas.Region],
        revealed: RevealedLayer,
        visitedRegionIds: Set<String>,
        unit: DistanceUnit,
        language: LanguageManager.Language
    ) -> [RegionLabelAnnotation] {
        regions.compactMap { region in
            guard visitedRegionIds.contains(region.id) else { return nil }
            let km = revealed.openedKm(regionId: region.id)
            return RegionLabelAnnotation(
                labelId: region.id,
                coordinate: region.center,
                isCountry: false,
                isVisited: true,
                name: region.localizedName(language).uppercased(language),
                kmLine: Measure.distance(km: km, unit: unit, lang: language),
                bounds: region.bounds
            )
        }
    }

    /// Все страны атласа — «страны у всех при мировом масштабе»; посещённые
    /// решает `visitedCountryCodes`, выведенный из ТОГО ЖЕ набора id регионов,
    /// что и `regionLabels` выше.
    static func countryLabels(
        countries: [RegionAtlas.MapCountry],
        visitedCountryCodes: Set<String>,
        language: LanguageManager.Language
    ) -> [RegionLabelAnnotation] {
        countries.map { country in
            RegionLabelAnnotation(
                labelId: country.id,
                coordinate: country.center,
                isCountry: true,
                isVisited: visitedCountryCodes.contains(country.id),
                name: country.localizedName(language).uppercased(language),
                kmLine: nil,
                bounds: country.bounds
            )
        }
    }
}

// MARK: - Вью

/// Капитель на тумане: разрядка, тёплый светлый цвет, тень в 1 pt. Не
/// контрол — тап обязан дойти до дороги под подписью (правило «не
/// притворяемся», CLAUDE.md).
final class RegionLabelView: MKAnnotationView {
    static let reuseID = "RegionLabel"

    /// Тот же тёплый светлый серый, которым в `FogVeilPainter` обведены
    /// границы регионов и стран — подпись и линия обязаны читаться как один
    /// язык, а не как два разных слоя, положенных друг на друга.
    private static let warmColor = FogVeilPainter.borderColor
    /// Посещённый регион (всегда) и посещённая страна читаются на треть
    /// ярче непосещённой — той на мировом зуме ещё только предстоит стать
    /// целью, а не памятью.
    private static let brightAlpha: CGFloat = 0.85
    private static let dimAlpha: CGFloat = 0.4

    /// Тёмный ореол вокруг букв. Подпись лежит и на тумане, и на СВЕТЛОЙ
    /// карте Apple внутри коридора (с фикс-волны 2 «Атлас» дневной), а
    /// светлые буквы на светлой земле не читаются никак. Обводка решает это
    /// на обоих грунтах сразу, чего одна тень не делает.
    ///
    /// `strokeWidth` ОТРИЦАТЕЛЬНЫЙ: положительный в TextKit означает «только
    /// контур, без заливки», то есть подпись стала бы полой.
    static let darkText = UIColor(red: 0x1E/255, green: 0x22/255, blue: 0x30/255, alpha: 1)
    static let darkHalo = UIColor(red: 0x1E/255, green: 0x22/255, blue: 0x30/255, alpha: 0.8)
    static let lightHalo = UIColor(white: 1, alpha: 0.85)
    /// Обводка идёт ПРОТИВ мглы: под тёмной она тёмная, под светлой светлая.
    /// Подпись лежит и на мгле, и на настоящей карте внутри коридора, и
    /// читаться обязана на обеих.
    static var haloColor: UIColor {
        FogVeilPainter.palette.isDark ? darkHalo : lightHalo
    }
    static let haloWidth: CGFloat = -2.0

    private let nameLabel = UILabel()
    private let kmLabel = UILabel()
    private let stack = UIStackView()

    /// Видна ли подпись на текущем масштабе — считает карта
    /// (`RegionLabelLOD`) и ставит сюда на каждом кадре жеста, как `lod` у
    /// `RiddleHintView`. Применяется БЕЗУСЛОВНО: MapKit вправе сам показать
    /// скрытую аннотацию заново при пересчёте столкновений.
    var visible: Bool = true {
        didSet { isHidden = !visible }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isEnabled = false
        // Печати и подсказки важнее подписей — те стоят на `.defaultHigh`/
        // `.required`, подпись уступает им при столкновении.
        displayPriority = .defaultLow
        collisionMode = .rectangle
        // Составную строку (`configure()` ниже) читает VoiceOver ОДНИМ
        // элементом — тот же приём, что у `SealAnnotation`/`RiddleHintView`.
        // Без этого `nameLabel`/`kmLabel` остаются accessibility-элементами
        // каждый сам по себе, и ротор зачитывает имя и километры отдельно —
        // а `accessibilityLabel` ниже просто не читается никогда.
        isAccessibilityElement = true

        nameLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        nameLabel.textAlignment = .center
        kmLabel.font = .systemFont(ofSize: 9, weight: .medium)
        kmLabel.textAlignment = .center

        for label in [nameLabel, kmLabel] {
            label.layer.shadowColor = Self.haloColor.cgColor
            label.layer.shadowOpacity = 0.85
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = .zero
        }

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(kmLabel)
        addSubview(stack)
        configure()
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    private func configure() {
        guard let region = annotation as? RegionLabelAnnotation else { return }
        // Под светлой дымкой тёплый светлый текст исчезает — там подпись
        // тёмная (#1E2230), а обводка, наоборот, светлая.
        let base = FogVeilPainter.palette.isDark ? Self.warmColor : Self.darkText
        let color = base.withAlphaComponent(region.isVisited ? Self.brightAlpha : Self.dimAlpha)

        // Разрядка 0.08 em: капитель без нее читается сплошным пятном,
        // разряженная — гравюрой. Заглавные буквы приходят готовыми в
        // `region.name` (языка у аннотации нет).
        nameLabel.attributedText = NSAttributedString(
            string: region.name,
            attributes: [.kern: nameLabel.font.pointSize * 0.08, .foregroundColor: color,
                         .strokeColor: Self.haloColor, .strokeWidth: Self.haloWidth]
        )
        nameLabel.sizeToFit()

        if let kmLine = region.kmLine {
            kmLabel.attributedText = NSAttributedString(
                string: kmLine,
                attributes: [.kern: kmLabel.font.pointSize * 0.08, .foregroundColor: color,
                             .strokeColor: Self.haloColor, .strokeWidth: Self.haloWidth]
            )
            kmLabel.isHidden = false
            kmLabel.sizeToFit()
        } else {
            kmLabel.isHidden = true
        }

        stack.layoutIfNeeded()
        let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        frame = CGRect(origin: .zero, size: size)
        stack.frame = bounds
        accessibilityLabel = [region.name, region.kmLine].compactMap { $0 }.joined(separator: ", ")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}
