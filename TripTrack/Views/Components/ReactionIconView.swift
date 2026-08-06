import SwiftUI

/// Drawn reaction icon (Figma Components → ReactionIcon, 24×24 template
/// SVGs bundled as `reaction_<name>_<state>` assets) keyed by the emoji
/// string the server stores. Legacy prod emoji (❤️ 🏎️ 🗺️) resolve to
/// their canonical replacement via `ReactionEmoji.canonical`, so every
/// known key renders as a drawn icon; the raw-emoji fallback only fires
/// for keys a future server might introduce before the app learns them.
struct ReactionIconView: View {
    let emoji: String
    var size: CGFloat = 14
    var filled: Bool = false
    /// Explicit tint override. Default: fill state → accent (the Figma
    /// fill variant is #EB571E), outline state → theme ink.
    var tint: Color? = nil

    @Environment(\.colorScheme) private var scheme

    /// Canonical emoji → asset base name. Order-independent lookup;
    /// palette order lives in `ReactionEmoji.all`.
    private static let assetBases: [String: String] = [
        "🔥": "fire", "🤯": "wow", "🏁": "finish",
        "🛣️": "pass", "🌅": "frame", "👍": "like",
    ]

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        if let base = Self.assetBases[ReactionEmoji.canonical(emoji)] {
            Image("reaction_\(base)_\(filled ? "fill" : "outline")")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(tint ?? (filled ? AppTheme.accent : c.text))
        } else {
            Text(emoji)
                .font(.system(size: size))
        }
    }
}
