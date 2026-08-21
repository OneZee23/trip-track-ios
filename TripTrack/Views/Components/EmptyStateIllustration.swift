import SwiftUI

/// The drawn scene an empty screen leads with.
///
/// The illustrations carry their own navy backdrop, so the plate IS the
/// artwork — rounding it is all the framing needed, and that reads as a
/// deliberate accent on the light theme's cream rather than as a rendering
/// fault. Sizing lives here so the empty screens stay the same size as each
/// other; they are seen one at a time, months apart, and nothing else would
/// catch them drifting.
struct EmptyStateIllustration: View {
    let name: String
    /// Bigger than it first shipped. At 104-132 pt a navy scene on a cream card
    /// reads as a dark square somebody forgot to style; the drawing only starts
    /// to look deliberate once it is large enough to be seen as a picture. Same
    /// lesson the onboarding heroes taught, applied one size down.
    var size: CGFloat = 156

    var body: some View {
        Image(name)
            .resizable()
            // After `resizable()`: that call rebuilds the Image and a
            // nearest-neighbour hint set before it may not survive.
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            // The scene is decoration; the heading under it carries the meaning.
            .accessibilityHidden(true)
    }
}
