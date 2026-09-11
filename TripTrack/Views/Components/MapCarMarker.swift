import UIKit
import CoreLocation

/// Машинка, которая едет по карте: собирается из трёх слоёв в цвет из гаража.
///
/// Один вид сверху вместо прежнего вида сбоку — и это не про вкус. Боковой
/// спрайт умел ровно два состояния, «влево» и «вправо», потому что в него
/// зашита перспектива: повернуть его на курс нельзя в принципе, на север он
/// вставал бы на нос. Вид сверху — единственная проекция, которой поворот
/// плоской карты ничего не ломает.
///
/// Цвет красит КОД, а не художник: девять готовых картинок на девять цветов
/// гаража — это девять чуть разных силуэтов, а разный силуэт при повороте
/// читается как виляние вокруг оси.
///
/// Слои (512×512, центры совпадают до пикселя):
/// - `map_car_body` — площадь краски, заливается цветом машины;
/// - `map_car_shade` — борта и задняя кромка, тем же цветом × 0.78;
/// - `map_car_ink` — контур, стёкла, фары, фонари, резина и белый ореол
///   снаружи силуэта. Не красится НИКОГДА: ореол несёт контраст с тёмной
///   картой, и покрасить его значит потерять машину на ночной теме.
///
/// Состояния — тень, круг точности, конус курса, пульс, пауза, «нет сигнала»,
/// точка на мелком зуме — рисует КОД, ассетов на них нет и не будет. Ни одно
/// из них не меняет форму машины, а тень, запечённая в картинку, на южном
/// курсе оказалась бы НАД машиной и свет поехал бы вместе с курсом.
enum MapCarMarker {

    /// Сторона бокса маркера. Одна на реплей и на живую запись: до 0.6.7 они
    /// разъезжались на 40 и 44 pt, то есть одна и та же машина была разного
    /// размера на двух экранах.
    static let side: CGFloat = 44

    // MARK: - Состояния

    /// Что случилось с ЗАПИСЬЮ, а не с машиной.
    ///
    /// Форму не меняет ни одно из трёх — меняется только краска, и это
    /// читается краем глаза, не отнимая у карты ни пункта площади.
    enum Mood: String, Equatable {
        /// Пишем (или смотрим реплей): краска в полную силу.
        case normal
        /// Пауза. Краска почти уходит, но машина остаётся собой — человек
        /// остановился нарочно, и запись его ждёт.
        case paused
        /// Сигнала нет. Цвета нет вовсе, и маркер наполовину прозрачен: «я не
        /// знаю, где ты сейчас» — сказанное без слов и без баннера.
        case lost

        /// Во сколько раз гасится насыщенность краски.
        var saturation: CGFloat {
            switch self {
            case .normal: return 1
            case .paused: return 0.35
            case .lost: return 0
            }
        }

        /// Прозрачность маркера целиком, вместе с тенью: полупрозрачная
        /// машина с плотной тенью выглядела бы как ошибка отрисовки.
        var alpha: CGFloat {
            switch self {
            case .normal, .paused: return 1
            case .lost: return 0.55
            }
        }
    }

    /// Всё, что маркер показывает КРОМЕ курса и масштаба.
    ///
    /// Курс идёт отдельно, потому что приходит шестьдесят раз в секунду;
    /// состояние меняется в час по чайной ложке, и сравнение целиком здесь
    /// дешевле, чем пересборка слоёв на каждом кадре.
    struct State: Equatable {
        /// Имя цвета из гаража. `nil` — «Без транспорта», законный выбор.
        var colorName: String?
        /// Радиус круга точности В МЕТРАХ. `nil` — круга нет.
        ///
        /// Метры, а не пункты: на отдалении круг обязан сжиматься вместе с
        /// картой, иначе он перестаёт быть про точность и становится
        /// украшением. В реплее круга нет вовсе — там точность это свойство
        /// прошлой записи, а не текущей секунды.
        var accuracyMeters: Double?
        /// Полуугол конуса неуверенности курса, градусы. `nil` — курсу верим.
        var coneHalfAngle: Double?
        /// Пульс «сигнал живой». Только запись: в реплее пульсировать нечему,
        /// там всё уже случилось.
        var pulses: Bool = false
        var mood: Mood = .normal
    }

    // MARK: - Схлопывание на мелком зуме

