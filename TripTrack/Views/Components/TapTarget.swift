import SwiftUI

/// A finger-sized target around a small control, without moving anything.
///
/// Apple's minimum is 44 × 44 pt. Text links like «13 из 35 ›» or «Октябрь ⌄»
/// and the 25 pt capsules in «Моменты» are drawn smaller than that, and
/// growing the drawing would change the layout people already know. This
/// widens only what takes the tap: an invisible margin above and below the
/// control's own frame, cancelled for layout by a negative padding of the same
/// size — the frame the neighbours see stays exactly where it was.
///
/// Apply it INSIDE a `Button`'s label (on the label view): the content shape
/// is what the button hit-tests.
private struct TapTargetModifier: ViewModifier {
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geo in
                Color.clear.preference(key: TapTargetHeightKey.self, value: geo.size.height)
            })
            .modifier(TapTargetPadding(minHeight: minHeight))
    }
}

private struct TapTargetPadding: ViewModifier {
    let minHeight: CGFloat
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        let extra = max(0, (minHeight - height) / 2)
        content
            .onPreferenceChange(TapTargetHeightKey.self) { height = $0 }
            .padding(.vertical, extra)
            .contentShape(Rectangle())
            .padding(.vertical, -extra)
    }
}

private struct TapTargetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    /// Makes the tappable area at least `minHeight` tall (44 pt by default)
    /// without changing how the control looks or where it sits.
    func tapTarget(minHeight: CGFloat = 44) -> some View {
        modifier(TapTargetModifier(minHeight: minHeight))
    }
}
