import SwiftUI
import MapKit

/// Read-only detail view for a trip from the social feed.
/// Unlike the local TripDetailView, it shows a friend's trip — no editing,
/// no deletion, no photo picker. Just the map, metrics, reactions row, and share.
struct SocialTripDetailView: View {
    let trip: SocialFeedTrip
    var onReact: ((String) -> Void)?
    var onShare: (() -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var selectedAuthor: SocialAuthor?
    @State private var showReport = false
    @State private var reactionEntries: [SocialReactionEntry] = []
    @State private var isLoadingReactions = false

    private var mapBaseHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.bounds.height ?? 844) * 0.42
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        ScrollView {
            VStack(spacing: 0) {
                mapSection(c)
                    .frame(height: mapBaseHeight)

                VStack(alignment: .leading, spacing: 16) {
                    authorRow(c, isRu: isRu)
                    titleSection(c)
                    metricsGrid(c, isRu: isRu)
                    if !trip.badgeIds.isEmpty {
                        TripBadgesRow(badgeIds: trip.badgeIds, maxVisible: 6, size: 26)
                            .padding(.top, 2)
                    }
                    reactionsRow(c)
                    reactionsBreakdown(c)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 80)
            }
        }
        .background(c.bg)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { NavBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Haptics.tap()
                        onShare?()
                    } label: {
                        Label(isRu ? "Поделиться" : "Share",
                              systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Haptics.tap()
                        showReport = true
                    } label: {
                        Label(isRu ? "Пожаловаться" : "Report", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedAuthor != nil },
            set: { if !$0 { selectedAuthor = nil } }
        )) {
            if let a = selectedAuthor {
                PublicProfileView(accountId: a.id, preloaded: a)
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(target: .trip(trip.id))
                .environmentObject(lang)
        }
        .task { await loadReactions() }
    }

    private func loadReactions() async {
        isLoadingReactions = true
        defer { isLoadingReactions = false }
        do {
            let res: SocialReactionsResponse = try await APIClient.shared.post(
                APIEndpoint.socialReactions, body: SocialUnreactRequest(tripId: trip.id))
            reactionEntries = res.reactions
        } catch {
            // Non-fatal — breakdown stays empty
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func mapSection(_ c: AppTheme.Colors) -> some View {
        let coords = trip.previewCoordinates
        if coords.count > 1 {
            MapSnapshotPreview(coordinates: coords, tripId: trip.id, height: mapBaseHeight)
                .frame(maxWidth: .infinity)
                .clipped()
        } else {
            c.cardAlt
                .overlay {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundStyle(c.textTertiary)
                }
        }
    }

    private func authorRow(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            selectedAuthor = trip.author
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.accentBg)
                    .frame(width: 42, height: 42)
                    .overlay { Text(trip.author.avatarEmoji ?? "🚗").font(.system(size: 22)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.author.displayName ?? (isRu ? "Пользователь" : "User"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                    Text(dateLine(isRu: isRu))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(12)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private func titleSection(_ c: AppTheme.Colors) -> some View {
        Text(trip.title ?? "—")
            .font(.system(size: 22, weight: .heavy))
            .tracking(-0.2)
            .foregroundStyle(c.text)
            .lineLimit(3)
    }

    private func metricsGrid(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCell(
                value: String(format: "%.1f", trip.distanceKm),
                unit: AppStrings.km(lang.language),
                label: AppStrings.distance(lang.language),
                color: AppTheme.green, c: c
            )
            metricCell(
                value: trip.formattedDuration,
                unit: "",
                label: AppStrings.duration(lang.language),
                color: AppTheme.accent, c: c
            )
            metricCell(
                value: String(format: "%.0f", trip.averageSpeedKmh),
                unit: AppStrings.kmh(lang.language),
                label: AppStrings.avgSpeed(lang.language),
                color: AppTheme.blue, c: c
            )
            if let region = trip.region, !region.isEmpty {
                metricCell(
                    value: region,
                    unit: "",
                    label: isRu ? "Регион" : "Region",
                    color: c.textSecondary, c: c
                )
            }
        }
    }

    private func metricCell(value: String, unit: String, label: String, color: Color, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .heavy).monospacedDigit())
                    .tracking(-0.3)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }

    private func reactionsRow(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if trip.reactionCount > 0 {
                Text("\(trip.reactionCount)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(c.textTertiary)
                    .tracking(0.5)
                + Text((lang.language == .ru ? " реакций" : " reactions").uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(c.textTertiary)
            }
            HStack(spacing: 4) {
                ForEach(ReactionEmoji.all, id: \.self) { emoji in
                    reactionPill(emoji, c: c)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }

    private func reactionPill(_ emoji: String, c: AppTheme.Colors) -> some View {
        let isMine = trip.myReaction == emoji
        return Button {
            Haptics.selection()
            onReact?(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isMine ? AppTheme.accentBg : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isMine ? AppTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .scaleEffect(isMine ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isMine)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reactions breakdown

    @ViewBuilder
    private func reactionsBreakdown(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        if reactionEntries.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(isRu ? "Реакции" : "Reactions")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(c.textTertiary)
                        .textCase(.uppercase)
                    Text("\(reactionEntries.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                    Spacer()
                    breakdownSummary(c)
                }

                ForEach(reactionEntries) { entry in
                    reactionRow(entry, c: c, isRu: isRu)
                }
            }
            .padding(14)
            .surfaceCard(cornerRadius: 14)
        }
    }

    /// Horizontal stack like "👍 2 · 🔥 1 · ❤️ 3" ranking emojis by count.
    private func breakdownSummary(_ c: AppTheme.Colors) -> some View {
        let counts = Dictionary(grouping: reactionEntries, by: { $0.emoji })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        return HStack(spacing: 6) {
            ForEach(Array(counts.prefix(3)), id: \.key) { emoji, count in
                HStack(spacing: 2) {
                    Text(emoji).font(.system(size: 12))
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textSecondary)
                }
            }
        }
    }

    private func reactionRow(_ entry: SocialReactionEntry, c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            selectedAuthor = entry.user
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.accentBg)
                    .frame(width: 32, height: 32)
                    .overlay { Text(entry.user.avatarEmoji ?? "🚗").font(.system(size: 16)) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.user.displayName ?? (isRu ? "Пользователь" : "User"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(relativeTime(entry.createdAt, isRu: isRu))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer()
                Text(entry.emoji)
                    .font(.system(size: 22))
            }
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date, isRu: Bool) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: isRu ? "ru_RU" : "en_US")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Formatters

    private func dateLine(isRu: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: isRu ? "ru_RU" : "en_US")
        f.dateFormat = "d MMM yyyy, HH:mm"
        var result = f.string(from: trip.startDate)
        if let region = trip.region, !region.isEmpty {
            result += " · \(region)"
        }
        return result
    }
}
