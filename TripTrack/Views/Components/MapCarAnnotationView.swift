import MapKit
import UIKit

/// Вид машинки на карте: контейнер, внутри которого вращается ОДНА картинка.
///
/// Разделение обязательное, а не декоративное. Всё, что положат в этот вид
/// рядом с машиной — тень, подложка, круг точности, пилюля паузы — вращаться
/// не имеет права: тень со светом, едущим за курсом, читается как ошибка
/// рендера, а не как объём. Поэтому курс крутит `car`, а сам вид остаётся
/// неповёрнутым — и заодно его собственный `transform` свободен для пружины
/// появления, которой карта уже пользуется.
///
/// Картинка при повороте НЕ пересобирается: реплей двигает маркер с частотой
/// экрана, и рисовать заново три слоя шестьдесят раз в секунду — это то же
/// самое, что не рисовать вовсе.
final class MapCarAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "MapCar"

    /// Курс маркера по земле, [0, 360). Экранный угол считается из него и
    /// поворота камеры — см. `CarHeadingPolicy.screenAngle`.
    private(set) var course: Double = 0

    private let car = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: MapCarMarker.side, height: MapCarMarker.side)
        car.frame = bounds
        car.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        car.contentMode = .scaleAspectFit
        car.isUserInteractionEnabled = false
        addSubview(car)
        canShowCallout = false
        centerOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCar(_ image: UIImage?) {
        car.image = image
    }

    /// Ставит курс и сразу разворачивает картинку под текущую камеру.
    func apply(course: Double, cameraHeading: Double, animated: Bool = false) {
        self.course = course
        applyScreenAngle(cameraHeading: cameraHeading, animated: animated)
    }

    /// Перерисовать под новый поворот камеры, курс не трогая. Зовётся, когда
    /// карту крутят пальцами или когда камера сама идёт по курсу — без этого
    /// маркер отвязывается от дороги под собой.
    func applyScreenAngle(cameraHeading: Double, animated: Bool = false) {
        let angle = CarHeadingPolicy.screenAngle(course: course, cameraHeading: cameraHeading)
        let transform = CGAffineTransform(rotationAngle: CGFloat(angle * .pi / 180))
        guard animated else {
            car.transform = transform
            return
        }
        // Прерываемая — с текущего состояния, а не с начала. Человек,
        // передумавший в середине поворота, ничего не доигрывает.
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.car.transform = transform
        }
    }

    /// Переиспользованный вид приезжает с чужим поворотом — на карте это
    /// выглядит как машина, прыгнувшая боком на один кадр.
    override func prepareForReuse() {
        super.prepareForReuse()
        course = 0
        car.transform = .identity
    }
}
