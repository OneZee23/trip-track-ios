import XCTest
import UIKit
import SwiftUI
@testable import TripTrack

/// Рисунки значков (0.8.2, второй набор) — СИМВОЛЫ без оправы.
///
/// Первый набор приезжал медалями: диск, ободок редкости и тень были вшиты в
/// графику, и редкость приходилось перекрашивать прямо в файлах. Владелец
/// заменил его символами (26 сен) — контейнер теперь рисует приложение.
/// Поэтому и сторожа другие: раньше проверяли цвет вшитого кольца, теперь —
/// что кольца НЕТ, а цвет живёт в коде.
final class BadgeArtTests: XCTestCase {

    /// У КАЖДОГО значка есть свой рисунок.
    ///
    /// Имя ассета — это `id`, то есть ключ в базе: переименование ломает уже
    /// выданные значки, а пропажа картинки выглядела бы на полке пустым
    /// местом, а не ошибкой.
    func testEveryBadgeHasItsArt() {
        var missing: [String] = []
        for badge in Badge.all where UIImage(named: BadgeArt.assetName(for: badge.id)) == nil {
            missing.append(badge.id)
        }
        XCTAssertTrue(missing.isEmpty, "без рисунка остались: \(missing)")
    }

    /// У символа НЕТ своей оправы: углы картинки прозрачны.
    ///
    /// Медаль первого набора заливала диск от края до края, и её угол был
    /// непрозрачным. Тест падает в тот день, когда в каталог вернут значок с
    /// вшитым кругом, — а на глаз такую подмену видно только рядом с
    /// остальными, то есть слишком поздно.
    func testSymbolsCarryNoBakedContainer() {
        var framed: [String] = []
        for badge in Badge.all {
            guard let image = UIImage(named: BadgeArt.assetName(for: badge.id)),
                  let corners = Self.cornerAlpha(of: image) else {
                framed.append("\(badge.id): не прочитался")
                continue
            }
            if corners.contains(where: { $0 > 0.2 }) { framed.append(badge.id) }
        }
        XCTAssertTrue(framed.isEmpty, "рисунок с собственной оправой: \(framed)")
    }

    /// Заливка плитки — по редкости, и своя на каждую тему.
    ///
    /// Шесть пар подобраны автором набора так, чтобы символ читался и на
    /// светлой, и на тёмной; подменить их на `rarity.color` с прозрачностью
    /// нельзя — выйдет не то. Числа сверяются с `badges.json`.
    func testTileFillFollowsRarityAndScheme() {
        let expected: [BadgeRarity: (light: UInt32, dark: UInt32)] = [
            .common: (0xF1F2F3, 0x35393D), .uncommon: (0xE6F5EB, 0x213F2F),
            .rare: (0xE7F1FC, 0x22384E), .epic: (0xF3EBF9, 0x382D48),
            .legendary: (0xFCF4E4, 0x493D21), .exclusive: (0xFBE7F2, 0x47243C),
        ]
        for (rarity, want) in expected {
            for dark in [false, true] {
                let got = Self.components(of: UIColor(BadgeTileFill.colour(for: rarity, dark: dark)))
                let hex = dark ? want.dark : want.light
                let ref = (r: CGFloat((hex >> 16) & 0xFF) / 255,
                           g: CGFloat((hex >> 8) & 0xFF) / 255,
                           b: CGFloat(hex & 0xFF) / 255)
                XCTAssertEqual(got.r, ref.r, accuracy: 1.0 / 255, "\(rarity) dark=\(dark) красный")
                XCTAssertEqual(got.g, ref.g, accuracy: 1.0 / 255, "\(rarity) dark=\(dark) зелёный")
                XCTAssertEqual(got.b, ref.b, accuracy: 1.0 / 255, "\(rarity) dark=\(dark) синий")
            }
        }
    }

    /// Светлая и тёмная заливки одной редкости обязаны РАЗЛИЧАТЬСЯ.
    ///
    /// Иначе полоса достижений в тёмной теме светится молочными плитками —
    /// ровно то, ради чего у автора набора две таблицы, а не одна.
    func testEachRarityHasTwoDistinctFills() {
        for rarity in [BadgeRarity.common, .uncommon, .rare, .epic, .legendary, .exclusive] {
            let light = Self.components(of: UIColor(BadgeTileFill.colour(for: rarity, dark: false)))
            let dark = Self.components(of: UIColor(BadgeTileFill.colour(for: rarity, dark: true)))
            XCTAssertGreaterThan(light.r + light.g + light.b, dark.r + dark.g + dark.b,
                                 "\(rarity): тёмная плитка не темнее светлой")
        }
    }

    // MARK: - Пиксели

    /// Альфа четырёх углов картинки, отрисованной в 96×96 — ту же сетку, по
    /// которой символы нарисованы.
    private static func cornerAlpha(of image: UIImage) -> [CGFloat]? {
        let side = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let raster = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format
        ).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
        guard let cg = raster.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let spots = [(2, 2), (side - 3, 2), (2, side - 3), (side - 3, side - 3)]
        return spots.map { CGFloat(pixels[($1 * side + $0) * 4 + 3]) / 255 }
    }

    private static func components(of colour: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }
}
