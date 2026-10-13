import SwiftUI

struct BadgeCelebrationView: View {
    let badges: [(badge: Badge, count: Int)]
    let onDismiss: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @State private var currentIndex = 0
    @State private var appear = false
    @State private var glowPulse = false
    /// Список, с которым экран открылся. Родитель очищает `pendingBadges`
    /// ДО того, как закрывающая анимация `fullScreenCover` отыграла, и тело
    /// перерисовывается уже с пустым массивом — `badges[0]` ронял
    /// приложение (Sentry APPLE-IOS-3, 8 падений в 0.6.7–0.8.1,
    /// `BadgeCelebrationView.swift:19`). Снимок держит последний кадр целым.
    @State private var shown: [(badge: Badge, count: Int)] = []

    /// Что показывать: снимок, иначе живой список; индекс зажат в границы.
    /// `nil` — показывать нечего, и тело рисует пустой фон, а не падает.
    static func item(at index: Int, shown: [(badge: Badge, count: Int)],
                     live: [(badge: Badge, count: Int)]) -> (badge: Badge, count: Int)? {
        let list = shown.isEmpty ? live : shown
        guard !list.isEmpty else { return nil }
        return list[min(max(index, 0), list.count - 1)]
    }

    private var list: [(badge: Badge, count: Int)] { shown.isEmpty ? badges : shown }

    var body: some View {
        if let current = Self.item(at: currentIndex, shown: shown, live: badges) {
            content(badge: current.badge, count: current.count)
        } else {
            Color.black.opacity(0.8).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(badge: Badge, count: Int) -> some View {

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

                    // Свечение вокруг осталось, а плашка под значком ушла:
                    // диск у него свой.
                    BadgeArt(badge: badge, side: 130)
                }
                .scaleEffect(appear ? 1 : 0.3)
                .opacity(appear ? 1 : 0)

                // Subtitle
                Text(AppStrings.achievementUnlocked(lang.language))
                    .font(.inter(14, weight: .bold))
                    .foregroundStyle(badge.color)
                    .textCase(.uppercase)
                    .tracking(3)
                    .opacity(appear ? 1 : 0)

                // Badge name
                Text(badge.title(lang.language))
                    .font(.inter(28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(appear ? 1 : 0)

                // Description
                Text(badge.description(lang.language, unit: distanceUnit))
                    .font(.inter(16))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(appear ? 1 : 0)

                // Earn count for repeatable badges
                if badge.isRepeatable && count > 0 {
                    Text(AppStrings.earnedTimes(lang.language, count: count))
                        .font(.inter(15, weight: .semibold))
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
                        .font(.inter(18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(badge.color, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
                .accessibilityIdentifier("celebration_continue")

                // Page indicator for multiple badges
                if list.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<list.count, id: \.self) { i in
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
            if shown.isEmpty { shown = badges }
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
        if currentIndex < list.count - 1 {
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