    /// Выше этого масштаба маркер — точка с обводкой, а не машина.
    ///
    /// Меряется в МЕТРАХ НА ПУНКТ экрана, а не в уровнях зума: уровень зума
    /// зависит от широты, и один и тот же «зум 9» в Мурманске и в Сочи
    /// показывает разное количество земли. Двадцать четыре метра на пункт —
    /// это километр земли под сорока четырьмя пунктами маркера. Дальше он
    /// показывает не машину, а закрывает дорогу, ради которой экран открыли:
    /// на треке в тысячу километров тот же спрайт накрывает сотню.
    static let collapseMetersPerPoint: Double = 24

    /// Обратно машина возвращается РАНЬШЕ, чем ушла.
    ///
    /// Разрыв нужен не для красоты: щипок пальцами меняет масштаб непрерывно,
    /// и на самой границе без гистерезиса маркер моргал бы точкой несколько
    /// раз за жест.
    static let expandMetersPerPoint: Double = 18

    /// Схлопнут ли маркер при таком масштабе. Чистая функция: гистерезис —
    /// ровно то место, где «на глаз» уже не проверишь.
    static func collapsed(metersPerPoint: Double, wasCollapsed: Bool) -> Bool {
        guard metersPerPoint > 0 else { return wasCollapsed }
        return wasCollapsed
            ? metersPerPoint > expandMetersPerPoint
            : metersPerPoint > collapseMetersPerPoint
    }

    // MARK: - Размеры того, что рисует код

    /// Длина конуса неуверенности в метрах карты.
    static let coneMeters: Double = 45
    /// Диаметр тени под машиной. Круг, а не силуэт: тень не вращается, и
    /// силуэтная на восточном курсе легла бы поперёк машины.
    static let shadowDiameter: CGFloat = 20
    /// Диаметр точки, в которую маркер схлопывается.
    static let dotDiameter: CGFloat = 13
    /// Круг точности мельче половины маркера прячется: он целиком под машиной,
    /// и рисовать его значит обещать точность, которой не видно.
    static let accuracyMinRadius: CGFloat = side * 0.5
    /// Дальше круг не растёт — на карманном зуме честные полкилометра радиуса
    /// залили бы экран целиком.
    static let accuracyMaxRadius: CGFloat = 900

    static let accuracyFill = UIColor(red: 0xC2 / 255, green: 0x45 / 255, blue: 0x2B / 255, alpha: 0.10)
    static let accuracyStroke = UIColor(red: 0xC2 / 255, green: 0x45 / 255, blue: 0x2B / 255, alpha: 0.26)
    static let coneFill = UIColor(red: 0xC2 / 255, green: 0x45 / 255, blue: 0x2B / 255, alpha: 0.16)
    static let pulseStroke = UIColor(red: 0xC2 / 255, green: 0x45 / 255, blue: 0x2B / 255, alpha: 0.55)

    // MARK: - Готовая картинка

    /// Собранный маркер для цвета из гаража («red», «silver», …).
    ///
    /// `nil` на входе — «без транспорта»: законный выбор человека, а не
    /// поломка, и красить нечем. Берём цвет гаража по умолчанию, чтобы маркер
    /// был, и был узнаваемым.
    ///
    /// Кэш по имени цвета и настроению: сборка — три офскрин-прохода, а маркер
    /// за реплей перерисовывается десятки раз в секунду. Зовётся только с
    /// главного потока (делегаты MapKit), поэтому замка здесь нет.
    static func image(colorName: String?, mood: Mood = .normal) -> UIImage? {
        let key = "\(colorName ?? VehicleAvatar.defaultColor)|\(mood.rawValue)"
        if let cached = cache[key] { return cached }
        guard let built = build(colorName: colorName ?? VehicleAvatar.defaultColor, mood: mood) else {
            return nil
        }
        cache[key] = built
        return built
    }

    private static var cache: [String: UIImage] = [:]

