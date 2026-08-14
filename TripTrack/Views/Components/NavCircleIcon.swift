import SwiftUI

/// Nav control (profile 117:944 / 117:948): a surface-filled circle carrying a
/// glyph, with a soft shadow lifting it off the warm background. Both ends of
/// `CustomNavBar` use it so «назад» and «…» read as one pair instead of a
/// filled circle on the left and three bare dots on the right. Colours are the
/// exact canon values: fill = `card` (#FFFFFF light), glyph = `text` (#1E1E23
/// light), background it sits on = `bg` (#F8F6F2).
///
/// Sized 40pt, not the artboard's 34. Canon was drawn on a 360pt frame; every
/// phone this ships to is 393–440pt wide, and the same absolute circle on a
/// fifth more width reads as a small control floating in a thin bar — which is
/// exactly how it landed on device. 40pt puts it back in proportion and brings
/// the visible circle within 4pt of the 44pt HIG target instead of 10.
///
/// Hit area: the tappable region is grown to the 44pt floor with `padding` +
/// `contentShape`, then taken back out of layout with negative padding so
/// nothing shifts.
///
/// Do NOT hang a `Menu` off this button. A Menu is a UIKit context menu, and
/// on dismissal UIKit spends ~0.9s animating a snapshot of the source view
/// back down on top of a rounded-SQUARE plate with its own shadow — against
/// the warm bar the plate's corners read as a translucent square frame around
/// the circle. Neither `contentShape(_:)` nor `contentShape(.contextMenuPreview, _:)`
/// reshapes it; both were measured frame-by-frame off a screen recording and
/// changed nothing. Use `ActionPopoverList` in a `.popover` for an action list,
/// or `.appConfirm(...)` for a confirmation (see `AppConfirmDialog`) — never a
/// `Menu` and never a system dialog.
struct NavCircleIcon: View {
    let systemImage: String
    var glyphSize: CGFloat = 18

    /// The visible circle. Also sets the bar's height, so `CustomNavBar` reads
    /// it rather than repeating the number.
    static let diameter: CGFloat = 40

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Image(systemName: systemImage)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(c.text)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Circle().fill(c.card))
            .shadow(
                color: .black.opacity(scheme == .dark ? 0.40 : 0.07),
                radius: 5,
                y: 2
            )
            .padding(2)
            .contentShape(Circle())
            .padding(-2)
    }
}
