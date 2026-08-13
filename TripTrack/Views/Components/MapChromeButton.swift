import SwiftUI

/// The one control token that sits on a map: a 36pt glass circle inside a
/// 44pt hit area.
///
/// The trip detail used to draw its map controls three different ways —
/// 34pt at 40% black, 44pt at 45%, and a 32pt legend pill — which is what
/// made the corner look assembled rather than designed. One token fixes the
/// sizes AND the touch targets: the circle you see is 36, the rectangle
/// that catches your thumb is 44, which is the Apple minimum the old 34pt
/// buttons missed.
///
/// `progress` exists for the pinned top bar, which starts as glass over the
/// map and turns into an opaque toolbar as the map scrolls away. Two full
/// layers cross-fade rather than one colour interpolating: a material can't
/// be tweened to a solid colour, and trying looks like dirt.
struct MapChromeButton: View {
    let systemImage: String
    /// 0 = glass over the map, 1 = opaque control on the page background.
    var progress: Double = 0
    var accessibilityLabelText: String? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            MapChromeSurface(progress: progress) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(glyphColor)
            }
            .frame(width: 36, height: 36)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText ?? "")
    }

    private var glyphColor: Color {
        let c = AppTheme.colors(for: scheme)
        // Same cross-fade as the surface: white while the map is behind it,
        // the theme's text colour once the toolbar is opaque.
        return progress > 0.5 ? c.text : .white
    }
}

/// The glass-to-solid backdrop shared by `MapChromeButton` and the segmented
/// action capsule, so the two can never drift apart mid-fade.
struct MapChromeSurface<Content: View>: View {
    var progress: Double = 0
    var shape: AnyShape = AnyShape(Circle())
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        return ZStack {
            shape
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay { shape.stroke(.white.opacity(0.14), lineWidth: 0.5) }
                .opacity(1 - progress)
            shape
                .fill(c.cardAlt)
                .opacity(progress)
            content
        }
    }
}
