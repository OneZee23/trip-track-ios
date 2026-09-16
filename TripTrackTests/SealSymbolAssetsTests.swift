import XCTest
import UIKit
@testable import TripTrack

/// Гравюры печатей — по каталогу, а не по экрану.
///
/// Символ на печати это единственное, чем одна находка отличается от другой,
/// и ассет у него не «картинка про запас»: без набора `SealPainter` тихо
/// уходит на SF-символ, а у `komsomolsky` системного символа не существует
/// вовсе — печать первого авторского секрета осталась бы пустым диском, и ни
/// сборка, ни один поведенческий тест этого не заметили бы.
///
/// Поэтому тест читает САМ каталог по `#filePath` (тот же приём, что у
/// `UnitsDisciplineTests`): восемнадцать наборов, в каждом ровно один SVG,
/// у каждого — намерение шаблона. Стиль тоже читается: 24×24, линия 1.5,
/// без заливок и без текста — гравюры обязаны выглядеть одним набором, а не
/// восемнадцатью находками разных рук.
final class SealSymbolAssetsTests: XCTestCase {

    /// Корень репозитория — от файла теста, а не от бандла: в бандле лежит
    /// уже скомпилированный `Assets.car`, по которому ни стиль, ни число
    /// файлов не проверить.
    private static var assetsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TripTrackTests
            .deletingLastPathComponent()   // корень
            .appendingPathComponent("TripTrack/Resources/Assets.xcassets")
    }

    private func set(for symbol: SealSymbol) -> URL {
        Self.assetsRoot.appendingPathComponent("\(symbol.assetName).imageset")
    }

    // MARK: - Наборы

    func testEverySymbolHasAnEngravingSet() {
        XCTAssertEqual(SealSymbol.allCases.count, 18, "восемнадцатый символ — «Знак Комсомольского»")
        for symbol in SealSymbol.allCases {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: set(for: symbol).path, isDirectory: &isDirectory)
            XCTAssertTrue(exists && isDirectory.boolValue,
                          "у \(symbol) нет гравюры \(symbol.assetName).imageset")
        }
    }

    /// Ассет-имя выводится из имени КЕЙСА, а не из `rawValue`: в `rawValue`
    /// стоят точки («mountain.2»), и он контракт с сервером.
    func testAssetNameComesFromTheCaseNotFromTheRawValue() {
        XCTAssertEqual(SealSymbol.pass.assetName, "seal_pass")
        XCTAssertEqual(SealSymbol.seaRoad.assetName, "seal_seaRoad")
        XCTAssertEqual(SealSymbol.komsomolsky.assetName, "seal_komsomolsky")
        XCTAssertEqual(SealSymbol.komsomolsky.rawValue, "seal.komsomolsky",
                       "rawValue — контракт с сервером, менять нельзя")
        XCTAssertEqual(Set(SealSymbol.allCases.map(\.assetName)).count, 18,
                       "два символа делят одну гравюру")
    }

    func testEverySetIsExactlyOneTemplateSvg() throws {
        for symbol in SealSymbol.allCases {
            let folder = set(for: symbol)
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            let svgs = files.filter { $0.hasSuffix(".svg") }
            XCTAssertEqual(svgs.count, 1, "\(symbol.assetName): ровно один SVG")
            XCTAssertEqual(Set(files), Set(["Contents.json", "\(symbol.assetName).svg"]),
                           "\(symbol.assetName): в наборе только Contents.json и SVG — растра нет")

            let data = try Data(contentsOf: folder.appendingPathComponent("Contents.json"))
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any])
            let images = try XCTUnwrap(json["images"] as? [[String: Any]])
            XCTAssertEqual(images.count, 1, "\(symbol.assetName): один универсальный вариант")
            XCTAssertEqual(images.first?["filename"] as? String, "\(symbol.assetName).svg")
            let properties = try XCTUnwrap(json["properties"] as? [String: Any],
                                           "\(symbol.assetName): нет properties")
            XCTAssertEqual(properties["template-rendering-intent"] as? String, "template",
                           "\(symbol.assetName): гравюра красится белым 70 %, значит шаблон")
            XCTAssertEqual(properties["preserves-vector-representation"] as? Bool, true,
                           "\(symbol.assetName): печать рисуется и в 26 pt, и в 44 pt")
        }
    }

    /// Гравюры — один стиль: 24×24, одинарная линия 1.5, скруглённые концы,
    /// без заливок и без текста.
    func testEngravingsShareOneStyle() throws {
        for symbol in SealSymbol.allCases {
            let file = set(for: symbol).appendingPathComponent("\(symbol.assetName).svg")
            let svg = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(svg.contains(#"viewBox="0 0 24 24""#), "\(symbol.assetName): не 24×24")
            XCTAssertTrue(svg.contains(#"stroke-width="1.5""#), "\(symbol.assetName): линия не 1.5")
            XCTAssertTrue(svg.contains(#"stroke-linecap="round""#),
                          "\(symbol.assetName): концы не скруглены")
            XCTAssertFalse(svg.contains("<text"), "\(symbol.assetName): текста в гравюре быть не может")
            XCTAssertFalse(svg.contains("<image"), "\(symbol.assetName): растра в гравюре быть не может")
            XCTAssertFalse(svg.contains("fill=\"#"),
                           "\(symbol.assetName): заливок нет — только линия")
            let strokes = svg.components(separatedBy: "stroke=\"").count - 1
            let paths = svg.components(separatedBy: "<path").count - 1
            XCTAssertGreaterThan(paths, 0, "\(symbol.assetName): в гравюре нет ни одного пути")
            XCTAssertEqual(strokes, paths, "\(symbol.assetName): у каждого пути свой stroke")
        }
    }

    /// Лишний `seal_*` в каталоге — это гравюра, которую никто не рисует:
    /// либо кейс удалили, либо набор назвали не тем именем.
    func testNoOrphanEngravingSets() throws {
        let all = try FileManager.default
            .contentsOfDirectory(atPath: Self.assetsRoot.path)
            .filter { $0.hasPrefix("seal_") }
        let expected = Set(SealSymbol.allCases.map { "\($0.assetName).imageset" })
        XCTAssertEqual(Set(all), expected, "в каталоге лишние или недостающие гравюры")
    }

    // MARK: - Лист гравюр

    /// Контрольный лист: все восемнадцать печатей в 44 pt, двумя рядами.
    ///
    /// Гравюру нельзя принять по коду — её принимают глазами, и лист кладётся
    /// файлом рядом с журналом задачи (плюс вложением в отчёт XCTest).
    /// Пишется только в отладочной сборке и только если корень репозитория на
    /// месте: на CI без исходников теста просто нечего писать.
    func testContactSheetOfEveryEngraving() throws {
        let seal: CGFloat = 44
        let cell = CGSize(width: 76, height: 78)
        let columns = 9
        let rows = (SealSymbol.allCases.count + columns - 1) / columns
        let sheet = CGSize(width: cell.width * CGFloat(columns),
                           height: cell.height * CGFloat(rows))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: sheet, format: format).image { context in
            UIColor(red: 0x2B / 255, green: 0x30 / 255, blue: 0x3C / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: sheet))
            for (index, symbol) in SealSymbol.allCases.enumerated() {
                let column = index % columns, row = index / columns
                let origin = CGPoint(x: CGFloat(column) * cell.width,
                                     y: CGFloat(row) * cell.height)
                let kind: DiscoveryKind = [.secret, .riddle, .milestone][index % 3]
                SealPainter.image(kind: kind, symbol: symbol, size: seal, scale: 3)
                    .draw(at: CGPoint(x: origin.x + (cell.width - seal) / 2, y: origin.y + 8))
                let label = symbol.assetName.replacingOccurrences(of: "seal_", with: "")
                (label as NSString).draw(
                    in: CGRect(x: origin.x, y: origin.y + seal + 12, width: cell.width, height: 12),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 8),
                        .foregroundColor: UIColor.white.withAlphaComponent(0.7),
                        .paragraphStyle: {
                            let style = NSMutableParagraphStyle()
                            style.alignment = .center
                            return style
                        }()
                    ])
            }
        }
        let png = try XCTUnwrap(image.pngData())

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "w070_w5_glyphs.png"
        attachment.lifetime = .keepAlways
        add(attachment)

        let shots = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".superpowers/sdd/2026-09-16-070-wave5-komsomolsky-release/shots")
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: shots.path) {
            try png.write(to: shots.appendingPathComponent("w070_w5_glyphs.png"))
        }
    }
}
