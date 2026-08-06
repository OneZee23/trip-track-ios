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
/// The circular content shape does double duty: UIKit derives the highlight
/// platter it flashes behind a `Menu` label from that shape, so the default
/// rectangle is what made a grey square outline blink around the dots when
/// the menu closed. A circle there matches the button and reads as a press.
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
            // Separate kind, separate shape: UIKit builds the preview plate
            // it flashes behind a `Menu` label on dismissal from the CONTEXT
            // MENU shape, not the interaction shape. Left at its default the
            // plate is the view's bounds — a white rounded square whose
            // corners poke out past our circle over the warm background.
            .contentShape(.contextMenuPreview, Circle())
            .padding(-5)
    }
}
