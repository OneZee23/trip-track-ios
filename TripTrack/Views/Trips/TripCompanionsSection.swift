import SwiftUI

/// «Попутчики» — the roster of REAL accounts that were in the car, backed by
/// `CompanionsStore` (Task 1's `/companions/*` client). Three states, driven
/// by `CompanionsCardModel.decide`:
///
///  - **Own trip.** Always drawn — an empty, successfully-loaded roster is
///    the invitation to invite someone, not a reason to hide. Rows carry a
///    "ждёт" note only while pending; declined rows stay visible (only to
///    the owner — the server never sends them to anyone else) but look
///    like any other row. Removing asks for confirmation first, then calls
///    `store.remove`. «Позвать» is a hook: the candidate picker itself is
///    Task 3, so this only calls `onInvite`.
///  - **Someone else's trip, viewer is a companion or a stranger.**
///    Identical read-only list. The roster item for a companion viewer
///    would carry their own account id among the accepted rows, so the two
///    cases ARE technically distinguishable — nothing in the required
///    behaviour currently depends on making that distinction, which is why
///    both render here rather than because the data can't tell them apart.
///    Tapping a row opens that person's profile the same way a reactor
///    avatar does elsewhere on this screen (`onOpenProfile`, wired by
///    `TripDetailView` to its existing `pushPath`/local-navigation
///    fallback).
///  - **Someone else's trip, nothing CONFIRMED to show.** Never loaded,
///    still loading, or loaded and genuinely empty — the card and its
///    header are not drawn. A load that outright FAILED is not folded into
///    this state: it surfaces its own error row (`CompanionsCardModel`'s
///    `.readOnly(rows: [], banner: .error)`) so a network blip can never
///    look identical to "this trip has no companions".
struct TripCompanionsSection: View {
    let tripId: UUID
    let isOwn: Bool
    /// Fix 2: whether it's worth even ASKING the server for this trip's
    /// companion roster — `false` only for an own trip that is signed out
    /// or has never reached the server (`TripDetailView.canQueryCompanions`).
    /// A non-owner is never gated: they can only have reached this screen
    /// for a trip that already exists server-side. When `false`, `load()`
    /// never fires the request at all and `CompanionsCardModel.decide`
    /// renders the disabled invite-with-hint state instead of asking a
    /// question the server can only answer `TRIP_NOT_FOUND` to.
    var canQuery: Bool = true
    /// Task 7's offline cache (`Trip.companions`) for THIS trip, as loaded
    /// by `TripDetailView` from local storage — empty for a foreign trip
    /// (which never has one) or an own trip that never had a successful
    /// `list()` yet. Only consulted by `CompanionsCardModel.decide` when
    /// today's fetch fails and nothing survived in memory either.
    var cachedCompanions: [TripCompanion] = []
    /// Task 3 hook: presents the candidate picker. The picker doesn't exist
    /// yet — this is deliberately just a closure the detail screen passes
    /// in, not a built flow.
    var onInvite: (() -> Void)?
    /// Same navigation the reactor rows on this screen already use — the
    /// section builds a `SocialAuthor` from the tapped companion and hands
    /// it back rather than owning a route of its own.
    var onOpenProfile: (SocialAuthor) -> Void
    var onError: (String) -> Void

    @ObservedObject private var store = CompanionsStore.shared
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var companionToRemove: CompanionItem?

    private var companions: [CompanionItem] { store.companionsByTrip[tripId] ?? [] }
    private var decision: CompanionsCardModel.Decision {
        CompanionsCardModel.decide(
            companions: companions, isOwn: isOwn, loadState: store.loadState(for: tripId),
            cached: cachedCompanions.map(\.asCompanionItem), canQuery: canQuery)
    }

