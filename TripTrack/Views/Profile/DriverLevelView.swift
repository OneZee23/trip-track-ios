import SwiftUI

struct DriverLevelView: View {
    let xp: Int
    let level: Int
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var showInfo = false

    private var rank: DriverRank { DriverRank.from(level: level) }
    private var progress: Double { LevelSystem.progressToNextLevel(xp: xp, level: level) }
    private var xpCurrent: Int { xp - LevelSystem.xpForLevel(level) }
    private var xpNeeded: Int { LevelSystem.xpForNextLevel(level) - LevelSystem.xpForLevel(level) }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Rank icon
                ZStack {
                    Circle()
                        .fill(rank.color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: rank.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(rank.color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(rank.title(lang.language))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(c.text)

                        Spacer()

                        Text("LVL \(level)")
                            .font(.custom("PressStart2P-Regular", size: 10))
                            .foregroundStyle(rank.color)
                    }

                    // XP progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(c.cardAlt)
                                .frame(height: 8)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [rank.color, rank.color.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * progress), height: 8)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        if level < LevelSystem.maxLevel {
                            Text("\(xpCurrent) / \(xpNeeded) XP")
                                .font(.system(size: 11))
                                .foregroundStyle(c.textTertiary)
                        } else {
                            Text("MAX")
                                .font(.custom("PressStart2P-Regular", size: 9))
                                .foregroundStyle(rank.color)
                        }

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showInfo.toggle() }
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(c.textTertiary)
                        }
                    }
                }
            }
            .padding(14)

            // Info section
            if showInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle().fill(c.border).frame(height: 1)

                    Text(isRu ? "Как получать опыт:" : "How to earn XP:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(c.textSecondary)

                    xpInfoRow(icon: "road.lanes", text: isRu ? "1 XP за каждый км" : "1 XP per km", c: c)
                    xpInfoRow(icon: "calendar", text: isRu ? "+20 XP за первую поездку дня" : "+20 XP for first trip of the day", c: c)
                    xpInfoRow(icon: "map", text: isRu ? "+50 XP за новый регион" : "+50 XP for a new region", c: c)
                    xpInfoRow(icon: "arrow.right", text: isRu ? "×2 за поездки 200+ км" : "×2 for trips 200+ km", c: c)

                    Text(isRu ? "Ранги: Новичок → Водитель → Путешественник → Исследователь → Штурман → Дальнобойщик → Легенда"
                         : "Ranks: Beginner → Driver → Traveler → Explorer → Navigator → Trucker → Legend")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .surfaceCard(cornerRadius: 16)
    }

    private func xpInfoRow(icon: String, text: String, c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(c.text)
        }
    }
}
