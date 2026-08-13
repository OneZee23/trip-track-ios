import SwiftUI

/// A sheet exactly as tall as what it holds.
///
/// The alternative — and what most of this app's sheets did — is to pick a
/// detent by hand (`.medium`, `.height(473)`, `.height(400)`) and let a
/// trailing `Spacer` soak up whatever the content did not use. That reads as a
/// card with a field of dead background under its buttons, and it is worse the
/// more the content varies: the same sheet carries eight different headlines,
/// or a message that is two lines on one trip and five on another.
///
/// The system clamps a `.height` bigger than the screen down to the maximum,
/// so tall content needs no cap here — it simply lands at full height and
/// scrolls if it was built to.
///
/// Give the content its own bottom padding; this adds only the home-indicator
/// strip, which is the phone's, not the design's.
struct ContentSizedSheet: ViewModifier {
    /// The sheet's own ground. Passed in rather than applied by the caller
    /// because the detent adds the home-indicator strip on top of the measured
    /// content: paint only as far as the content goes and that strip shows the
    /// system's default sheet colour instead — a band of the wrong grey under
    /// the buttons, which is exactly what this modifier exists to avoid.
    var background: Color
    /// Floor, for a sheet that would otherwise be too small to grab.
    var minimum: CGFloat = 0

    @State private var measured: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ContentSheetHeightKey.self, value: geo.size.height
                    )
                }
            }
            .onPreferenceChange(ContentSheetHeightKey.self) { measured = $0 }
            // Content sits at the top; the ground runs to the bottom edge.
            .frame(maxHeight: .infinity, alignment: .top)
            // The SHEET's own ground, not just the content's. A background
            // behind the content stops where the content's frame stops, which
            // leaves the strip above it — the one the grabber sits in — and
            // the strip below showing whatever the system paints a sheet with,
            // read as two pale bands framing the card.
            .presentationBackground(background)
            .presentationDetents([.height(max(measured, minimum) + Self.bottomInset)])
    }

    /// Looked up rather than laid out: the detent is a number, not a view, so
    /// there is no safe area to read from where it is needed.
    private static var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
    }
}

private struct ContentSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Sizes this sheet to its content. See `ContentSizedSheet`.
    func contentSizedSheet(background: Color, minimum: CGFloat = 0) -> some View {
        modifier(ContentSizedSheet(background: background, minimum: minimum))
    }
}
