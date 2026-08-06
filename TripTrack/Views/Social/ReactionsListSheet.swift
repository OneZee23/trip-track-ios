import SwiftUI

/// «Кто отреагировал» — Telegram's reaction list, opened by long-pressing a
/// reaction pill. Chips across the top switch between all reactions and one
/// specific emoji; the rows below are the people, newest first, tappable
/// through to their profile.
///
/// Fetches `/social/reactions` itself rather than taking a prepared list:
/// the feed card only knows the tallies, and the trip detail's copy can be
/// stale by the time you press. Legacy prod emoji (❤️ 🏎️ 🗺️) are folded into
/// their canon replacements for the chips, exactly like the tallies, while
/// each row still shows the icon that person actually left.
struct ReactionsListSheet: View {
    let tripId: UUID
    /// Emoji whose pill was pressed — the list opens on that chip.
    var initialEmoji: String?
    /// Row tap. The host closes this sheet and pushes the profile in its own
    /// stack, so the list never has to own navigation.
    var onSelectUser: (SocialAuthor) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [SocialReactionEntry] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var selectedEmoji: String?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(spacing: 0) {
            header(c, isRu: isRu)

            if !tallies.isEmpty {
                chips(c, isRu: isRu)
            }

            content(c, isRu: isRu)
        }
        .background(c.bg)
        .task {
            selectedEmoji = initialEmoji.map { ReactionEmoji.canonical($0) }
            await load()
        }
    }

    // MARK: - Header

    private func header(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isRu ? "Реакции" : "Reactions")
                .font(.inter(22, weight: .heavy))
                .tracking(-0.22)
                .foregroundStyle(c.text)

            if !entries.isEmpty {
                Text("\(entries.count)")
                    .font(.inter(13, weight: .bold).monospacedDigit())
                    .foregroundStyle(c.textTertiary)
            }

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                NavCircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.closeSheet(lang.language))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Chips

    /// Canonical emoji + count, most-used first — same ordering rule the
    /// card tallies use so the chip row reads like the pills you pressed.
    private var tallies: [ReactionTally] {
        ReactionEmoji.mergedTallies(
            entries.map { ReactionTally(emoji: $0.emoji, count: 1) }
        )
    }

    private func chips(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(
                    label: { Text(isRu ? "Все" : "All").font(.inter(13, weight: .bold)) },
                    count: entries.count,
                    isSelected: selectedEmoji == nil,
                    c: c
                ) { selectedEmoji = nil }

                ForEach(tallies, id: \.emoji) { tally in
                    chip(
                        label: {
                            ReactionIconView(
                                emoji: tally.emoji,
                                size: 15,
                                filled: selectedEmoji == tally.emoji,
                                tint: selectedEmoji == tally.emoji ? AppTheme.accent : c.text
                            )
                        },
                        count: tally.count,
                        isSelected: selectedEmoji == tally.emoji,
                        c: c
                    ) { selectedEmoji = tally.emoji }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 10)
    }

    private func chip<Label: View>(
        @ViewBuilder label: () -> Label,
        count: Int,
        isSelected: Bool,
        c: AppTheme.Colors,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 5) {
                label()
                Text("\(count)")
                    .font(.inter(12, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSelected ? AppTheme.accent : c.textSecondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(isSelected ? AppTheme.orangeDim : c.cardAlt))
            .overlay(Capsule().stroke(isSelected ? AppTheme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var visibleEntries: [SocialReactionEntry] {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        guard let selectedEmoji else { return sorted }
        return sorted.filter { ReactionEmoji.canonical($0.emoji) == selectedEmoji }
    }

    @ViewBuilder
    private func content(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        if isLoading {
            PixelCarLoader(label: nil, height: 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 30)
        } else if loadFailed {
            emptyState(
                icon: "wifi.slash",
                title: isRu ? "Не удалось загрузить" : "Couldn't load",
                subtitle: isRu
                    ? "Проверьте соединение и потяните вниз, чтобы обновить."
                    : "Check your connection and pull to refresh.",
                c: c
            )
        } else if visibleEntries.isEmpty {
            emptyState(
                icon: "hand.thumbsup",
                title: isRu ? "Пока никто не отреагировал" : "No reactions yet",
                subtitle: isRu
                    ? "Будьте первым — реакции появятся здесь."
                    : "Be the first — reactions show up here.",
                c: c
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleEntries) { entry in
                        row(entry, c: c, isRu: isRu)
                        if entry.id != visibleEntries.last?.id {
                            Divider()
                                .overlay(c.border)
                                .padding(.leading, 67)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await load() }
        }
    }

    private func row(
        _ entry: SocialReactionEntry, c: AppTheme.Colors, isRu: Bool
    ) -> some View {
        Button {
            Haptics.tap()
            onSelectUser(entry.user)
        } label: {
            HStack(spacing: 11) {
                Circle()
                    .fill(c.cardAlt)
                    .frame(width: 36, height: 36)
                    .overlay { Text(entry.user.avatarEmoji ?? "🚗").font(.system(size: 18)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.user.displayName ?? (isRu ? "Пользователь" : "User"))
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(RelativeTripDate.string(from: entry.createdAt, language: lang.language))
                        .font(.inter(11))
                        .foregroundStyle(c.textTertiary)
                }

                Spacer(minLength: 8)

                // The icon this person actually left — a legacy ❤️ still
                // renders as the canon 👍 art, which is what they see
                // everywhere else in the app.
                ReactionIconView(emoji: ReactionEmoji.canonical(entry.emoji), size: 20, filled: true)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private func emptyState(
        icon: String, title: String, subtitle: String, c: AppTheme.Colors
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(c.textTertiary)
            Text(title)
                .font(.inter(14, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Text(subtitle)
                .font(.inter(12))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
        .padding(.horizontal, 30)
    }

    // MARK: - Loading

    private func load() async {
        loadFailed = false
        do {
            let res: SocialReactionsResponse = try await APIClient.shared.post(
                APIEndpoint.socialReactions,
                body: SocialUnreactRequest(tripId: tripId),
                requiresAuth: false
            )
            await MainActor.run {
                entries = res.reactions
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadFailed = true
                isLoading = false
            }
        }
    }
}
