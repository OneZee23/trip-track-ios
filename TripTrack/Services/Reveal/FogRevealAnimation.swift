import MapKit

/// Прорезь, которая растёт у машины на экране записи: «туман выгорает по
/// новому пути».
///
/// Чистыми функциями нарочно. До 0.7.0 та же анимация жила внутри
/// `FogOverlay.updateAnimationProgress` вперемешку со списком центров, и
/// проверить её можно было только глазами на телефоне в движении — то есть
/// никогда. Здесь три величины, и каждая проверяется тестом: сколько прошло,
/// сколько раскрыто и какой кусок карты из-за этого пора перерисовать.
enum FogRevealAnimation {
    /// Сколько растёт прорезь. Ровно столько же, сколько росла до 0.7.0, —
    /// число уже прожито людьми, менять его этой версии незачем.
    static let duration: Double = 0.7

    /// Насколько раскрыт туман через `elapsed` секунд после начала.
    ///
    /// Зажато в 0…1 с обоих концов: отрицательное время приходит от часов,
    /// переставленных назад посреди поездки, а не от ошибки счёта, и прорезь
    /// отрицательного радиуса рендерер молча пропустил бы — вместе со всем
    /// кадром.
    ///
    /// `reduceMotion` даёт единицу СРАЗУ: человек, попросивший систему не
    /// двигать картинку, должен получить открытое место, а не отказ от него.
    static func progress(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        guard duration > 0 else { return 1 }
        let t = min(1, max(0, elapsed / duration))
        // Ease-out cubic — та же кривая, что была у прежней анимации.
        return 1 - pow(1 - t, 3)
    }

    /// Анимация кончилась (или не начиналась).
    static func isDone(elapsed: TimeInterval, reduceMotion: Bool) -> Bool {
        reduceMotion || elapsed >= duration
    }

    /// Какой кусок карты просить перерисовать.
    ///
    /// НЕ весь мир: `setNeedsDisplay()` без прямоугольника заставляет MapKit
    /// пересобрать каждый видимый тайл вуали шестьдесят раз в секунду, а вуаль
    /// накрывает весь мир по определению. Коробка считается по ПОЛНОМУ радиусу,
    /// а не по текущему: иначе последний кадр оставлял бы за собой кольцо уже
    /// стёртого тумана, которое никто не попросил перерисовать.
    static func rect(around coordinate: CLLocationCoordinate2D) -> MKMapRect {
        let metre = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        // Полтора радиуса: мягкий край прорези гаснет не ровно на границе.
        let radius = FogVeilRenderer.revealMetres * metre * 1.5
        let centre = MKMapPoint(coordinate)
        return MKMapRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2
        )
    }
}
