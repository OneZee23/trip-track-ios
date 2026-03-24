import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var pulseAnimation = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        HStack(spacing: 0) {
            // Feed tab
            tabItem(
                index: 0,
                icon: "flag",
                iconFilled: "flag.fill",
                label: AppStrings.feed(lang.language),
                c: c
            )

            // Record tab — center, raised circle
            Button {
                let isOnRecordingTab = selectedTab == 1
                if mapVM.isRecording && isOnRecordingTab {
                    mapVM.toggleRecording()
                    Haptics.success()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = 1
                    }
                    Haptics.tap()
                }
            } label: {
                let showStop = mapVM.isRecording && selectedTab == 1
                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(showStop ? AppTheme.red : AppTheme.accent)
                            .frame(width: 48, height: 48)
                            .shadow(color: (showStop ? AppTheme.red : AppTheme.accent).opacity(0.3), radius: 3, y: 1)
                            .scaleEffect(selectedTab == 1 ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)
                            .animation(.easeInOut(duration: 0.3), value: showStop)

                        Image(systemName: showStop ? "stop.fill" : "car.fill")
                            .font(.system(size: showStop ? 18 : 20))
                            .foregroundStyle(.white)
                            .animation(.easeInOut(duration: 0.2), value: showStop)
                    }
                    .overlay(alignment: .topTrailing) {
                        if mapVM.isRecording && !showStop {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                                .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                                .opacity(pulseAnimation ? 0.6 : 1.0)
                                .animation(
                                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                    value: pulseAnimation
                                )
                                .onAppear { pulseAnimation = true }
                                .onDisappear { pulseAnimation = false }
                                .offset(x: 2, y: -2)
                        }
                    }
                    .offset(y: -6)

                    Text(showStop
                         ? (lang.language == .ru ? "Стоп" : "Stop")
                         : AppStrings.record(lang.language))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(showStop ? AppTheme.red : (selectedTab == 1 ? AppTheme.accent : c.textTertiary))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Regions tab
            tabItem(
                index: 2,
                icon: "map",
                iconFilled: "map.fill",
                label: AppStrings.regions(lang.language),
                c: c
            )

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 360)
        .background {
            ZStack {
                // Glass material
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)

                // Border
                RoundedRectangle(cornerRadius: 28)
                    .stroke(c.glassBorder, lineWidth: 1)

                // Specular shine overlay
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(scheme == .dark ? 0.12 : 0.6),
                                .white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.6)
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 6, y: 3)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    @State private var tabBounce: [Int: Bool] = [:]

    private func tabItem(index: Int, icon: String, iconFilled: String, label: String, c: AppTheme.Colors) -> some View {
        let isActive = selectedTab == index

        return Button {
            if isActive && index == 0 {
                // Re-tap on Feed → scroll to top
                NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
            Haptics.tap()
            // Bounce the icon
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                tabBounce[index] = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                tabBounce[index] = false
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isActive ? iconFilled : icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? AppTheme.accent : c.textTertiary)
                    .scaleEffect(tabBounce[index] == true ? 1.2 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: tabBounce[index])

                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? AppTheme.accent : c.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
