import SwiftUI

/// Figma canon nav control (profile 117:944 / 117:948): a 34pt surface-filled
/// circle carrying a ~17pt glyph, with a soft shadow lifting it off the warm
/// background. Both ends of `CustomNavBar` use it so «назад» and «…» read as
/// one pair instead of a filled circle on the left and three bare dots on the
/// right. Colours are the exact canon values: fill = `card` (#FFFFFF light),
/// glyph = `text` (#1E1E23 light), background it sits on = `bg` (#F8F6F2).
///
/// Hit area: the visible circle stays 34pt (canon — it also sets the bar
/// height), while the tappable region is grown to the 44pt HIG floor with
/// `padding` + `contentShape`, then taken back out of layout with negative
/// padding so nothing shifts.
///
/// Do NOT hang a `Menu` off this button. A Menu is a UIKit context menu, and
/// on dismissal UIKit spends ~0.9s animating a snapshot of the source view
/// back down on top of a rounded-SQUARE plate with its own shadow — against
/// the warm bar the plate's corners read as a translucent square frame around
/// the circle. Neither `contentShape(_:)` nor `contentShape(.contextMenuPreview, _:)`
/// reshapes it; both were measured frame-by-frame off a screen recording and
/// changed nothing. Use a `confirmationDialog` instead (see PublicProfileView).
struct NavCircleIcon: View {
    let systemImage: String
    /// Glyph point size — canon draws a 17pt box, which 16pt semibold fills.
    var glyphSize: CGFloat = 16

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Image(systemName: systemImage)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(c.text)
            .frame(width: 34, height: 34)
            .background(Circle().fill(c.card))
            .shadow(
                color: .black.opacity(scheme == .dark ? 0.40 : 0.07),
                radius: 5,
                y: 2
            )
            .padding(5)
            .contentShape(Circle())
            .padding(-5)
    }
}
