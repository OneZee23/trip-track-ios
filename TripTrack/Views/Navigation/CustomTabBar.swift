import SwiftUI

/// Floating glass tab bar — 6.1.0 redesign, 5 tabs: Лента / Карта / Запись /
/// Группы / Я. Spec is the Figma TabBar masters (page 88:2, section 90:2):
/// 74pt-tall pill, radius 30, glass background; regular tabs are a 20pt icon
/// over a 9pt label, active = filled glyph + accent, inactive = tertiary
/// grey; the center Record item is a 46pt accent disc with a white steering
/// wheel that stays INSIDE the pill (does not protrude), and its label stays
/// grey in every state — Record is an action, never an "active tab".
/// There is deliberately no underline/pill indicator — the active state is
/// purely the color + fill swap.
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        HStack(spacing: 4) {
            tabItem(tab: .home, label: AppStrings.feed(lang.language), c: c) { active in
                FeedTabIcon(filled: active)
            }
            tabItem(tab: .maps, label: AppStrings.tabMap(lang.language), c: c) { active in
                sfIcon(active ? "map.fill" : "map", active: active, size: 16)
            }

            recordItem(c: c)

            tabItem(tab: .groups, label: AppStrings.tabGroups(lang.language), c: c) { active in
                sfIcon(active ? "person.2.fill" : "person.2", active: active, size: 14)
            }
            tabItem(tab: .profile, label: AppStrings.tabMe(lang.language), c: c) { active in
                sfIcon(active ? "person.fill" : "person", active: active, size: 17)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: 380)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 30)
                    .stroke(c.glassBorder, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 3, y: 3)
        .padding(.horizontal, 11)
        // ContentView ignores the bottom safe area, so the pill is lifted
        // manually. Figma places the pill's bottom edge 14pt above the
        // physical screen bottom — the home indicator renders in that gap
        // over the app background.
        .padding(.bottom, 14)
    }

    // MARK: - Tab cells

    /// Standard peer tab — Лента, Карта, Группы, Я. The icon closure gets
    /// the active flag so callers can swap outline/filled variants.
    private func tabItem(
        tab: AppTab,
        label: String,
        c: AppTheme.Colors,
        @ViewBuilder icon: @escaping (Bool) -> some View
    ) -> some View {
        let isActive = selectedTab == tab

        return Button {
            if isActive && tab == .home {
                NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
            }
            withAnimation(.snappy(duration: 0.22)) {
                selectedTab = tab
            }
            Haptics.tap()
        } label: {
            VStack(spacing: 3) {
                icon(isActive)
                    .frame(width: 20, height: 20)
                tabLabel(label, tint: isActive ? AppTheme.accent : c.textTertiary)
            }
            .foregroundStyle(isActive ? AppTheme.accent : c.textTertiary)
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab_\(tab.rawValue)")
    }

    /// Center Record item: 46pt accent disc + steering wheel, subtle orange
    /// glow. Label is ALWAYS tertiary grey (Figma: record is an action, not
    /// a tab that reads "active"). The bar is hidden on the Record tab
    /// itself, so no recording/stop state is needed here.
    private func recordItem(c: AppTheme.Colors) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                selectedTab = .record
            }
            Haptics.tap()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 46, height: 46)
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 3, y: 1)
                    SteeringWheelIcon()
                        .foregroundStyle(.white)
                }
                tabLabel(AppStrings.record(lang.language), tint: c.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab_record")
    }

    /// Glyph sizes are tuned per symbol so every icon's VISIBLE bounds match
    /// the Figma 20×20 box — SF Symbols pad differently (person.2 renders
    /// much wider than person at the same point size).
    private func sfIcon(_ name: String, active: Bool, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .regular))
            .symbolEffect(.bounce, value: active)
    }

    private func tabLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The record-disc steering wheel from Figma: thin-stroke outline — rim +
/// three spokes (left/right/down) + a small filled hub. SF's `steeringwheel`
/// is a heavy filled automotive glyph and reads too bold at 24pt, so the
/// Figma geometry is drawn directly (24×24 box, 2.5pt round-cap strokes).
struct SteeringWheelIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(lineWidth: 2.5)
            Path { p in
                let c = CGPoint(x: 12, y: 12)
                p.move(to: c); p.addLine(to: CGPoint(x: 3.2, y: 12))
                p.move(to: c); p.addLine(to: CGPoint(x: 20.8, y: 12))
                p.move(to: c); p.addLine(to: CGPoint(x: 12, y: 20.8))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            Circle()
                .frame(width: 5, height: 5)
        }
        .frame(width: 24, height: 24)
    }
}

/// The Лента glyph from Figma has no SF Symbol equivalent: a rounded card
/// with a horizontal caption bar. Outline variant = stroked 12.4pt rect +
/// bar; filled variant = 14pt filled rect with a white bar knocked out.
/// Drawn in a fixed 20×20 box to match the other tab icons.
struct FeedTabIcon: View {
    var filled: Bool

    var body: some View {
        // Bar offsets from the Figma SVG: bar center sits at ~62% of the
        // card height — a clear gap above the card's bottom edge, not
        // merged into it.
        ZStack {
            if filled {
                RoundedRectangle(cornerRadius: 3.5)
                    .frame(width: 14, height: 14)
                RoundedRectangle(cornerRadius: 0.9)
                    .fill(.white)
                    .frame(width: 10, height: 1.8)
                    .offset(y: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 2.7)
                    .strokeBorder(lineWidth: 1.6)
                    .frame(width: 13.5, height: 13.5)
                RoundedRectangle(cornerRadius: 0.8)
                    .frame(width: 9.5, height: 1.6)
                    .offset(y: 1.2)
            }
        }
        .frame(width: 20, height: 20)
    }
}
