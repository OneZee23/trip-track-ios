import SwiftUI

/// «Попутчики» on the trip detail — the GLANCE: a cluster of faces, who they
/// are, and one line saying what they are to this trip. Tapping it opens
/// `CompanionsRosterSheet`, which owns the list itself and everything you
/// can do to a companion (invite, remove, open a profile).
///
/// It used to draw the whole roster inline, and grew a status note, a remove
/// button, an invite row and two failure strips doing it — a lot of
/// machinery on a screen whose subject is the trip, and it got longer with
/// every companion. What stayed here is the part that belongs on the trip:
/// who was in the car.
///
/// States, driven by `CompanionsCardModel.decide` (the plaque itself by
/// `CompanionsSummaryModel.summarize`):
///
///  - **Own trip, roster non-empty.** The plaque. A failed refresh or a
///    cache-only roster adds its strip UNDER the plaque rather than
///    replacing it — rows that are still good must not be evicted by a
///    network blip.
///  - **Own trip, roster empty.** Always drawn: an empty, successfully
///    loaded roster is the invitation to invite someone, not a reason to
///    hide. Loading, failed and never-published each say so on their own
///    instead of impersonating "nobody came along".
///  - **Someone else's trip, roster non-empty.** The same plaque, opening
///    the same roster read-only.
///  - **Someone else's trip, nothing CONFIRMED to show.** Never loaded,
///    still loading, or genuinely empty — the section isn't drawn at all. A
///    load that outright FAILED is not folded into this state: it surfaces
///    its own error row, so a network blip can never look identical to
///    "this trip has no companions".
struct TripCompanionsSection: View {
    let tripId: UUID
    let isOwn: Bool
    /// Fix 2: whether it's worth even ASKING the server for this trip's
    /// companion roster, and when it isn't, why — blocked only for an own
    /// trip that is signed out or has never reached the server
    /// (`TripDetailView.companionsGate`). A non-owner is never gated: they
    /// can only have reached this screen for a trip that already exists
    /// server-side. When blocked, `load()` never fires the request at all
    /// and the card explains the blocker instead of asking a question the
    /// server can only answer `TRIP_NOT_FOUND` to.
    var gate: CompanionsCardModel.Gate = .allowed
    /// Task 7's offline cache (`Trip.companions`) for THIS trip, as loaded
    /// by `TripDetailView` from local storage — empty for a foreign trip
    /// (which never has one) or an own trip that never had a successful
    /// `list()` yet. Only consulted by `CompanionsCardModel.decide` when
    /// today's fetch fails and nothing survived in memory either.
    var cachedCompanions: [TripCompanion] = []
    /// Opens the candidate picker — reachable from here only in the empty
    /// state, where there is no plaque to lead into the roster.
    var onInvite: (() -> Void)?
    /// Opens `CompanionsRosterSheet`.
    var onOpenRoster: () -> Void
    /// Opens the sign-in sheet from the signed-out row. Without it that row
    /// would state a blocker and give no way to clear it.
    var onSignIn: (() -> Void)?

    @ObservedObject private var store = CompanionsStore.shared
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    private var companions: [CompanionItem] { store.companionsByTrip[tripId] ?? [] }
    private var decision: CompanionsCardModel.Decision {
        CompanionsCardModel.decide(
            companions: companions, isOwn: isOwn, loadState: store.loadState(for: tripId),
            cached: cachedCompanions.map(\.asCompanionItem), gate: gate)
    }

    /// `.task(id:)`'s identity — includes `gate` (not just `tripId`) so a
    /// trip that becomes askable WHILE this screen is already open re-fires
    /// the fetch instead of staying stuck on the blocked hint until the
    /// screen is reopened. Two things can flip it: the record→upload race
    /// resolving in the background, and the guest signing in from the row
    /// below.
    private struct TaskKey: Equatable {
        let tripId: UUID
        let gate: CompanionsCardModel.Gate
    }