    /// `.task(id:)`'s identity — includes `canQuery` (not just `tripId`) so
    /// a trip that flips from "not on the server" to "on the server" WHILE
    /// this screen is already open (the record→upload race resolving in the
    /// background) re-fires the fetch instead of staying stuck showing the
    /// disabled hint until the screen is reopened.
    private struct TaskKey: Equatable {
        let tripId: UUID
        let canQuery: Bool
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
        .task(id: TaskKey(tripId: tripId, canQuery: canQuery)) { await load() }
        .confirmationDialog(
            AppStrings.companionsRemoveConfirmTitle(lang.language),
            isPresented: Binding(
                get: { companionToRemove != nil },
                set: { if !$0 { companionToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.companionsRemove(lang.language), role: .destructive) { remove() }
            Button(AppStrings.cancel(lang.language), role: .cancel) {}
        }
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
        VStack(spacing: 0) {
            if rows.isEmpty {
                switch banner {
                case .loading: loadingRow
                case .error: errorRow(c)
                case .none: inviteRow(c, emptyState: true)
                // Unreachable by construction — `CompanionsCardModel.decide`
                // only ever returns `.stale` together with the cached rows
                // it's flagging, so `rows` is never empty here. Handled
                // anyway so this switch stays exhaustive; falls back to the
                // same empty-state invitation `.none` shows.
                case .stale: inviteRow(c, emptyState: true)
                case .notPublished: notPublishedRow(c)
                }
            } else {
                ForEach(rows) { row in
                    companionRow(row, c: c, navigable: false)
                    divider(c)
                }
                // A failed BACKGROUND refresh must not evict rows that are
                // still good — surface it as a strip alongside them instead
                // of replacing the list. `.stale` is the Task 7 twin of this:
                // the rows themselves ARE the (possibly outdated) cache, so
                // the strip just says so more quietly than `.error` does.
                if banner == .error {
                    errorRow(c)
                    divider(c)
                } else if banner == .stale {
                    staleRow(c)
                    divider(c)
                }
                inviteRow(c, emptyState: false)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
        .accessibilityIdentifier("companions_card")
    }

    // MARK: - Read-only card

    @ViewBuilder
    private func readOnlyCard(
        rows: [CompanionsCardModel.Row], banner: CompanionsCardModel.Banner
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            if rows.isEmpty {
                // `decide` only ever routes an empty, non-owner roster here
                // when the load outright failed — a still-loading or
                // genuinely-empty roster renders as `.hidden` instead (see
                // this view's doc comment), so `banner` is always `.error`
                // on this branch.
                errorRow(c)
            } else {
                ForEach(rows) { row in
                    companionRow(row, c: c, navigable: true)
                    if row.id != rows.last?.id { divider(c) }
                }
                if banner == .error {
                    divider(c)
                    errorRow(c)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
        .accessibilityIdentifier("companions_card")
    }

    private func divider(_ c: AppTheme.Colors) -> some View {
        Rectangle().fill(c.border).frame(height: 1)
    }

    // MARK: - Rows

    @ViewBuilder
    private func companionRow(
        _ row: CompanionsCardModel.Row, c: AppTheme.Colors, navigable: Bool
    ) -> some View {
        if navigable {
            Button {
                Haptics.tap()
                onOpenProfile(socialAuthor(for: row.companion))
            } label: {
                companionRowContent(row, c: c, showChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("companion_row")
        } else {
            companionRowContent(row, c: c, showChevron: false)
                .accessibilityIdentifier("companion_row")
        }
    }

    private func companionRowContent(
        _ row: CompanionsCardModel.Row, c: AppTheme.Colors, showChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(c.cardAlt)
                .frame(width: 34, height: 34)
                .overlay { Text(row.companion.avatarEmoji ?? "🙂").font(.system(size: 16)) }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.companion.displayName ?? (lang.language == .ru ? "Без имени" : "No name"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                // The ONLY status note a row ever carries — accepted and
                // declined both show nothing here.
                if row.isWaiting {
                    Text(AppStrings.companionsWaiting(lang.language))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                }
            }

            Spacer(minLength: 0)

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }

            if isOwn {
                Button {
                    Haptics.tap()
                    companionToRemove = row.companion
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.companionsRemove(lang.language))
                .accessibilityIdentifier("companion_remove")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        // A declined row stays visible to the owner (so they know who said
        // no) but reads as quieter than someone actually coming along.
        .opacity(row.status == .declined ? 0.55 : 1)
    }

    /// The empty-state invitation (own trip, no companions yet) and the
    /// smaller «Позвать» row appended after an existing roster are the same
    /// affordance at two sizes — both just call `onInvite`.
    private func inviteRow(_ c: AppTheme.Colors, emptyState: Bool) -> some View {
        Button {
            Haptics.tap()
            onInvite?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(c.cardAlt).frame(width: emptyState ? 34 : 30, height: emptyState ? 34 : 30)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: emptyState ? 14 : 13, weight: .semibold))
                        .foregroundStyle(emptyState ? c.textTertiary : AppTheme.accent)
                }
                if emptyState {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.companionsAddPrompt(lang.language))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                        Text(AppStrings.companionsEmptyHint(lang.language))
                            .font(.system(size: 12.5))
                            .foregroundStyle(c.textTertiary)
                    }
                } else {
                    Text(AppStrings.companionsInvite(lang.language))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
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
        .accessibilityIdentifier(emptyState ? "companions_invite_empty" : "companions_invite_more")
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
                Circle().fill(c.cardAlt).frame(width: 34, height: 34)
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

    // MARK: - Loading / error

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

    /// Task 7: today's roster fetch failed, but the rows above ARE a
    /// previously-cached one (`Trip.companions`) rather than nothing.
    /// Deliberately quieter than `errorRow` — no red triangle, no "couldn't
    /// load" — because real rows are on screen; this only flags that they
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
        // TRIP_NOT_FOUND to — see `canQuery`'s doc comment.
        guard canQuery else { return }
        try? await store.list(tripId: tripId, treatTripNotFoundAsEmpty: isOwn)
    }

    private func remove() {
        guard let target = companionToRemove else { return }
        companionToRemove = nil
        Haptics.action()
        Task {
            do {
                try await store.remove(tripId: tripId, accountId: target.accountId)
            } catch {
                onError(AppStrings.companionsRemoveFailed(lang.language))
            }
        }
    }

    /// `PublicProfileView`'s preload summary carries a `profileLevel`
    /// `CompanionItem` doesn't have — 0 renders for the instant it takes the
    /// screen to fetch the real profile underneath, same as every other
    /// preload built from a partial DTO on this screen.
    private func socialAuthor(for companion: CompanionItem) -> SocialAuthor {
        SocialAuthor(
            id: companion.accountId,
            displayName: companion.displayName,
            avatarEmoji: companion.avatarEmoji,
            profileLevel: 0
        )
    }
}
