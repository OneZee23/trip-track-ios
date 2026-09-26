import MapKit

/// Название региона поверх тумана «Атласа».
///
/// Координата — из БАНДЛА (`RegionAtlas.Region.center`), не из открытой части
/// слоя: имя обязано стоять в географическом центре края, а не гулять вслед
/// за тем, куда именно в этот раз проехала машина.
///
/// Только регионы: подписи стран и их контуры на «Атласе» убраны 17 сентября
/// (контур у Японии и Филиппин был заметно смещён на мировом зуме, а
/// геополитика на карте нам не нужна).
///
/// Заглавные буквы и строка километров приходят ГОТОВЫМИ (`RegionLabelModel`
/// их собирает) — у аннотации нет языка, его знает карта, которая её строит;
/// тот же приём, что у `SealAnnotation.accessibilityText`.
final class RegionLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    /// ISO 3166-2 региона (`"RU-KDA"`) — не путать с `MKAnnotation.title`,
    /// который несёт уже локализованное имя.
    let labelId: String
    let name: String
    /// «N км» — список уже отфильтрован по открытым километрам, поэтому
    /// подпись есть только у посещённого региона.
    let kmLine: String?
    /// Bbox региона из бандла — по нему `RegionLabelLOD` решает, показывать
    /// подпись на этом масштабе или нет.
    let bounds: GeoBounds

    var title: String? { name }

    init(
        labelId: String, coordinate: CLLocationCoordinate2D,
        name: String, kmLine: String?, bounds: GeoBounds
    ) {
        self.labelId = labelId
        self.coordinate = coordinate
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
    /// весь туман (`FogVeilRenderer`) — `zoomScale` и есть множитель «точка
    /// карты → точка экрана», второго счёта заводить незачем.
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

/// Собирает `RegionLabelAnnotation` из атласа и слоя открытого — чистой
/// функцией, без обращения к `RegionAtlas.shared`, чтобы тест кормил её
/// синтетическими регионами напрямую.
///
/// Стран здесь больше нет: их подписи и контуры убраны 17 сентября вместе с
/// границами — геополитика на карте нам не нужна, а контур у Японии и
/// Филиппин к тому же был заметно смещён на мировом зуме.
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
                name: region.localizedName(language).uppercased(language),
                kmLine: Measure.distance(km: km, unit: unit, lang: language),
                bounds: region.bounds
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

    /// Тот же тёплый светлый серый, которым раньше на «Атласе» рисовались
    /// границы стран — подпись региона и он обязаны читаться как один язык.
    private static var warmColor: UIColor { FogVeilPainter.borderColor }
    /// Список уже отфильтрован по открытым километрам, поэтому подпись у
    /// региона всегда «посещённая» яркость.
    private static let brightAlpha: CGFloat = 0.85

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

    func refreshPalette() { configure() }

    private func configure() {
        guard let region = annotation as? RegionLabelAnnotation else { return }
        // Под светлой дымкой тёплый светлый текст исчезает — там подпись
        // тёмная (#1E2230), а обводка, наоборот, светлая.
        let base = FogVeilPainter.palette.isDark ? Self.warmColor : Self.darkText
        let color = base.withAlphaComponent(Self.brightAlpha)
        for label in [nameLabel, kmLabel] {
            label.layer.shadowColor = Self.haloColor.cgColor
        }

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
