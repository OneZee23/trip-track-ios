import SwiftUI
import UIKit

// MARK: - Rarity Chip Colours (Figma 909:392)

/// The two colours canon draws a badge chip with: a saturated ring and a pale
/// tint behind it.
///
/// Canon draws four of the six tiers — #E5A61A / #9959CC / #338CE5 / #8C9199 —
/// and each one is byte-identical to that tier's existing `BadgeRarity.color`,
/// so the ring needs no second source of truth. The tints turn out to be one
/// construction too: every canon pair is the ring laid over white at 20 %
/// (#E5A61A → #FAEDD1, #9959CC → #EBDEF5, #338CE5 → #D6E8FA, #8C9199 → #E8E9EB,
/// all four exact to the byte). That is why `uncommon` and `exclusive`, which
/// canon never draws, can be derived instead of eyeballed — they come out of
/// the same rule as the four that were designed.
extension BadgeRarity {

    /// sRGB components of the tier's ring, matching `BadgeRarity.color`.
    ///
    /// Spelled out rather than read back off `color`: `color` also dresses the
    /// badge grid, and retuning it there must not silently move a canon screen.
    private var chipRGB: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .common:    return (0.55, 0.57, 0.60) // #8C9199
        case .uncommon:  return (0.18, 0.68, 0.35) // not in canon — derived
        case .rare:      return (0.20, 0.55, 0.90) // #338CE5
        case .epic:      return (0.60, 0.35, 0.80) // #9959CC
        case .legendary: return (0.90, 0.65, 0.10) // #E5A61A
        case .exclusive: return (0.86, 0.20, 0.58) // not in canon — derived
        }
    }

    /// The 1.5pt circle stroke — and the colour the rarity caption under the
    /// featured badge is set in.
    ///
    /// Dark lifts the hue toward white. Canon picked these against a white
    /// card; on the dark card (#1E1E20) the deeper tiers land near 3:1, which
    /// a hairline ring survives but 11pt text does not.
    var chipRing: Color {
        let (r, g, b) = chipRGB
        return Color(UIColor { tc in
            guard tc.userInterfaceStyle == .dark else {
                return UIColor(red: r, green: g, blue: b, alpha: 1)
            }
            let lift: CGFloat = 0.22
            return UIColor(red: r + (1 - r) * lift,
                           green: g + (1 - g) * lift,
                           blue: b + (1 - b) * lift,
                           alpha: 1)
        })
    }

    /// The ring darkened for use as INK — the rarity caption under the featured
    /// badge, and the glyph inside the disc.
    ///
    /// The ring itself is a hairline against a tint of the same hue: legendary
    /// lands at 1.86:1 on its own tint, which a 1.5pt stroke reads fine at and
    /// 11pt text does not. Canon already knew this — it sets that caption in
    /// #B8800D, a shaded #E5A61A, not the ring colour. Shading by the same 0.22
    /// the dark mode lifts by reproduces it to within a percent and extends the
    /// rule to the two tiers canon never drew.
    var chipText: Color {
        let (r, g, b) = chipRGB
        return Color(UIColor { tc in
            guard tc.userInterfaceStyle == .dark else {
                let shade: CGFloat = 0.22
                return UIColor(red: r * (1 - shade),
                               green: g * (1 - shade),
                               blue: b * (1 - shade),
                               alpha: 1)
            }
            // Dark already sits on a 16 %-alpha tint, where the lifted ring is
            // the legible one — no second treatment.
            let lift: CGFloat = 0.22
            return UIColor(red: r + (1 - r) * lift,
                           green: g + (1 - g) * lift,
                           blue: b + (1 - b) * lift,
                           alpha: 1)
        })
    }

    /// The circle fill.
    ///
    /// Dark cannot use the canon tint — a near-white slab is the loudest thing
    /// on the screen — so it becomes the ring at low alpha over whatever sits
    /// behind, the same fix `AppTheme.goldBg` makes for the LVL pill.
    var chipTint: Color { tint(over: 0.2, darkAlpha: 0.16) }

    /// The featured row's background — a WEAKER wash than the chip that sits on
    /// it. Canon draws the row #FBF3DF under a #FAEDD1 disc: same hue, 14 % vs
    /// 20 %, which is what keeps the disc visible instead of dissolving into
    /// the row.
    var rowTint: Color { tint(over: 0.14, darkAlpha: 0.10) }

    private func tint(over: CGFloat, darkAlpha: CGFloat) -> Color {
        let (r, g, b) = chipRGB
        return Color(UIColor { tc in
            if tc.userInterfaceStyle == .dark {
                return UIColor(red: r, green: g, blue: b, alpha: darkAlpha)
            }
            return UIColor(red: 1 - (1 - r) * over,
                           green: 1 - (1 - g) * over,
                           blue: 1 - (1 - b) * over,
                           alpha: 1)
        })
    }
}

// MARK: - Unlock share

extension Badge {
    /// «0,4» / «3» — the global unlock share, one decimal, RU comma, and no
    /// dangling «,0». Canon prints «0,4%» beside «3%», so the decimal exists
    /// for the sub-1 % tiers and nowhere else.
    ///
    /// Lives here because three screens print this number — the profile's
    /// featured row, the award grid and the award detail — and three private
    /// copies had already drifted into printing «3%» in one and «3,0%» in the
    /// next, for the same badge.
    ///
    /// Not `NumberFormatter`: the app's language is not the device's, and a
    /// phone on en_US showing the RU screen still owes «0,4».
    static func unlockShareText(_ value: Double, _ lang: LanguageManager.Language) -> String {
        var s = String(format: "%.1f", value)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return lang == .ru ? s.replacingOccurrences(of: ".", with: ",") : s
    }
}
