import SwiftUI

/// Floating glass tab bar. Earlier version had a raised 48pt Record disc in
/// the center — it looked toy-like next to the calm Feed/Regions tabs and
/// fought the overall "cozy companion" register of the app. This revision
/// makes all three tabs equal peers: same icon size, same label, same
/// vertical baseline. Record's primacy is expressed through color (accent
/// idle, red while recording) and a shared `matchedGeometryEffect` underline
/// that slides between active tabs. The raised disc and the specular
/// white-gradient shine are gone.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Namespace private var underline

    /// Device-dependent safe-area bottom inset. ContentView intentionally
    /// does `.ignoresSafeArea(edges: .bottom)` so Feed cards can scroll
    /// under the floating pill, but that means we need to lift the bar
    /// manually — a hardcoded small bottom padding dropped the pill into
    /// the home-indicator zone on pre-Dynamic-Island devices (iPhone 12).
    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let recording = mapVM.isRecording

        HStack(spacing: 0) {
            tabItem(
                index: 0,
                icon: "flag",
                iconFilled: "flag.fill",
                label: AppStrings.feed(lang.language),
                activeTint: AppTheme.accent,
                c: c
            )

            recordTab(recording: recording, c: c)

            tabItem(
                index: 2,
                icon: "map",
                iconFilled: "map.fill",
                label: AppStrings.regions(lang.language),
                activeTint: AppTheme.accent,
                c: c
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 360)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28)
                    .stroke(c.glassBorder, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.05), radius: 4, y: 2)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        // Continue the pill's glass material all the way to the screen
        // bottom so the area between the pill and the home indicator
        // doesn't read as a separate dark "floor". Matches what Apple's
        // native tab bars do — the pill appears to float, but the
        // surface behind it is visually continuous.
        .background(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: safeAreaBottom + 24)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Tab cells

    /// Standard peer tab — Feed and Regions use this directly. Record also
    /// routes through the same layout so the three items have identical
    /// metrics; only the tap behavior and active tint differ.
    private func tabItem(
        index: Int,
        icon: String,
        iconFilled: String,
        label: String,
        activeTint: Color,
        c: AppTheme.Colors
    ) -> some View {
        let isActive = selectedTab == index

        return Button {
            if isActive && index == 0 {
                NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
            }
            withAnimation(.snappy(duration: 0.22)) {
                selectedTab = index
            }
            Haptics.tap()
        } label: {
            tabContent(
                isActive: isActive,
                iconName: isActive ? iconFilled : icon,
                label: label,
                activeTint: activeTint,
                c: c,
                indexForUnderline: index
            )
        }
        .buttonStyle(.plain)
    }

    /// Record tab has a dedicated builder because its icon, label, and tint
    /// swap between idle and recording states. The symbol uses
    /// `.contentTransition(.symbolEffect(.replace))` so `car.fill` morphs to
    /// `stop.fill` smoothly instead of a cut.
    private func recordTab(recording: Bool, c: AppTheme.Colors) -> some View {
        let isActive = selectedTab == 1
        let showStop = recording && isActive
        let tint: Color = showStop ? AppTheme.red : AppTheme.accent
        let iconName = showStop ? "stop.fill" : "car.fill"
        let label = showStop
            ? (lang.language == .ru ? "Стоп" : "Stop")
            : AppStrings.record(lang.language)

        return Button {
            if recording && isActive {
                mapVM.toggleRecording()
                Haptics.success()
            } else {
                withAnimation(.snappy(duration: 0.22)) {
                    selectedTab = 1
                }
                Haptics.tap()
            }
        } label: {
            tabContent(
                isActive: isActive,
                iconName: iconName,
                label: label,
                activeTint: tint,
                c: c,
                indexForUnderline: 1
            )
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    /// Shared icon + label + underline block so all three tabs sit on the
    /// exact same baseline. `matchedGeometryEffect` animates the 3pt accent
    /// underline sliding between the active tab's icon across taps.
    @ViewBuilder
    private func tabContent(
        isActive: Bool,
        iconName: String,
        label: String,
        activeTint: Color,
        c: AppTheme.Colors,
        indexForUnderline: Int
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 22))
                .foregroundStyle(isActive ? activeTint : c.textTertiary)
                .symbolEffect(.bounce, value: isActive)
                .frame(height: 24)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? activeTint : c.textTertiary)
                .lineLimit(1)

            ZStack {
                if isActive {
                    Capsule()
                        .fill(activeTint)
                        .frame(width: 18, height: 3)
                        .matchedGeometryEffect(id: "tab-underline", in: underline)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 18, height: 3)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
