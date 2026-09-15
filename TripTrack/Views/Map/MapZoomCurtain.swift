import UIKit
import MapKit

/// Правило шторы: на зуме она поднимается, на панораме — никогда.
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
/// экран, на котором человек возит пальцем и не видит ничего, а панорама и зум
/// приходят ОДНИМ и тем же колбэком (тот же довод, что у `AutoTripPolicy` и
/// `JourneyEditSheet.startBounds`).
struct MapZoomCurtain {
    /// Насколько должна измениться ширина видимого прямоугольника, чтобы это
    /// считалось зумом. Пятнадцать процентов — примерно палец на полсантиметра
    /// в щипке: меньше бывает дрожанием руки на панораме.
    static let threshold: Double = 0.15

    /// Сколько гаснет штора после того, как камера встала. Четверть секунды —
    /// столько же, сколько MapKit довозит свежие тайлы оверлея; короче — и
    /// из-под шторы снова покажется карта Apple.
    static let fadeDuration: TimeInterval = 0.25

    /// Величина, по которой считается зум, — `visibleMapRect.size.width`, и это
    /// половина решения: при чистом сдвиге камеры она не меняется ВООБЩЕ, в
    /// отличие от `region.span.latitudeDelta`, который на Меркаторе растёт при
    /// движении на север. «Панорама не поднимает штору» здесь — свойство
    /// величины, а не удачно подобранного порога.
    static func shouldRaise(startWidth: Double, currentWidth: Double) -> Bool {
        guard startWidth > 0, currentWidth > 0 else { return false }
        let ratio = currentWidth / startWidth
        return ratio > 1 + threshold || ratio < 1 / (1 + threshold)
    }

    private var startWidth: Double?
    /// Стоит ли штора прямо сейчас.
    private(set) var isUp = false
    /// Поколение жеста: затухание, начатое прошлым, не имеет права досчитаться
    /// поверх нового.
    private(set) var generation = 0

    /// Камера начала меняться — запомнить, от чего считать.
    mutating func willChange(width: Double) {
        startWidth = width
        generation += 1
    }

    /// Камера меняется. `true` — поднять штору ПРЯМО СЕЙЧАС и без анимации:
    /// карта под ней уже видна.
    mutating func changing(width: Double) -> Bool {
        guard !isUp, let start = startWidth,
              Self.shouldRaise(startWidth: start, currentWidth: width) else { return false }
        isUp = true
        return true
    }

    /// Камера встала. Не `nil` — гасить, и это поколение затухания.
    mutating func didChange(width: Double) -> Int? {
        startWidth = width
        guard isUp else { return nil }
        isUp = false
        return generation
    }

    /// Актуально ли ещё затухание этого поколения — или его обогнал новый жест.
    func fadeIsCurrent(_ fadeGeneration: Int) -> Bool { fadeGeneration == generation }
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

    /// Ставит штору НАД картой. `host` — контейнер, если он есть («Атлас»
    /// живёт в своём вью-контроллере); без него шторой становится верхняя
    /// сабвью самой карты — SwiftUI-хром лежит выше представимого и остаётся
    /// сверху в обоих случаях.
    func install(over map: MKMapView, in host: UIView? = nil) {
        let parent = host ?? map
        view.frame = parent.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(view)
    }

    func willChange(_ map: MKMapView) {
        policy.willChange(width: map.visibleMapRect.size.width)
    }

    /// Поднимать штору есть смысл только там, где лежит вуаль: без неё под
    /// картой Apple ничего не прячется, и гасить экран не за чем. Заодно это
    /// сама собой выключает штору на «Атласе» с отключённым туманом.
    func changing(_ map: MKMapView) {
        guard map.overlays.contains(where: { $0 is FogVeilOverlay }) else { return }
        guard policy.changing(width: map.visibleMapRect.size.width) else { return }
        view.superview?.bringSubviewToFront(view)
        view.layer.removeAllAnimations()
        view.alpha = 1
    }

    func didChange(_ map: MKMapView) {
        guard policy.didChange(width: map.visibleMapRect.size.width) != nil else { return }
        UIView.animate(
            withDuration: MapZoomCurtain.fadeDuration, delay: 0,
            options: [.beginFromCurrentState]
        ) { [view] in
            view.alpha = 0
        }
    }
}
