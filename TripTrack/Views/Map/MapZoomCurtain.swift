import UIKit
import MapKit

/// Правило шторы: на зуме она поднимается, на панораме и на ПОВОРОТЕ — никогда.
///
/// Зачем штора вообще. `MKOverlayRenderer` рисует тайлы ПО ЗАПРОСУ и только для
/// той области, которая нужна сейчас; у базовой карты Apple есть многоуровневый
/// кэш плиток, и площадь, приехавшая на экран после щипка наружу, у неё почти
/// всегда уже есть. У вуали растягивать нечего — этой области не рисовали ни на
/// каком масштабе, — поэтому между «новая площадь на экране» и «MapKit поставил
/// наши тайлы в очередь» НАШЕЙ отрисовки не существует вовсе, и там видна живая
/// карта Apple, которую туман обязан прятать. Удешевление тайлов эту дыру не
/// закрывает (спайк 15 сен: вуаль, выродженная в одну `fill`, отстаёт ровно так
/// же) — закрывает только непрозрачная вью поверх карты.
///
/// Цена, записанная словами: **на время изменения зума с экрана пропадают
/// подписи регионов, точки городов, пины и логотип Apple вместе с картой.** Все
/// они сабвью `MKMapView`, а вставить свой слой между плитками и контейнером
/// аннотаций публичного API у MapKit нет. В покое они видны — ровно как под
/// непрозрачной вуалью, которая уже принята.
///
/// Правило живёт отдельным типом и под тестом, потому что ошибка здесь — это
/// экран, на котором человек возит пальцем и не видит ничего, а панорама, зум и
/// поворот приходят ОДНИМ и тем же колбэком (тот же довод, что у
/// `AutoTripPolicy` и `JourneyEditSheet.startBounds`).
struct MapZoomCurtain {
    /// Насколько должна измениться высота камеры, чтобы это считалось зумом.
    /// Пятнадцать процентов — примерно палец на полсантиметра в щипке: меньше
    /// бывает дрожанием руки на панораме.
    static let threshold: Double = 0.15

    /// Сколько гаснет штора после того, как камера встала. Четверть секунды —
    /// столько же, сколько MapKit довозит свежие тайлы оверлея; короче — и
    /// из-под шторы снова покажется карта Apple.
    static let fadeDuration: TimeInterval = 0.25

    /// Величина, по которой считается зум, — `camera.centerCoordinateDistance`,
    /// высота камеры над центром, и это половина решения: она не меняется ни
    /// при сдвиге, ни при ПОВОРОТЕ. «Панорама и поворот не поднимают штору»
    /// здесь — свойство величины, а не удачно подобранного порога.
    ///
    /// Так было не сразу: мерили `visibleMapRect.size.width`, а это
    /// axis-aligned коробка вокруг видимой области. При сдвиге она и правда
    /// стоит на месте, но при повороте камеры растёт тем сильнее, чем длиннее
    /// экран: на телефоне 9:19.5 поворот на 90° меняет её примерно вдвое, то
    /// есть порог перешагивался уже на 15–20°. А на экране записи в режиме «по
    /// курсу» карту крутит сама система — каждый поворот на перекрёстке гасил
    /// бы карту, на которую человек смотрит из-за руля.
    static func shouldRaise(startDistance: Double, currentDistance: Double) -> Bool {
        guard startDistance > 0, currentDistance > 0 else { return false }
        let ratio = currentDistance / startDistance
        return ratio > 1 + threshold || ratio < 1 / (1 + threshold)
    }

    /// Второй рубеж для экрана записи: в режиме «по курсу» камерой командует
    /// система, и любое её движение здесь — не жест человека. Высота камеры
    /// при повороте не меняется, так что первый рубеж уже закрывает вопрос;
    /// этот стоит потому, что цена ошибки — тёмный прямоугольник вместо карты
    /// у водителя, а не лишний кадр тумана.
    static func suppresses(trackingMode: MKUserTrackingMode) -> Bool {
        trackingMode == .followWithHeading
    }

    private var startDistance: Double?
    /// Стоит ли штора прямо сейчас.
    private(set) var isUp = false

    /// Камера начала меняться — запомнить, от чего считать.
    mutating func willChange(distance: Double) {
        startDistance = distance
    }

    /// Камера меняется. `true` — поднять штору ПРЯМО СЕЙЧАС и без анимации:
    /// карта под ней уже видна.
    mutating func changing(distance: Double) -> Bool {
        guard !isUp, let start = startDistance,
              Self.shouldRaise(startDistance: start, currentDistance: distance) else { return false }
        isUp = true
        return true
    }

    /// Камера встала. `true` — гасить.
    ///
    /// Отменять затухание, начатое прошлым жестом, отдельным поколением не
    /// нужно: подъём шторы снимает анимации сам (`removeAllAnimations`) и
    /// ставит альфу в единицу. Поколение здесь стояло, не имея ни одного
    /// читателя в продакшене, — API, который держит только тест, завтра
    /// прочитают как работающую защиту.
    mutating func didChange(distance: Double) -> Bool {
        startDistance = distance
        guard isUp else { return false }
        isUp = false
        return true
    }
}

/// Сама штора: непрозрачная вью цвета вуали плюс три колбэка карты.
///
/// Одна на все карты с туманом («Атлас», экран поездки, экран записи): дефект у
/// них один и тот же, и разъехаться правилам подъёма нельзя.
final class MapCurtain {
    let view = UIView()
    private var policy = MapZoomCurtain()

    init() {
        view.backgroundColor = FogVeilPainter.veilColorBottom
        view.isUserInteractionEnabled = false
        view.alpha = 0
    }

    /// Ставит штору НАД картой — но только если этой карте она может
    /// понадобиться: туман на ней есть, и двигает её человек. Условие живёт
    /// ЗДЕСЬ, а не у трёх вызывающих: три копии одного правила разъезжаются.
    ///
    /// `host` — контейнер, если он есть («Атлас» живёт в своём
    /// вью-контроллере); без него шторой становится верхняя сабвью самой
    /// карты — SwiftUI-хром лежит выше представимого и остаётся сверху в обоих
    /// случаях.
    func install(
        over map: MKMapView, in host: UIView? = nil,
        showsFog: Bool = true, isInteractive: Bool = true
    ) {
        guard showsFog, isInteractive else { return }
        let parent = host ?? map
        view.frame = parent.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(view)
    }

    func willChange(_ map: MKMapView) {
        policy.willChange(distance: map.camera.centerCoordinateDistance)
    }

    /// Поднимать штору есть смысл только там, где лежит вуаль: без неё под
    /// картой Apple ничего не прячется, и гасить экран не за чем. Заодно это
    /// сама собой выключает штору на «Атласе» с отключённым туманом.
    func changing(_ map: MKMapView) {
        guard !MapZoomCurtain.suppresses(trackingMode: map.userTrackingMode) else { return }
        guard map.overlays.contains(where: { $0 is FogVeilOverlay }) else { return }
        guard policy.changing(distance: map.camera.centerCoordinateDistance) else { return }
        view.superview?.bringSubviewToFront(view)
        view.layer.removeAllAnimations()
        view.alpha = 1
    }

    func didChange(_ map: MKMapView) {
        guard policy.didChange(distance: map.camera.centerCoordinateDistance) else { return }
        UIView.animate(
            withDuration: MapZoomCurtain.fadeDuration, delay: 0,
            options: [.beginFromCurrentState]
        ) { [view] in
            view.alpha = 0
        }
    }
}
