import SwiftUI

/// The badge card (Figma 117:1547).
struct BadgeDetailOverlay: View {
    let badge: Badge
    let isUnlocked: Bool
    let language: LanguageManager.Language
    let colorScheme: ColorScheme
    var earnCount: Int? = nil
    var lastEarnedDate: Date? = nil
    /// What the owner actually did to earn it («47.3 км») — the canon puts the
    /// personal number under the generic rule, because «проедьте 42.2 км» is
    /// the badge and «47.3 км» is the memory.
    var recordValue: String? = nil
    /// Trip this badge was earned on, for the «Получен … · Дача и обратно» line.
    var earnedOnTripTitle: String? = nil
    let onDismiss: () -> Void
    @State private var appear = false

    var body: some View {
        let c = AppTheme.colors(for: colorScheme)
        let lng = language

        ZStack {
            Color.black.opacity(appear ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 16) {
                // Large badge icon. The two rings around it were ours, not the
                // canon's (117:1572 is a single 96pt disc) — and at 88pt with
                // a 40pt glyph the medallion read as a list cell blown up
                // rather than as the card's subject.
                ZStack {
                    Circle()
                        .fill(isUnlocked ? badge.color.opacity(0.15) : c.cardAlt)
                        .frame(width: 96, height: 96)

                    if isUnlocked {
                        Image(systemName: badge.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(badge.color)
                    } else if badge.isHidden {
                        Image(systemName: "questionmark")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(c.textTertiary)
                    } else {
                        Image(systemName: badge.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(c.textTertiary.opacity(0.5))
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(c.textTertiary)
                    }
                }

                // The badge's own colour is the card's only identity accent
                // (117:1575) — in the neutral text token every achievement
                // looked like the same achievement.
                // Two lines and a floor on the scale: «Воскресный водитель»
                // at 22pt heavy runs the full width of the card, and with
                // nothing to fall back on a longer name would either clip or
                // stretch the card into a slab.
                Text(isUnlocked || !badge.isHidden ? badge.title(language) : "???")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(isUnlocked ? badge.color : c.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 4)

                Text(isUnlocked || !badge.isHidden
                    ? badge.description(language)
                    : (AppStrings.badgeDetailHiddenAchievement(lng)))
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)

                // «Не получено» + the category are what a LOCKED card has
                // instead of a story. On an unlocked one the canon (117:1567)
                // draws neither: a green «Получено» pill under a card that
                // already says «Получен 14 мая» was the same fact twice, and
                // the category is a filter from the grid you arrived from.
                if !isUnlocked {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                        Text(AppStrings.badgeDetailLocked(lng))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(c.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(c.cardAlt, in: Capsule())

                    Text(badge.category.title(language))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }

                if isUnlocked, let recordValue {
                    Text(recordValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(badge.color)
                }

                if isUnlocked, let date = lastEarnedDate {
                    VStack(spacing: 3) {
                        Text(earnHeadline(date: date))
                        if let trip = earnedOnTripTitle, !trip.isEmpty, !isRepeated {
                            Text(trip)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                    .multilineTextAlignment(.center)
                }

                // No «Поделиться» here. The button shared the TRIP, not
                // the achievement — you tapped a badge and handed someone
                // your drive. Sharing a badge on its own is a different
                // feature (its own card, its own image); until that exists,
                // the honest thing is to offer nothing rather than
                // something adjacent.
            }
            .padding(24)
            .padding(.top, 8)
            .frame(maxWidth: 300)
            .overlay(alignment: .topTrailing) {
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(c.cardAlt))
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityIdentifier("badge_close")
                .accessibilityLabel(AppStrings.close(language))
            }
            .background(c.bg, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            .scaleEffect(appear ? 1 : 0.8)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appear = true
            }
        }
    }

    /// Earned more than once — so no single trip can honestly be called THE
    /// one it came from.
    private var isRepeated: Bool {
        badge.isRepeatable && (earnCount ?? 0) > 1
    }

    /// One line about earning it, and the trip on a second line under it —
    /// never «Получен 9 августа 2026 · 14 Jun, 12:31 · ×15» on one run, which
    /// is what folding all three together produced: a Russian date, an
    /// auto-generated English trip name and a bare ×15 wrapping onto a line
    /// of its own.
    ///
    /// A repeatable badge earned fifteen times drops the trip entirely. The
    /// card only ever knows the LAST one, and naming it implies it was
    /// special.
    private func earnHeadline(date: Date) -> String {
        guard isRepeated, let count = earnCount else {
            return AppStrings.badgeEarnedOn(language, date: date, tripTitle: nil)
        }
        let times = AppStrings.earnedTimes(language, count: count)
        let last = AppStrings.badgeLastEarned(language, date: date)
        return "\(times) · \(last)"
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { appear = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            onDismiss()
        }
    }
}
