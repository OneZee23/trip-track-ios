import SwiftUI

/// The trip detail's one and only top bar: back on the left, the author of
/// someone else's trip next to it, share and «…» fused into a single
/// segmented capsule on the right.
///
/// Two things changed from what this replaces. It is **pinned to the
/// screen** instead of riding the map, so «Назад» is still there after you
/// scroll into the trip's details — before, the only way back from the
/// bottom of a long trip was to scroll all the way up. And share and «…»
/// stopped being two separate floating circles a few points apart: two
/// islands with a gap read as debris, one capsule with a divider reads as
/// a control.
///
/// `progress` (0 at rest, 1 once the map has scrolled past) turns the glass
/// chrome into an ordinary opaque toolbar with the trip's name in it. The
/// bar's BACKGROUND never takes touches — only the controls do — because a
/// full-width hit-testing strip over a pannable map would eat the drag that
/// starts inside it.
struct TripDetailTopBar<Pill: View, Popover: View>: View {
    let progress: Double
    let topInset: CGFloat
    let title: String
    let language: LanguageManager.Language
    let showShare: Bool
    let shareDisabled: Bool
    let showActions: Bool
    @Binding var actionsPresented: Bool
    let onBack: () -> Void
    let onShare: () -> Void
    @ViewBuilder var pill: Pill
    @ViewBuilder var popover: Popover

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack {
            // The scrolled-state title. Fades in only at the end of the
            // morph, so it never competes with the map's own labels.
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .padding(.horizontal, 120)
                .opacity(max(0, (progress - 0.6) / 0.4))

            HStack(spacing: 8) {
                MapChromeButton(
                    systemImage: "chevron.left",
                    progress: progress,
                    accessibilityLabelText: AppStrings.back(language),
                    action: onBack
                )
                .accessibilityIdentifier("detail_back")

                pill
                    .opacity(max(0, 1 - progress * 2.5))
                    .allowsHitTesting(progress < 0.2)

                Spacer(minLength: 8)

                actionsCapsule
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, topInset + 8)
        .padding(.bottom, 8)
        .background(alignment: .top) { barBackground(c) }
    }

    /// Opaque only once the map is gone; invisible and untouchable while the
    /// route is behind it.
    private func barBackground(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            c.bg
            Rectangle()
                .fill(c.border)
                .frame(height: 0.5)
        }
        .opacity(progress)
        .allowsHitTesting(false)
    }

    /// Share + «…» in one capsule — but only when there are two of them.
    ///
    /// A segmented control of one segment is not a segmented control. Alone in
    /// the capsule, a cell kept the 44pt width it has for sitting next to a
    /// sibling, so the surface drew a 44×36 oval next to the 36pt circle of
    /// «Назад» — squat and visibly wider than its neighbour, which is what a
    /// stranger's public trip shows, since only its owner gets «…». One
    /// control is the plain map-chrome circle, the same token as every other
    /// button on this map.
    @ViewBuilder
    private var actionsCapsule: some View {
        if showShare, showActions {
            HStack(spacing: 0) {
                cell("square.and.arrow.up", label: AppStrings.share(language)) { onShare() }
                    .disabled(shareDisabled)
                    .accessibilityIdentifier("detail_share")

                Rectangle()
                    .fill(.white.opacity(progress > 0.5 ? 0 : 0.18))
                    .frame(width: 0.5, height: 18)

                cell("ellipsis", label: AppStrings.moreActions(language)) {
                    actionsPresented = true
                }
                .accessibilityIdentifier("detail_actions")
                .popover(isPresented: $actionsPresented, arrowEdge: .top) { popover }
            }
            .background {
                MapChromeSurface(progress: progress, shape: AnyShape(Capsule())) { Color.clear }
            }
        } else if showShare {
            MapChromeButton(
                systemImage: "square.and.arrow.up",
                progress: progress,
                accessibilityLabelText: AppStrings.share(language)
            ) {
                Haptics.tap()
                onShare()
            }
            .disabled(shareDisabled)
            .accessibilityIdentifier("detail_share")
        } else if showActions {
            MapChromeButton(
                systemImage: "ellipsis",
                progress: progress,
                accessibilityLabelText: AppStrings.moreActions(language)
            ) {
                Haptics.tap()
                actionsPresented = true
            }
            .accessibilityIdentifier("detail_actions")
            .popover(isPresented: $actionsPresented, arrowEdge: .top) { popover }
        }
    }

    private func cell(
        _ systemImage: String, label: String, action: @escaping () -> Void
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(progress > 0.5 ? c.text : .white)
                // 36 tall to match the circle token, 44 wide so the thumb
                // gets Apple's minimum even inside a segmented control.
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
