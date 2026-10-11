import XCTest

/// A segment drawn clear when it is not selected must still take a tap across
/// its whole shape (0.8.9).
///
/// SwiftUI hit-tests a `Button` by what its label draws. The selected segment
/// has a fill and catches taps everywhere; the unselected one is
/// `Color.clear`, so only the letters of its word were tappable — «Подписки»
/// in the feed was a 66 × 16 pt target inside a 178 × 32 pt half, and the
/// trip's energy switch and the vehicle trips sort had the same shape. A
/// `.contentShape` on the label makes the whole segment the target.
///
/// This reads the sources: a `Button` whose label paints a background or fill
/// with `… ? … : Color.clear` / `.clear` must carry a `.contentShape` in the
/// same label. The check is per `Button {…} label: {…}` block, so a shape on a
/// neighbouring view doesn't count.
final class ClearPillTapShapeTests: XCTestCase {
    func testEveryClearSegmentHasATapShape() throws {
        let views = UnitGuard.repoRoot().appendingPathComponent("TripTrack/Views")
        let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty)
        // A ternary that ends in a clear colour, inside a fill or background —
        // on one line or spread over several, as in the feed switcher.
        let clearFill = try NSRegularExpression(
            pattern: #"(\.fill|\.background)\((?:[^()]|\([^()]*\))*?\?(?:[^()]|\([^()]*\))*?:\s*(Color\.clear|\.clear)\b"#,
            options: [.dotMatchesLineSeparators])
        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for label in Self.buttonLabels(in: source) {
                let range = NSRange(label.text.startIndex..., in: label.text)
                guard clearFill.firstMatch(in: label.text, range: range) != nil else { continue }
                if !label.text.contains(".contentShape(") {
                    offenders.append("\(file.lastPathComponent):\(label.line)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Clear segment without a tap shape: \(offenders)")
    }

    /// The text of each `} label: { … }` block, found by brace matching.
    private static func buttonLabels(in source: String) -> [(line: Int, text: String)] {
        var result: [(Int, String)] = []
        let chars = Array(source)
        let marker = Array("} label: {")
        var i = 0
        while i + marker.count <= chars.count {
            if Array(chars[i..<(i + marker.count)]) == marker {
                var depth = 1
                var j = i + marker.count
                while j < chars.count, depth > 0 {
                    if chars[j] == "{" { depth += 1 } else if chars[j] == "}" { depth -= 1 }
                    j += 1
                }
                let line = chars[0..<i].filter { $0 == "\n" }.count + 1
                result.append((line, String(chars[(i + marker.count)..<max(i + marker.count, j - 1)])))
                i = j
            } else {
                i += 1
            }
        }
        return result
    }
}
