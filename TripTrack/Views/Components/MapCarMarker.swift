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
enum MapCarMarker {

    /// Сторона бокса маркера. Одна на реплей и на живую запись: до 0.6.7 они
    /// разъезжались на 40 и 44 pt, то есть одна и та же машина была разного
    /// размера на двух экранах.
    static let side: CGFloat = 44

    // MARK: - Готовая картинка

    /// Собранный маркер для цвета из гаража («red», «silver», …).
    ///
    /// `nil` на входе — «без транспорта»: законный выбор человека, а не
    /// поломка, и красить нечем. Берём цвет гаража по умолчанию, чтобы маркер
    /// был, и был узнаваемым.
    ///
    /// Кэш по имени цвета: сборка — три офскрин-прохода, а маркер за реплей
    /// перерисовывается десятки раз в секунду. Зовётся только с главного
    /// потока (делегаты MapKit), поэтому замка здесь нет.
    static func image(colorName: String?) -> UIImage? {
        let key = colorName ?? VehicleAvatar.defaultColor
        if let cached = cache[key] { return cached }
        guard let built = build(colorName: key) else { return nil }
        cache[key] = built
        return built
    }

    private static var cache: [String: UIImage] = [:]

    // MARK: - Покраска

    /// Цвет краски: swatch гаража, зажатый по светлоте.
    ///
    /// Коридор 22–86% — не вкусовщина. Чистый чёрный сливается с собственным
    /// контуром, и машина превращается в кляксу; чистый белый сливается с
    /// белым ореолом, и остаётся один контур. Оба цвета в гараже есть, и оба
    /// — самые частые на дорогах.
    static func paint(colorName: String) -> UIColor {
        let (r, g, b) = VehicleAvatar.swatch(colorName)
        let base = UIColor(red: r, green: g, blue: b, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return base
        }
        let clamped = min(max(brightness, minBrightness), maxBrightness)
        return UIColor(hue: hue, saturation: saturation, brightness: clamped, alpha: alpha)
    }

    static let minBrightness: CGFloat = 0.22
    static let maxBrightness: CGFloat = 0.86

    /// Во сколько раз затемняются борта и задняя кромка.
    private static let shadeFactor: CGFloat = 0.78

    private static func build(colorName: String) -> UIImage? {
        guard let body = UIImage(named: "map_car_body"),
              let shade = UIImage(named: "map_car_shade"),
              let ink = UIImage(named: "map_car_ink") else { return nil }

        let box = CGSize(width: side, height: side)
        let rect = CGRect(origin: .zero, size: box)
        let color = paint(colorName: colorName)
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
