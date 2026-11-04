import SwiftUI

/// A person's avatar emoji drawn from TripTrack's own artwork, the same images the Android app ships, so a person looks
/// the same on both phones. The iPhone showed Apple's emoji and Android Google's, and Apple's artwork cannot ship on
/// Android (owner, 4 Nov 2026: «что там что там одинаковые»). The stored value stays the emoji; one outside the set (a
/// retired pick, anything an old client wrote) falls back to the font.
enum AvatarArt {
    private static let names: [String: String] = [
        "😎": "1f60e", "🙂": "1f642", "😄": "1f604", "🤠": "1f920", "🥸": "1f978", "🧔": "1f9d4",
        "👨‍🦳": "1f468_200d_1f9b3", "👩": "1f469", "👩‍🦰": "1f469_200d_1f9b0", "👱‍♀": "1f471_200d_2640",
        "👵": "1f475", "🐶": "1f436",
        // Retired from the picker, still worn (`MyProfileView.avatars`).
        "🌅": "1f305", "🎸": "1f3b8", "📷": "1f4f7", "🎮": "1f3ae", "🚀": "1f680", "🚙": "1f699",
    ]

    /// The asset for an emoji. The variation selector is optional in stored values: «👱‍♀️» arrives with U+FE0F and
    /// without it.
    static func imageName(for emoji: String) -> String? {
        names[emoji.replacingOccurrences(of: "\u{FE0F}", with: "")].map { "Avatars/avatar_\($0)" }
    }

    static var emojis: [String] { Array(names.keys) }
}

/// Where an avatar used to be `Text(emoji).font(.inter(fontSize))`: the artwork in the box the emoji glyph took, or
/// the text itself for an emoji outside the set. The art fills 86 % of its square, as an emoji fills its em.
struct AvatarGlyph: View {
    let emoji: String
    let fontSize: CGFloat

    var body: some View {
        if let name = AvatarArt.imageName(for: emoji) {
            Image(name)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: fontSize * Self.scale, height: fontSize * Self.scale)
                .accessibilityHidden(true)
        } else {
            Text(emoji).font(.inter(fontSize))
        }
    }

    /// An emoji glyph is about 1.15 em wide; the art's subject is 86 % of its image.
    private static let scale: CGFloat = 1.15 / 0.86
}
