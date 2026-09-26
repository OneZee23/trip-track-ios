import XCTest
import UIKit
import SwiftUI
@testable import TripTrack

/// Рисунки значков (0.8.2) — 58 гравюр вместо SF Symbols.
///
/// Обе проверки про то, что нельзя увидеть кодом: доехал ли ассет до бандла и
/// тот ли у него ободок. Редкость художник проставлял на глаз (он не видел
/// `docs/achievements.md`) и разошёлся с кодом на девятнадцати значках —
/// ободки перекрашены при заведении в каталог, и этот тест сторожит, чтобы
/// они не разъехались снова.
final class BadgeArtTests: XCTestCase {

    /// У КАЖДОГО значка есть свой рисунок.
    ///
    /// Имя ассета — это `id`, то есть ключ в базе: переименование ломает уже
    /// выданные значки, и пропажа картинки выглядела бы на полке пустым
    /// местом, а не ошибкой.
    func testEveryBadgeHasItsArt() {
        var missing: [String] = []
        for badge in Badge.all where UIImage(named: BadgeArt.assetName(for: badge.id)) == nil {
            missing.append(badge.id)
        }
        XCTAssertTrue(missing.isEmpty, "без рисунка остались: \(missing)")
    }

    /// Внешнее кольцо каждого значка выведено из редкости, которая у него В
    /// КОДЕ.
    ///
    /// Сравнивается именно ОНО, а не яркое кольцо под ним: колец у значка
    /// несколько (контур, фаска, само кольцо, блик), и какая из ступеней
    /// лесенки окажется второй — решает рисунок конкретного значка. А самое
    /// внешнее у всех пятидесяти восьми одно и то же: редкость, затемнённая
    /// до 45 %. На этом тест и поймал заведение, где перекрашена была одна
    /// ступень из пяти.
    func testRimColourMatchesTheRarityInCode() {
        var wrong: [String] = []
        for badge in Badge.all {
            guard let image = UIImage(named: BadgeArt.assetName(for: badge.id)),
                  let rim = Self.rimColour(of: image) else {
                wrong.append("\(badge.id): не прочитался")
                continue
            }
            let full = Self.components(of: UIColor(badge.rarity.color))
            let want = (r: full.r * 0.45, g: full.g * 0.45, b: full.b * 0.45)
            let far = max(abs(rim.r - want.r), abs(rim.g - want.g), abs(rim.b - want.b))
            if far > 0.06 {
                wrong.append("\(badge.id): кольцо \(rim) вместо \(badge.rarity) \(want)")
            }
        }
        XCTAssertTrue(wrong.isEmpty, "ободок не по редкости:\n" + wrong.joined(separator: "\n"))
    }

    // MARK: - Пиксели

    /// Цвет САМОГО ВНЕШНЕГО кольца — первой непрозрачной краски на средней
    /// строке. Ищется перебором, а не по вбитой координате: долю канвы под
    /// диск выбирает художник, и вбитое число разъехалось бы с первым же
    /// перерисованным значком.
    private static func rimColour(of image: UIImage) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let side = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let raster = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format
        ).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let cg = raster.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        let row = side / 2
        for x in 0..<side {
            let i = (row * side + x) * 4
            let a = CGFloat(pixels[i + 3]) / 255
            guard a > 0.9 else { continue }
            return (CGFloat(pixels[i]) / 255 / a,
                    CGFloat(pixels[i + 1]) / 255 / a,
                    CGFloat(pixels[i + 2]) / 255 / a)
        }
        return nil
    }

    private static func components(of colour: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }
}
