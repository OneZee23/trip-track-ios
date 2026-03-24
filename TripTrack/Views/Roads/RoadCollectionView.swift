import SwiftUI

struct RoadCollectionView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    let roadManager: RoadCollectionManager

    @State private var roads: [RoadCard] = []
    @State private var selectedRarity: RoadRarity?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru
        let filtered = selectedRarity == nil ? roads : roads.filter { $0.rarity == selectedRarity }

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Stats header
                    HStack(spacing: 16) {
                        VStack {
                            Text("\(roads.count)")
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundStyle(c.text)
                            Text(isRu ? "дорог" : "roads")
                                .font(.system(size: 11))
                                .foregroundStyle(c.textTertiary)
                        }

                        let mastered = roads.filter { $0.level == .mastered }.count
                        if mastered > 0 {
                            VStack {
                                Text("\(mastered)")
                                    .font(.system(size: 24, weight: .heavy))
                                    .foregroundStyle(AppTheme.accent)
                                Text(isRu ? "освоено" : "mastered")
                                    .font(.system(size: 11))
                                    .foregroundStyle(c.textTertiary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    // Rarity filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterPill(label: isRu ? "Все" : "All", isActive: selectedRarity == nil, c: c) {
                                selectedRarity = nil
                            }
                            ForEach(RoadRarity.allCases, id: \.self) { rarity in
                                let count = roads.filter { $0.rarity == rarity }.count
                                if count > 0 {
                                    filterPill(
                                        label: "\(rarity.title(lang.language)) (\(count))",
                                        isActive: selectedRarity == rarity,
                                        c: c
                                    ) {
                                        selectedRarity = rarity
                                    }
                                }
                            }
                        }
                    }

                    // Road cards
                    if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "road.lanes")
                                .font(.system(size: 32))
                                .foregroundStyle(c.textTertiary)
                            Text(isRu
                                ? "Запишите поездку, чтобы открыть дорогу"
                                : "Record a trip to discover a road")
                                .font(.system(size: 14))
                                .foregroundStyle(c.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(filtered) { road in
                            RoadCardView(road: road)
                        }
                    }
                }
                .padding(16)
            }
            .background(c.bg)
            .navigationTitle(isRu ? "Коллекция дорог" : "Road Collection")
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
        .onAppear { roads = roadManager.fetchRoads() }
    }

    private func filterPill(label: String, isActive: Bool, c: AppTheme.Colors, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? .white : c.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isActive ? AppTheme.accent : c.cardAlt, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Road Card View

struct RoadCardView: View {
    let road: RoadCard
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let nextLevel = road.level.nextLevel
        let progress = road.progressToNextLevel

        VStack(alignment: .leading, spacing: 10) {
            // Header: name + rarity pill
            HStack {
                Text(road.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)

                Spacer()

                Text(road.rarity.title(lang.language))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(road.rarity.color, in: Capsule())
            }

            // Stats row
            HStack(spacing: 16) {
                Label(String(format: "%.1f km", road.distanceKm), systemImage: "arrow.left.and.right")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)

                Label(road.level.title(lang.language), systemImage: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(road.level.color)

                Label("×\(road.timesDriven)", systemImage: "repeat")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)

                Spacer()
            }

            // Progress to next level
            if let next = nextLevel {
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(c.cardAlt).frame(height: 5)
                            Capsule()
                                .fill(road.level.color)
                                .frame(width: max(2, geo.size.width * progress), height: 5)
                        }
                    }
                    .frame(height: 5)

                    Text("\(road.timesDriven)/\(next.minDrives)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                        .fixedSize()
                }
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }
}