    /// Точка, в которую маркер схлопывается на мелком зуме.
    ///
    /// Цвет тот же, что у машины, — иначе на обзорном зуме теряется единственное,
    /// что маркер сообщал: чья это поездка. Белое кольцо вокруг обязательно:
    /// без него тёмная точка тонет в дороге под собой.
    static func dot(colorName: String?, mood: Mood = .normal) -> UIImage {
        let key = "\(colorName ?? VehicleAvatar.defaultColor)|\(mood.rawValue)"
        if let cached = dotCache[key] { return cached }
        let colour = paint(colorName: colorName ?? VehicleAvatar.defaultColor,
                           saturation: mood.saturation)
        let d = dotDiameter
        let image = UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { ctx in
            let full = CGRect(x: 0, y: 0, width: d, height: d)
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: full)
            colour.setFill()
            ctx.cgContext.fillEllipse(in: full.insetBy(dx: 2, dy: 2))
        }
        dotCache[key] = image
        return image
    }

    private static var dotCache: [String: UIImage] = [:]

    /// Пилюля с паузой — маленькая, в углу, НЕ вращается вместе с машиной.
    ///
    /// Одной приглушённой краски мало: серая машина на карте читается как
    /// «далеко» или «чужая», а не как «я сам нажал паузу». Знак говорит это
    /// словом, которое ни с чем не спутать.
    static let pausePill: UIImage = {
        let size = CGSize(width: 20, height: 14)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let capsule = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            UIColor.white.setFill()
            capsule.fill()
            let glyph = UIImage(
                systemName: "pause.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .black)
            )?.withTintColor(UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1),
                             renderingMode: .alwaysOriginal)
            guard let glyph else { return }
            glyph.draw(in: CGRect(
                x: rect.midX - glyph.size.width / 2,
                y: rect.midY - glyph.size.height / 2,
                width: glyph.size.width, height: glyph.size.height
            ))
        }
    }()

    // MARK: - Покраска

    /// Цвет краски: swatch гаража, зажатый по светлоте и приглушённый по
    /// настроению.
    ///
    /// Коридор 22–86% — не вкусовщина. Чистый чёрный сливается с собственным
    /// контуром, и машина превращается в кляксу; чистый белый сливается с
    /// белым ореолом, и остаётся один контур. Оба цвета в гараже есть, и оба
    /// — самые частые на дорогах.
    ///
    /// Насыщенность гасится ПОСЛЕ зажима светлоты: иначе «нет сигнала» у
    /// чёрной машины дало бы чёрный же прямоугольник вместо серой машины.
    static func paint(colorName: String, saturation: CGFloat = 1) -> UIColor {
        let (r, g, b) = VehicleAvatar.swatch(colorName)
        let base = UIColor(red: r, green: g, blue: b, alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard base.getHue(&hue, saturation: &sat, brightness: &brightness, alpha: &alpha) else {
            return base
        }
        let clamped = min(max(brightness, minBrightness), maxBrightness)
        return UIColor(hue: hue, saturation: sat * saturation, brightness: clamped, alpha: alpha)
    }

    static let minBrightness: CGFloat = 0.22
    static let maxBrightness: CGFloat = 0.86

    /// Во сколько раз затемняются борта и задняя кромка.
    private static let shadeFactor: CGFloat = 0.78

    private static func build(colorName: String, mood: Mood) -> UIImage? {
        guard let body = UIImage(named: "map_car_body"),
              let shade = UIImage(named: "map_car_shade"),
              let ink = UIImage(named: "map_car_ink") else { return nil }

        let box = CGSize(width: side, height: side)
        let rect = CGRect(origin: .zero, size: box)
        let color = paint(colorName: colorName, saturation: mood.saturation)
        let bodyLayer = tinted(body, with: color, in: box)
        let shadeLayer = tinted(shade, with: darkened(color), in: box)

        return UIGraphicsImageRenderer(size: box).image { ctx in
            // `.high`, а не `.none`. Отключённая интерполяция осталась от
            // пиксель-арта, где она сохраняла сетку; здесь слои — гладкий
            // вектор, ужатый с 512 до 44, и «ближайший сосед» выбрасывает из
            // каждых двенадцати строк одиннадцать, превращая контур в лесенку.
            ctx.cgContext.interpolationQuality = .high
            bodyLayer.draw(in: rect)
            shadeLayer.draw(in: rect)
            ink.draw(in: rect)
        }
    }

    /// Маска (белое с альфой) → та же форма, залитая цветом.
    ///
    /// `.destinationIn` в отдельном проходе, а не на общем холсте: на общем он
    /// вырезал бы по альфе маски всё, что уже нарисовано под ней.
    private static func tinted(_ mask: UIImage, with color: UIColor, in box: CGSize) -> UIImage {
        let rect = CGRect(origin: .zero, size: box)
        return UIGraphicsImageRenderer(size: box).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            color.setFill()
            ctx.fill(rect)
            mask.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }

    private static func darkened(_ color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        return UIColor(red: r * shadeFactor, green: g * shadeFactor, blue: b * shadeFactor, alpha: a)
    }
}
