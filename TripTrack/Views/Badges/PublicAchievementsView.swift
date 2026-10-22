import SwiftUI

// MARK: - Чужие достижения (0.9.1)

/// Somebody else's whole collection: the «Достижения» screen of the Я tab,
/// fed the ids the profile fetched from `/users/:id/badges`.
///
/// A tile opens the same `BadgeDetailOverlay` a badge opens on that person's
/// profile, not the Я stack's `AchievementDetailView` — the detail is pushed
/// there through `MeDest.achievement`, and somebody else's profile is shown
/// in five different stacks that would each need a route for it.
struct PublicAchievementsView: View {
    let badgeIds: [String]
    let ownerName: String?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var selectedBadge: Badge?

    var body: some View {
        AchievementsView(unlockedIds: badgeIds, ownerName: ownerName) { badge in
            selectedBadge = badge
        }
        .overlay {
            if let badge = selectedBadge {
                BadgeDetailOverlay(
                    badge: badge,
                    isUnlocked: badgeIds.contains(badge.id),
                    language: lang.language,
                    colorScheme: scheme,
                    onDismiss: { selectedBadge = nil }
                )
            }
        }
    }
}
