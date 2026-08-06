import XCTest
@testable import TripTrack

/// Backward compatibility of the reaction palette swap: prod trips carry
/// legacy emoji (❤️ 🏎️ 🗺️) that must render as — and merge into — their
/// canonical drawn-icon replacements without losing counts.
final class ReactionEmojiTests: XCTestCase {
    func testCanonPaletteIsSixDrawnIcons() {
        XCTAssertEqual(ReactionEmoji.all, ["🔥", "🤯", "🏁", "🛣️", "🌅", "👍"])
    }

    func testLegacyMapsToCanonical() {
        XCTAssertEqual(ReactionEmoji.canonical("❤️"), "👍")
        XCTAssertEqual(ReactionEmoji.canonical("🏎️"), "🏁")
        XCTAssertEqual(ReactionEmoji.canonical("🗺️"), "🛣️")
    }

    func testCanonicalKeysPassThrough() {
        for emoji in ReactionEmoji.all {
            XCTAssertEqual(ReactionEmoji.canonical(emoji), emoji)
        }
    }

    func testVariationSelectorStrippedFormRecognized() {
        // Some client builds round-trip 🏎️/🗺️ without U+FE0F.
        XCTAssertEqual(ReactionEmoji.canonical("🏎"), "🏁")
        XCTAssertEqual(ReactionEmoji.canonical("🗺"), "🛣️")
    }

    func testUnknownEmojiPassesThrough() {
        XCTAssertEqual(ReactionEmoji.canonical("🦄"), "🦄")
    }

    func testMergedTalliesFoldsLegacyIntoCanonical() {
        let merged = ReactionEmoji.mergedTallies([
            ReactionTally(emoji: "❤️", count: 2),
            ReactionTally(emoji: "👍", count: 1),
            ReactionTally(emoji: "🔥", count: 2),
        ])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first, ReactionTally(emoji: "👍", count: 3))
        XCTAssertEqual(merged.last, ReactionTally(emoji: "🔥", count: 2))
    }

    func testMergedTalliesTieBreaksOnPaletteOrder() {
        let merged = ReactionEmoji.mergedTallies([
            ReactionTally(emoji: "🌅", count: 1),
            ReactionTally(emoji: "🔥", count: 1),
        ])
        XCTAssertEqual(merged.map(\.emoji), ["🔥", "🌅"])
    }

    func testMergedTalliesKeepsUnknownKeys() {
        let merged = ReactionEmoji.mergedTallies([ReactionTally(emoji: "🦄", count: 4)])
        XCTAssertEqual(merged, [ReactionTally(emoji: "🦄", count: 4)])
    }
}
