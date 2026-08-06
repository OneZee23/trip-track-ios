import SwiftUI

/// Inter — the Figma design's actual typeface, bundled (OFL, Resources/
/// Fonts) and registered at runtime in `TripTrackApp`. SF Pro stood in
/// during the redesign, but at equal nominal weights SF reads visibly
/// thinner than Inter (SF Heavy vs Inter ExtraBold bit us on the feed
/// metric digits), so screens the user signs off against Figma migrate
/// to `.inter` per-screen.
///
/// Always `fixedSize`: the app sizes ALL type with fixed
/// `.system(size:)` values, and `Font.custom(_:size:)` — unlike
/// `.system(size:)` — scales with the user's Dynamic Type setting. On a
/// device with enlarged text the Inter runs ballooned while the SF text
/// around them stayed put (feed metrics, 2026-08-06).
extension Font {
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        if weight == .heavy || weight == .black {
            name = "Inter-ExtraBold"
        } else if weight == .bold {
            name = "Inter-Bold"
        } else if weight == .semibold {
            name = "Inter-SemiBold"
        } else if weight == .medium {
            name = "Inter-Medium"
        } else {
            name = "Inter-Regular"
        }
        return .custom(name, fixedSize: size)
    }
}
