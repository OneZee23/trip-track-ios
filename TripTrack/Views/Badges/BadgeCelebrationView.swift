import SwiftUI

struct BadgeCelebrationView: View {
    let badges: [(badge: Badge, count: Int)]
    let onDismiss: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var currentIndex = 0
    @State private var appear = false
    @State private var glowPulse = false

    private var current: (badge: Badge, count: Int) {
        badges[currentIndex]
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let badge = current.badge
        let count = current.count

        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            ConfettiView()
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Badge icon with glow
                ZStack {
                    // Glow rings
                    Circle()
                        .fill(badge.color.opacity(0.15))
                        .frame(width: 180, height: 180)
                        .scaleEffect(glowPulse ? 1.1 : 0.9)

                    Circle()
                        .fill(badge.color.opacity(0.08))
                        .frame(width: 220, height: 220)
                        .scaleEffect(glowPulse ? 1.15 : 0.85)

                    // Main circle
                    Circle()
                        .fill(badge.color.opacity(0.2))
                        .frame(width: 130, height: 130)

                    Image(systemName: badge.icon)
                        .font(.system(size: 56))
                        .foregroundStyle(badge.color)
                }
                .scaleEffect(appear ? 1 : 0.3)
                .opacity(appear ? 1 : 0)

                // Subtitle
                Text(AppStrings.achievementUnlocked(lang.language))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(badge.color)
                    .textCase(.uppercase)
                    .tracking(3)
                    .opacity(appear ? 1 : 0)

                // Badge name
                Text(badge.title(lang.language))
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(appear ? 1 : 0)

                // Description
                Text(badge.description(lang.language))
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(appear ? 1 : 0)

                // Earn count for repeatable badges
                if badge.isRepeatable && count > 0 {
                    Text(AppStrings.earnedTimes(lang.language, count: count))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(badge.color.opacity(0.15), in: Capsule())
                        .opacity(appear ? 1 : 0)
                }

                Spacer()

                // Continue button
                Button {
                    advanceOrDismiss()
                } label: {
                    Text(AppStrings.continueButton(lang.language))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(badge.color, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)

                // Page indicator for multiple badges
                if badges.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<badges.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 48)
        }
        .onAppear {
            animateIn()
        }
    }

    private func animateIn() {
        appear = false
        glowPulse = false

        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            appear = true
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
        Haptics.success()
    }

    private func advanceOrDismiss() {
        if currentIndex < badges.count - 1 {
            withAnimation(.easeOut(duration: 0.2)) {
                appear = false
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                currentIndex += 1
                animateIn()
            }
        } else {
            onDismiss()
        }
    }
}
