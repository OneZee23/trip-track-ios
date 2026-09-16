import Foundation
import CoreLocation

/// Снимок, нажатый на карте, в том виде, в каком его показывает карточка
/// предпросмотра.
///
/// Нажатие по булавке открывало просмотрщик сразу и во весь экран — и это
/// был второй тяжёлый заход подряд: сначала выезжала карта, потом поверх неё
/// разворачивалась картинка. Между ними встала карточка в том же слоте и той
/// же пружиной, что карточка отметки (0.6.5): миниатюра, «сколько до сюда» и
/// номер в стопке. Отсюда до полного экрана — один тап и кроссфейд.
///
/// Чистый тип, считается вне `body`: в нём стопка соседних булавок, а это
/// проход по всем снимкам поездки.
struct MapPhotoPreview: Equatable, Identifiable {
    let photoId: UUID
    /// Номер в стопке, с единицы.
    let index: Int
    /// Сколько всего снимков в этой стопке.
    let total: Int
    /// «1 ч 19 мин · 106 км» — если кадр встал на трек. `nil` — не встал, и
    /// врать нечем.
    let reading: String?
    /// Файл на диске: по нему карточка берёт ступень 600 pt.
    let filename: String?

    var id: UUID { photoId }

    /// Насколько близко булавки считаются ОДНОЙ стопкой, в метрах.
    ///
    /// Стопка — это то, что палец накрывает целиком: три кадра с одной
    /// смотровой площадки стоят на карте одной кучкой, и «2 из 3» отвечает
    /// на вопрос «а что ещё я тут снял». Снимки с разных концов маршрута в
    /// одну стопку не попадают — им этот номер ничего не сказал бы.
    static let stackRadius: Double = 50

    /// Собрать карточку для нажатой булавки.
    static func build(photoId: UUID, pins: [PhotoPin]) -> MapPhotoPreview? {
        guard let tapped = pins.first(where: { $0.id == photoId }) else { return nil }
        let stack = stack(around: tapped, in: pins)
        let index = (stack.firstIndex(where: { $0.id == photoId }) ?? 0) + 1
        return MapPhotoPreview(
            photoId: photoId,
            index: index,
            total: stack.count,
            reading: tapped.reading,
            filename: tapped.filename
        )
    }

    /// Булавки, стоящие с этой в одной кучке, в исходном порядке.
    static func stack(around pin: PhotoPin, in pins: [PhotoPin]) -> [PhotoPin] {
        let centre = CLLocation(latitude: pin.latitude, longitude: pin.longitude)
        return pins.filter {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: centre) <= stackRadius
        }
    }

    /// «2 из 5». Один снимок в стопке — строки нет вовсе: «1 из 1» это не
    /// ответ, а шум.
    func counterText(_ lang: LanguageManager.Language) -> String? {
        guard total > 1 else { return nil }
        return AppStrings.outOf(l: lang, have: index, all: total)
    }
}
