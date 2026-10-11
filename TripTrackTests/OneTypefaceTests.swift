import XCTest

/// One typeface — Inter — for every word on screen (decision 26 Sep 2026).
///
/// The move to Inter caught 743 text sites; 49 more were found on 11 Oct
/// still on the system face, the trip tiles' numbers among them (SF Heavy
/// reads visibly thinner than Inter ExtraBold beside it). This reads the
/// sources: a `Text(...)` whose font is `.system(size:)` fails. SF Symbols
/// keep the system font — Inter has no glyphs for them — and so do emoji and
/// the deliberate monospaced faces (an id in the sync queue, a debug dump).
final class OneTypefaceTests: XCTestCase {
    func testNoTextIsSetInTheSystemFace() throws {
        let views = UnitGuard.repoRoot().appendingPathComponent("TripTrack/Views")
        let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty)
        let font = try NSRegularExpression(pattern: #"\.font\(\.system\(size:"#)
        let textHead = try NSRegularExpression(pattern: #"^\s*(return\s+)?Text\("#)
        let glyph = try NSRegularExpression(
            pattern: #"Text\((emoji|fallbackEmoji|avatar|model\.badge|[A-Za-z.]*[Ee]moji\b)"#)
        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated()
            where font.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                && !line.contains("monospaced") {
                // A modifier on the same line belongs to the view right
                // before it: `Image(systemName:).font(.system(...))` after a
                // `Text` on that line is the glyph's own font.
                if let fontAt = line.range(of: ".font(.system(size:"),
                   line[..<fontAt.lowerBound].contains("Image(") { continue }
                // The view the modifier belongs to: the nearest line above
                // that is not itself a modifier, a comment or blank.
                var j = i - 1
                while j >= 0 {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty || t.hasPrefix(".") || t.hasPrefix("//") { j -= 1 } else { break }
                }
                guard j >= 0 else { continue }
                let head = lines[j]
                let r = NSRange(head.startIndex..., in: head)
                if textHead.firstMatch(in: head, range: r) != nil, glyph.firstMatch(in: head, range: r) == nil {
                    offenders.append("\(file.lastPathComponent):\(i + 1)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Text in the system face instead of Inter: \(offenders)")
    }
}
