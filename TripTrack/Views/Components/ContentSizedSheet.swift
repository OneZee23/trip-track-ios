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
    /// Floor, for a sheet that would otherwise be too small to grab.
    var minimum: CGFloat = 0

    @State private var measured: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ContentSheetHeightKey.self, value: geo.size.height
                    )
                }
            }
            .onPreferenceChange(ContentSheetHeightKey.self) { measured = $0 }
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
    func contentSizedSheet(minimum: CGFloat = 0) -> some View {
        modifier(ContentSizedSheet(minimum: minimum))
    }
}
