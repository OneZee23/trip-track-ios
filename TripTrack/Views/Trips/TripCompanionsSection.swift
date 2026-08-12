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
            companions: companions, isOwn: isOwn, loadState: store.loadState(for: tripId))
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
        .task(id: tripId) { await load() }
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
                }
            } else {
                ForEach(rows) { row in
                    companionRow(row, c: c, navigable: false)
                    divider(c)
                }
                // A failed BACKGROUND refresh must not evict rows that are
                // still good — surface it as a strip alongside them instead
                // of replacing the list.
                if banner == .error {
                    errorRow(c)
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

    // MARK: - Networking

    /// `CompanionsStore.list` records loading/loaded/failed into its own
    /// published `loadStateByTrip` as it goes, so there's nothing further
    /// for this view to track locally — `decision` (computed from the
    /// store) updates on its own as that state changes.
    private func load() async {
        try? await store.list(tripId: tripId)
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
