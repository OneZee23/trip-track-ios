import SwiftUI

/// Which half of the follow toggle a social action button is showing.
enum SocialActionButtonKind {
    /// Accent fill, white label — the action still to be taken («Подписаться»,
    /// «В ответ»).
    case primary
    /// The state already reached («Подписан»): an accent TINT with accent ink
    /// and no border (canon 1635:145). It shipped once as a bordered grey
    /// chip, which is the chrome of a control you have not touched — the whole
    /// point of this half is that you already did.
    case done
    /// A pill that stands where an action would be but is not one — «Это вы»
    /// on your own profile (canon 580:438). Capsule, quiet fill, secondary
    /// ink, no border: same footprint as the follow button so switching
    /// between your preview and a stranger's profile moves nothing, but
    /// nothing about it invites a tap.
    case inert
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
        content
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            // Only bites where a pinned width leaves a long RU label short of
            // room; a button left to hug its label never scales.
            .minimumScaleFactor(0.9)
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(width: width)
            // Floor rather than a fixed height: padding alone already lands on
            // 41pt at the default text size, but a user running smaller type
            // would otherwise shrink the tap target with it.
            .frame(minHeight: 41)
            .background(fill, in: shape)
    }

    /// The inert pill is canon's one capsule here; everything else keeps the
    /// 14pt radius the design system draws for buttons.
    private var shape: AnyShape {
        kind == .inert
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var fill: Color {
        switch kind {
        case .primary: return AppTheme.accent
        case .done:    return AppTheme.accentDim
        case .inert:   return colors.cardAlt
        }
    }

    private var ink: Color {
        switch kind {
        case .primary: return .white
        case .done:    return AppTheme.accent
        case .inert:   return colors.textSecondary
        }
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
