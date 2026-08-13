import SwiftUI

/// Which half of the follow toggle a social action button is showing.
enum SocialActionButtonKind {
    /// Accent fill, white label — the action still to be taken («Подписаться»,
    /// «В ответ»).
    case primary
    /// Card-alt fill with a hairline border — the state already reached
    /// («Подписан»), so it reads as done rather than as a second offer.
    case secondary
}

/// Canon geometry for the follow/action button (Figma `Button/Primary`
/// 117:969, `Button/Secondary` 117:298): 41pt tall, corner radius 14, 14pt
/// bold label, 18pt of horizontal and 12pt of vertical padding.
///
/// Discover, the notifications inbox and the public profile each grew their
/// own version of this control — 12pt semibold against 14pt semibold labels,
/// 7 / 8 / 10pt of vertical padding, two capsules and one 14pt rectangle. The
/// three screens push each other, so the same button changed shape as you
/// walked between them and every one of them came out 10–12pt shorter than the
/// design.
private struct SocialActionButtonModifier: ViewModifier {
    let kind: SocialActionButtonKind
    let colors: AppTheme.Colors
    let width: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return content
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            // Only bites where a pinned width leaves a long RU label short of
            // room; a button left to hug its label never scales.
            .minimumScaleFactor(0.9)
            .foregroundStyle(kind == .primary ? Color.white : colors.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(width: width)
            // Floor rather than a fixed height: padding alone already lands on
            // 41pt at the default text size, but a user running smaller type
            // would otherwise shrink the tap target with it.
            .frame(minHeight: 41)
            .background(kind == .primary ? AppTheme.accent : colors.cardAlt, in: shape)
            // `strokeBorder`, not `stroke`: a centred stroke puts half its
            // width outside the shape, which the enclosing horizontal
            // ScrollViews on these screens clip off.
            .overlay(
                shape.strokeBorder(
                    kind == .secondary ? colors.borderBright : Color.clear,
                    lineWidth: 1.5
                )
            )
    }
}

extension View {
    /// Applies the canon social action button chrome to a button's label.
    /// - Parameter width: pins the footprint so swapping the label
    ///   («Подписаться» ↔ «Подписан») can't shove the row around it. Omit to
    ///   hug the label, which is what the design does where nothing sits
    ///   beside the button.
    func socialActionButton(
        _ kind: SocialActionButtonKind,
        colors: AppTheme.Colors,
        width: CGFloat? = nil
    ) -> some View {
        modifier(SocialActionButtonModifier(kind: kind, colors: colors, width: width))
    }
}
