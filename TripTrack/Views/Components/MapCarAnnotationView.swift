import MapKit
import UIKit

/// Вид машинки на карте: контейнер, внутри которого вращается ОДНА картинка.
///
/// Разделение обязательное, а не декоративное. Всё, что лежит в этом виде
/// рядом с машиной — тень, круг точности, пульс, пилюля паузы — вращаться не
/// имеет права: тень со светом, едущим за курсом, читается как ошибка
/// рендера, а не как объём, а круг точности повернуть вообще нельзя, он
/// круглый. Поэтому курс крутит `car` (и конус — он ПРО курс), а сам вид
/// остаётся неповёрнутым, и заодно его собственный `transform` свободен для
/// пружины появления, которой карта уже пользуется.
///
/// Картинка при повороте НЕ пересобирается: реплей двигает маркер с частотой
/// экрана, и рисовать заново три слоя шестьдесят раз в секунду — это то же
/// самое, что не рисовать вовсе.
///
/// Три вещи меряются в МЕТРАХ КАРТЫ, а не в пунктах экрана, — круг точности,
/// конус курса и порог схлопывания в точку. Пункты соврали бы одинаково во
/// всех трёх случаях: круг точности в пунктах обещает на обзорном зуме
/// точность до квартала, конус в пунктах на нём же накрывает область, а
/// машина в сорок четыре пункта на треке в тысячу километров закрывает сотню
/// и прячет ровно тот маршрут, ради которого экран открыли.
final class MapCarAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "MapCar"

    /// Курс маркера по земле, [0, 360). Экранный угол считается из него и
    /// поворота камеры — см. `CarHeadingPolicy.screenAngle`.
    private(set) var course: Double = 0

    private var state = MapCarMarker.State()
    /// Метров земли в одном пункте экрана. Ноль — карта ещё не сказала.
    private var metersPerPoint: Double = 0
    private var isCollapsed = false

    /// Пульс, круг точности и конус лежат ПОД тенью и машиной: любой из них
    /// поверх превратил бы машину в пятно под цветным стеклом.
    private let pulseLayer = CAShapeLayer()
    private let accuracyLayer = CAShapeLayer()
    private let coneLayer = CAShapeLayer()
    private let shadowLayer = CALayer()
    private let car = UIImageView()
    private let dot = UIImageView()
    private let pausePill = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: MapCarMarker.side, height: MapCarMarker.side)
        // Ничего не обрезаем: круг точности на дворовом зуме в разы больше
        // бокса маркера, и `clipsToBounds` съел бы от него всё, кроме пятачка
        // под машиной.
        clipsToBounds = false

        for shape in [pulseLayer, accuracyLayer, coneLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = UIColor.clear.cgColor
            shape.isHidden = true
            layer.addSublayer(shape)
        }
        accuracyLayer.fillColor = MapCarMarker.accuracyFill.cgColor
        accuracyLayer.strokeColor = MapCarMarker.accuracyStroke.cgColor
        accuracyLayer.lineWidth = 1
        coneLayer.fillColor = MapCarMarker.coneFill.cgColor
        pulseLayer.strokeColor = MapCarMarker.pulseStroke.cgColor
        pulseLayer.lineWidth = 2

        // Тень рисуется ТЕНЬЮ слоя, а не серым овалом: овал без размытия
        // читается как вторая машина под машиной. Свой `shadowPath` рисуется
        // и у слоя без содержимого — содержимое здесь и не нужно.
        shadowLayer.shadowColor = UIColor.black.cgColor
        shadowLayer.shadowOpacity = 0.22
        shadowLayer.shadowRadius = 2
        shadowLayer.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(shadowLayer)

        car.frame = bounds
        car.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        car.contentMode = .scaleAspectFit
        car.isUserInteractionEnabled = false
        addSubview(car)

        dot.contentMode = .center
        dot.isUserInteractionEnabled = false
        dot.isHidden = true
        addSubview(dot)

        pausePill.image = MapCarMarker.pausePill
        pausePill.contentMode = .center
        pausePill.isUserInteractionEnabled = false
        pausePill.isHidden = true
        pausePill.layer.shadowColor = UIColor.black.cgColor
        pausePill.layer.shadowOpacity = 0.18
        pausePill.layer.shadowRadius = 2
        pausePill.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(pausePill)

        canShowCallout = false
        centerOffset = .zero
        // Картинку ставим СРАЗУ, а не ждём первого `setState`: «Без
        // транспорта» — это состояние по умолчанию, и на нём сравнение в
        // `setState` честно скажет «ничего не изменилось», оставив пустой вид.
        refreshImages()
        layoutPieces()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Что показывает маркер

    /// Цвет, круг точности, конус, пульс и настроение — всё разом.
    ///
    /// Сравнение целиком, а не по полю: состояние меняется в час по чайной
    /// ложке, и лишний проход по слоям стоит дешевле, чем пять отдельных
    /// сеттеров, из которых однажды забудут позвать четвёртый.
    func setState(_ new: MapCarMarker.State) {
        guard new != state else { return }
        let moodChanged = new.mood != state.mood || new.colorName != state.colorName
        state = new
        if moodChanged { refreshImages() }
        alpha = state.mood.alpha
        layoutPieces()
        refreshPulse()
    }

    /// Масштаб карты: метров земли в одном пункте экрана.
    ///
    /// Отсюда живут все три «в метрах»: круг точности, конус и решение
    /// схлопнуться в точку.
    func setScale(metersPerPoint: Double) {
        guard metersPerPoint > 0 else { return }
        let collapsed = MapCarMarker.collapsed(
            metersPerPoint: metersPerPoint, wasCollapsed: isCollapsed
        )
        // В реплее камера едет за машиной, и этот метод зовётся на КАЖДЫЙ
        // кадр: широта центра чуть меняется, значит меняется и число метров в
        // пункте. Процент — это меньше половины пикселя на любом из радиусов,
        // то есть перекладывать слои под него незачем.
        let moved = self.metersPerPoint <= 0
            || abs(metersPerPoint - self.metersPerPoint) / self.metersPerPoint > 0.01
        guard moved || collapsed != isCollapsed else { return }
        self.metersPerPoint = metersPerPoint
        isCollapsed = collapsed
        layoutPieces()
        // Схлопнутый маркер не пульсирует: кольцо вокруг точки на обзорном
        // зуме — это круги по всей области, а не «сигнал живой».
        refreshPulse()
    }

    private func refreshImages() {
        car.image = MapCarMarker.image(colorName: state.colorName, mood: state.mood)
        dot.image = MapCarMarker.dot(colorName: state.colorName, mood: state.mood)
    }

    /// Пульс — «сигнал живой», и только на записи: в реплее пульсировать
    /// нечему, там всё уже случилось.
    ///
    /// Повторяющаяся анимация — ровно то, что Reduce Motion просит убрать
    /// (тем же правилом, что и дыхание кандидата в отметки): тогда кольца
    /// нет вовсе, а «живое» говорит сама едущая машина.
    private func refreshPulse() {
        let wanted = state.pulses && !isCollapsed && !UIAccessibility.isReduceMotionEnabled
        guard wanted else {
            pulseLayer.removeAnimation(forKey: "pulse")
            pulseLayer.isHidden = true
            return
        }
        pulseLayer.isHidden = false
        guard pulseLayer.animation(forKey: "pulse") == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 2.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.55
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.9
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulseLayer.add(group, forKey: "pulse")
    }

    /// Раскладывает всё, что не картинка: радиусы в метрах, тень, точка,
    /// пилюля. Внутри одной транзакции с выключенными действиями — иначе
    /// каждый слой поедет к новому радиусу своей четвертьсекундной
    /// анимацией, и на щипке пальцами круг точности отстанет от карты.
    private func layoutPieces() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let centre = CGPoint(x: bounds.midX, y: bounds.midY)

        car.isHidden = isCollapsed
        dot.isHidden = !isCollapsed
        dot.frame = bounds

        // Схлопнутый маркер — это «машина где-то здесь», и обещать ей курс,
        // точность и паузу отдельными значками на обзорном зуме не на чем:
        // конус в сорок пять метров там короче самой точки.
        pausePill.isHidden = state.mood != .paused || isCollapsed
        let pill = MapCarMarker.pausePill.size
        pausePill.frame = CGRect(
            x: centre.x + MapCarMarker.side * 0.30,
            y: centre.y - MapCarMarker.side * 0.30 - pill.height,
            width: pill.width, height: pill.height
        )

        let shadow = isCollapsed ? MapCarMarker.dotDiameter * 0.9 : MapCarMarker.shadowDiameter
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = UIBezierPath(ovalIn: CGRect(
            x: centre.x - shadow / 2, y: centre.y - shadow / 2,
            width: shadow, height: shadow
        )).cgPath

        pulseLayer.frame = bounds
        let ring = MapCarMarker.side * 0.28
        pulseLayer.path = UIBezierPath(ovalIn: CGRect(
            x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2
        )).cgPath

        layoutAccuracy(centre: centre)
        layoutCone(centre: centre)
    }

    /// Круг точности — в метрах карты, поэтому на отдалении он сжимается
    /// вместе с ней.
    ///
    /// Мельче половины маркера не рисуется вовсе: такой круг целиком под
    /// машиной, и показать его значит пообещать точность, которой не видно.
    /// Так же ведёт себя системная синяя точка, и по той же причине.
    private func layoutAccuracy(centre: CGPoint) {
        guard let metres = state.accuracyMeters, metres > 0, metersPerPoint > 0 else {
            accuracyLayer.isHidden = true
            return
        }
        let radius = CGFloat(metres / metersPerPoint)
        guard radius >= MapCarMarker.accuracyMinRadius else {
            accuracyLayer.isHidden = true
            return
        }
        let capped = min(radius, MapCarMarker.accuracyMaxRadius)
        accuracyLayer.isHidden = false
        accuracyLayer.frame = bounds
        accuracyLayer.path = UIBezierPath(ovalIn: CGRect(
            x: centre.x - capped, y: centre.y - capped, width: capped * 2, height: capped * 2
        )).cgPath
    }

    /// Конус неуверенности курса: «еду примерно туда».
    ///
    /// Тоже в метрах — и по той же причине, что круг: конус в пунктах на
    /// обзорном зуме накрыл бы область, а на дворовом сжался бы в ничто ровно
    /// там, где курс и правда шумит.
    ///
    /// Рисуется в СВОЁМ квадрате со стороной в два радиуса и вращается
    /// целиком: слой поворачивается вокруг своего центра, и апекс обязан
    /// стоять именно в нём, иначе конус будет уезжать от машины по дуге.
    private func layoutCone(centre: CGPoint) {
        guard let half = state.coneHalfAngle, half > 0, metersPerPoint > 0, !isCollapsed else {
            coneLayer.isHidden = true
            return
        }
        let radius = CGFloat(MapCarMarker.coneMeters / metersPerPoint)
        guard radius >= MapCarMarker.side * 0.5 else {
            coneLayer.isHidden = true
            return
        }
        coneLayer.isHidden = false
        let side = radius * 2
        // Трансформацию на время перекладки снимаем: `frame` у повёрнутого
        // слоя — это уже описанный прямоугольник, и задать его напрямую
        // значит растянуть конус вкось.
        let spin = coneLayer.affineTransform()
        coneLayer.setAffineTransform(.identity)
        coneLayer.frame = CGRect(
            x: centre.x - radius, y: centre.y - radius, width: side, height: side
        )
        let apex = CGPoint(x: radius, y: radius)
        let path = UIBezierPath()
        path.move(to: apex)
        // Нос картинки смотрит вверх, то есть в −90° в системе координат
        // экрана, — от него и отмеряем половины угла.
        let start = CGFloat((-90 - half) * .pi / 180)
        let end = CGFloat((-90 + half) * .pi / 180)
        path.addArc(withCenter: apex, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        path.close()
        coneLayer.path = path.cgPath
        coneLayer.setAffineTransform(spin)
    }

    // MARK: - Курс

    /// Ставит курс и сразу разворачивает картинку под текущую камеру.
    func apply(course: Double, cameraHeading: Double, animated: Bool = false) {
        self.course = course
        applyScreenAngle(cameraHeading: cameraHeading, animated: animated)
    }

    /// Перерисовать под новый поворот камеры, курс не трогая. Зовётся, когда
    /// карту крутят пальцами или когда камера сама идёт по курсу — без этого
    /// маркер отвязывается от дороги под собой.
    ///
    /// Поворот при Reduce Motion ОСТАЁТСЯ: это информация, а не украшение —
    /// системная стрелка курса тоже не выключается. Убирается только доводка:
    /// угол встаёт сразу.
    func applyScreenAngle(cameraHeading: Double, animated: Bool = false) {
        let angle = CarHeadingPolicy.screenAngle(course: course, cameraHeading: cameraHeading)
        let transform = CGAffineTransform(rotationAngle: CGFloat(angle * .pi / 180))
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            car.transform = transform
            coneLayer.setAffineTransform(transform)
            CATransaction.commit()
            return
        }
        // Прерываемая — с текущего состояния, а не с начала. Человек,
        // передумавший в середине поворота, ничего не доигрывает. Конус едет
        // тем же временем: иначе он отстаёт от носа на четверть секунды и
        // читается как второй, чужой маркер.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        coneLayer.setAffineTransform(transform)
        CATransaction.commit()
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.car.transform = transform
        }
    }

    /// Переиспользованный вид приезжает с чужим поворотом и чужим настроением
    /// — на карте это выглядит как машина, прыгнувшая боком на один кадр.
    override func prepareForReuse() {
        super.prepareForReuse()
        course = 0
        state = MapCarMarker.State()
        // Картинку сбрасываем вместе с состоянием: иначе вид, приехавший из
        // очереди от красной машины, останется красным ровно в том случае,
        // когда новое состояние равно пустому, — `setState` честно скажет
        // «ничего не изменилось».
        alpha = 1
        refreshImages()
        car.transform = .identity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coneLayer.setAffineTransform(.identity)
        CATransaction.commit()
        pulseLayer.removeAnimation(forKey: "pulse")
        pulseLayer.isHidden = true
        layoutPieces()
    }
}

extension MKMapView {
    /// Метров земли в одном пункте экрана.
    ///
    /// Общая мера для всего, что у маркера меряется в метрах: круг точности,
    /// конус курса и порог схлопывания в точку. Считается ровно так же, как в
    /// обработчике касания по маршруту, — другой счёт здесь означал бы, что
    /// палец и маркер живут на разных картах.
    var metersPerScreenPoint: Double {
        guard bounds.width > 0 else { return 0 }
        return visibleMapRect.size.width / Double(bounds.width)
            * MKMetersPerMapPointAtLatitude(centerCoordinate.latitude)
    }
}
