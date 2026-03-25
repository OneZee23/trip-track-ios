import SwiftUI

struct BadgesView: View {
    let trips: [Trip]
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBadge: Badge?
    @State private var unlocked: Set<String> = []
    @State private var sections: [BadgeSection] = []
    @State private var hiddenCount: Int = 0
    @State private var showHiddenInfo: Bool = false
    @State private var earnCounts: [String: Int] = [:]
    @State private var lastEarnedDates: [String: Date] = [:]

    struct BadgeSection: Identifiable {
        let id: String
        let category: BadgeCategory
        let badges: [(badge: Badge, isUnlocked: Bool)]
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let totalUnlocked = unlocked.count
        let totalVisible = sections.reduce(0) { $0 + $1.badges.count }

        NavigationStack {
            ScrollView {
                Text("\(totalUnlocked)/\(totalVisible)")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 8)

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.category.title(lang.language))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(c.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(section.badges, id: \.badge.id) { item in
                                BadgeCellView(badge: item.badge, isUnlocked: item.isUnlocked, earnCount: earnCounts[item.badge.id] ?? 0)
                                    .onTapGesture {
                                        Haptics.tap()
                                        selectedBadge = item.badge
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if hiddenCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showHiddenInfo.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 12))
                            Text(lang.language == .ru
                                ? "\(hiddenCount) скрытых достижений"
                                : "\(hiddenCount) hidden achievements")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(c.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)

                    if showHiddenInfo {
                        Text(lang.language == .ru
                            ? "Скрытые достижения открываются за особые действия: ночные поездки, горные маршруты, зимние путешествия и другие сюрпризы. Продолжайте ездить — они появятся!"
                            : "Hidden achievements unlock for special actions: night drives, mountain routes, winter trips and other surprises. Keep driving — they will appear!")
                            .font(.system(size: 13))
                            .foregroundStyle(c.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Spacer().frame(height: 24)
                }
            }
            .background(c.bg)
            .navigationTitle(AppStrings.badges(lang.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                    }
                }
            }
            .toolbarBackground(c.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { buildSections() }
        .overlay {
            if let badge = selectedBadge {
                BadgeDetailOverlay(
                    badge: badge,
                    isUnlocked: unlocked.contains(badge.id),
                    language: lang.language,
                    colorScheme: scheme,
                    earnCount: badge.isRepeatable ? BadgeManager.earnCount(for: badge.id) : nil,
                    lastEarnedDate: lastEarnedDates[badge.id],
                    onDismiss: { selectedBadge = nil }
                )
            }
        }
    }

    private func buildSections() {
        let stats = BadgeManager.computeStats(from: trips)
        let unlockedSet = Set(BadgeManager.unlockedBadges(for: stats).map(\.id))
        unlocked = unlockedSet

        var result: [BadgeSection] = []
        for category in BadgeCategory.allCases {
            let badges = Badge.all
                .filter { $0.category == category }
                .filter { !$0.isHidden || unlockedSet.contains($0.id) }
                .map { (badge: $0, isUnlocked: unlockedSet.contains($0.id)) }
            if !badges.isEmpty {
                result.append(BadgeSection(id: category.rawValue, category: category, badges: badges))
            }
        }
        sections = result
        hiddenCount = Badge.all.filter { $0.isHidden && !unlockedSet.contains($0.id) }.count
        earnCounts = BadgeManager.allEarnCounts()

        // Compute last earned dates from trips
        var dates: [String: Date] = [:]
        for trip in trips {
            for id in trip.earnedBadgeIds {
                if dates[id] == nil || trip.startDate > dates[id]! {
                    dates[id] = trip.startDate
                }
            }
        }
        lastEarnedDates = dates
    }
}

// MARK: - Badge Cell

private struct BadgeCellView: View {
    let badge: Badge
    let isUnlocked: Bool
    let earnCount: Int
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let count = earnCount

        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? badge.color.opacity(0.15) : c.cardAlt)
                        .frame(width: 56, height: 56)

                    if isUnlocked {
                        Image(systemName: badge.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(badge.color)
                    } else if badge.isHidden {
                        Image(systemName: "questionmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(c.textTertiary)
                    } else {
                        Image(systemName: badge.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(c.textTertiary)

                        Circle()
                            .fill(c.card.opacity(0.5))
                            .frame(width: 56, height: 56)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(c.textTertiary)
                    }
                }

                if isUnlocked && badge.isRepeatable && count > 1 {
                    Text("x\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(badge.color, in: Capsule())
                        .offset(x: 4, y: 4)
                }
            }

            Text(isUnlocked || !badge.isHidden
                ? badge.title(lang.language)
                : "???")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isUnlocked ? c.text : c.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(c.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