    var body: some View {
        Group {
            switch decision {
            case .own(let rows, let banner):
                section(ownCard(rows: rows, banner: banner))
            case .readOnly(let rows, let banner):
                section(readOnlyCard(rows: rows, banner: banner))
            case .hidden:
                EmptyView()
            }
        }
        .task(id: TaskKey(tripId: tripId, gate: gate)) { await load() }
    }

    private func section<Content: View>(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(text: AppStrings.companionsSection(lang.language))
            content
        }
    }

    // MARK: - Own card

    @ViewBuilder
    private func ownCard(
        rows: [CompanionsCardModel.Row], banner: CompanionsCardModel.Banner
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        card(c) {
            if let summary = summary(for: rows) {
                plaque(summary, c: c)
                trailingStrip(banner, c: c)
            } else {
                switch banner {
                case .loading: loadingRow
                case .error: errorRow(c)
                // `.stale` only ever arrives WITH the cached rows it's
                // flagging, so it can't reach an empty card — folded in
                // with `.none` so the switch stays exhaustive.
                case .none, .stale: inviteRow(c)
                case .signedOut: signInRow(c)
                case .notPublished: notPublishedRow(c)
                }
            }
        }
    }

    // MARK: - Read-only card

    @ViewBuilder
    private func readOnlyCard(
        rows: [CompanionsCardModel.Row], banner: CompanionsCardModel.Banner
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        card(c) {
            if let summary = summary(for: rows) {
                plaque(summary, c: c)
                trailingStrip(banner, c: c)
            } else {
                // `decide` only ever routes an empty, non-owner roster here
                // when the load outright failed — a still-loading or
                // genuinely-empty roster renders as `.hidden` instead (see
                // this view's doc comment), so `banner` is always `.error`.
                errorRow(c)
            }
        }
    }

    private func card<Content: View>(
        _ c: AppTheme.Colors, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) { content() }
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(c.card)
                    .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
            }
            // `.contain` makes this VStack its own accessibility container
            // instead of a plain (`.ignore`) compound view — without it,
            // SwiftUI floods this identifier onto every leaf element in the
            // subtree, stomping the more specific identifiers each row sets
            // on itself (`companions_publish_first`, `companions_retry`,
            // `companions_summary`, ...), which made them unaddressable by
            // XCUITest even though they render correctly on screen.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("companions_card")
    }

    private func summary(for rows: [CompanionsCardModel.Row]) -> CompanionsSummaryModel.Summary? {
        CompanionsSummaryModel.summarize(
            rows: rows.map(\.companion), isOwn: isOwn, lang: lang.language)
    }

    /// A failed refresh (or a cache-only roster) sits UNDER the plaque
    /// instead of replacing it — see the type's doc comment.
    @ViewBuilder
    private func trailingStrip(_ banner: CompanionsCardModel.Banner, c: AppTheme.Colors) -> some View {
        if banner == .error {
            divider(c)
            errorRow(c)
        } else if banner == .stale {
            divider(c)
            staleRow(c)
        }
    }

    private func divider(_ c: AppTheme.Colors) -> some View {
        Rectangle().fill(c.border).frame(height: 1)
    }

    // MARK: - The plaque

    private func plaque(_ summary: CompanionsSummaryModel.Summary, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            onOpenRoster()
        } label: {
            HStack(spacing: 12) {
                avatarCluster(summary, c: c)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.names)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(summary.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("companions_summary")
    }

    /// Overlapping faces. Each circle carries a ring in the CARD's colour so
    /// the one under it reads as a separate face rather than a smudge, and
    /// `zIndex` keeps the leftmost on top — the same direction the names
    /// are listed in.
    private func avatarCluster(
        _ summary: CompanionsSummaryModel.Summary, c: AppTheme.Colors
    ) -> some View {
        HStack(spacing: -10) {
            ForEach(Array(summary.avatars.enumerated()), id: \.offset) { index, emoji in
                avatarCircle(c) {
                    Text(emoji).font(.system(size: 17))
                }
                .zIndex(Double(summary.avatars.count - index))
            }
            if summary.overflow > 0 {
                avatarCircle(c) {
                    Text("+\(summary.overflow)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                }
                .zIndex(0)
            }
        }
    }

    private func avatarCircle<Content: View>(
        _ c: AppTheme.Colors, @ViewBuilder content: () -> Content
    ) -> some View {
        Circle()
            .fill(c.cardAlt)
            .frame(width: 36, height: 36)
            .overlay { content() }
            .overlay { Circle().strokeBorder(c.card, lineWidth: 2) }
    }

    // MARK: - Empty / loading / error rows

    /// Own trip, nobody invited yet: the invitation IS the card.
    private func inviteRow(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            onInvite?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(c.cardAlt).frame(width: 36, height: 36)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.companionsAddPrompt(lang.language))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                    Text(AppStrings.companionsEmptyHint(lang.language))
                        .font(.system(size: 12.5))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("companions_invite_empty")
    }

    /// Own trip, signed out. Looks like the invitation and IS one — the
    /// blocker is the missing session, and this row can clear it, so it
    /// stays a button and opens the sign-in sheet. It used to render as
    /// `notPublishedRow`, which told owners of already-public trips to
    /// publish them.
    private func signInRow(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            onSignIn?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(c.cardAlt).frame(width: 36, height: 36)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.companionsAddPrompt(lang.language))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                    Text(AppStrings.companionsSignInHint(lang.language))
                        .font(.system(size: 12.5))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("companions_sign_in")
    }

    /// Fix 2: own trip, no server row yet. The ordinary empty-state
    /// invitation's layout, but NOT a button — inviting would hit the
    /// identical `TRIP_NOT_FOUND` `/companions/candidates` throws for the
    /// same reason (see the design doc §1.4), so a dead-end tap would just
    /// trade one failure state for another. The hint says why instead of
    /// leaving the disabled row unexplained.
    private func notPublishedRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(c.cardAlt).frame(width: 36, height: 36)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.companionsAddPrompt(lang.language))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                Text(AppStrings.companionsPublishFirstHint(lang.language))
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityIdentifier("companions_publish_first")
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 20)
    }

    private func errorRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.red)
            Text(AppStrings.companionsLoadFailed(lang.language))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 8)
            Button(AppStrings.retry(lang.language)) {
                Haptics.tap()
                Task { await load() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .accessibilityIdentifier("companions_retry")
    }

    /// Task 7: today's roster fetch failed, but the plaque above IS a
    /// previously-cached roster (`Trip.companions`) rather than nothing.
    /// Deliberately quieter than `errorRow` — no red triangle, no "couldn't
    /// load" — because real people are on screen; this only flags that they
    /// might not be current, with the same retry affordance.
    private func staleRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13))
                .foregroundStyle(c.textTertiary)
            Text(AppStrings.companionsCachedNotice(lang.language))
                .font(.system(size: 12.5))
                .foregroundStyle(c.textTertiary)
            Spacer(minLength: 8)
            Button(AppStrings.retry(lang.language)) {
                Haptics.tap()
                Task { await load() }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityIdentifier("companions_stale")
    }

    // MARK: - Networking

    /// `CompanionsStore.list` records loading/loaded/failed into its own
    /// published `loadStateByTrip` as it goes, so there's nothing further
    /// for this view to track locally — `decision` (computed from the
    /// store) updates on its own as that state changes.
    private func load() async {
        // Fix 2: don't ask a question the server can only answer
        // TRIP_NOT_FOUND to — see `gate`'s doc comment.
        guard gate == .allowed else { return }
        _ = try? await store.list(tripId: tripId, treatTripNotFoundAsEmpty: isOwn)
    }
}
