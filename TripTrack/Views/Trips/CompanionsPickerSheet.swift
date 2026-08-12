import SwiftUI

/// «Позвать» — search + invite from the trip owner's followed accounts.
/// Presented as a measured-height sheet (same trick as `TripEditSheet`:
/// measure the HEADER's own height, never its position — the list below it
/// gets a fixed height budget instead of a measured one, see
/// `Self.listAreaHeight`'s doc comment) from `TripCompanionsSection`'s
/// «Позвать» affordance via `TripDetailView.openCompanionsPicker`.
///
/// Candidates come pre-filtered server-side (`/companions/candidates`:
/// followed, not already on the trip, no blocks/bans) — this view does no
/// additional filtering of its own. All rendering decisions (loading /
/// loaded-empty / failed / already-invited) live in the pure
/// `CompanionsPickerModel.decide`, covered by
/// `TripTrackTests/CompanionsPickerTests.swift`.
struct CompanionsPickerSheet: View {
    let tripId: UUID

    @ObservedObject private var store = CompanionsStore.shared
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var query: String = ""
    @State private var searchTask: Task<Void, Never>?
    /// Bumped by every `reset: true` call in `load(reset:)`, mirroring
    /// `CompanionsStore`'s own `candidatesGeneration` — but scoped to this
    /// VIEW, because the store's guard only protects `store.candidates`
    /// itself, not this view's separate `displayedCandidates` mirror (see
    /// `CompanionsPickerModel.isCurrent`'s doc comment for the race this
    /// closes).
    @State private var loadGeneration = 0
    /// True once this sheet SESSION has published a real result at least
    /// once. `store.candidatesLoadState` is a singleton field that outlives
    /// any one picker session — reopening the picker (same trip or a
    /// different one) starts with fresh, empty `@State` here but
    /// `store.candidatesLoadState` still holds whatever the PREVIOUS
    /// session last left it at (`.loaded`/`.failed`). Without this gate,
    /// `decision`'s very first evaluation — before `.task` below has even
    /// started running, let alone completed a request — would read that
    /// leftover verdict against the fresh empty list and flash "Некого
    /// позвать" for a frame before the real load state catches up. Gating
    /// on a per-session `@State` flag (rather than trying to reset the
    /// store's field early enough) is what guarantees the FIRST frame is
    /// correct regardless of exactly when the async `.task` closure and its
    /// inner `Task` actually get scheduled.
    @State private var hasCompletedInitialLoad = false
    /// Local mirror of `store.candidates` that only ever GROWS or gets
    /// wholesale replaced on a fresh search/reset — `store.invite`
    /// optimistically PRUNES an invited account out of `store.candidates`
    /// (it's no longer a valid future candidate), which is correct for what
    /// a FRESH page should contain but would make an already-rendered row
    /// vanish mid-tap instead of visibly flipping to "приглашён" the way
    /// the brief asks for. Keeping our own copy, and only ever
    /// appending/replacing it (never pruning in step with the store), is
    /// what lets `invitedIds` below do that.
    @State private var displayedCandidates: [CompanionCandidate] = []
    /// Accounts THIS sheet session invited — read by `CompanionsPickerModel
    /// .decide` to flag a row `isInvited` even after the store has already
    /// dropped it from `store.candidates`.
    @State private var invitedIds: Set<UUID> = []
    @State private var toastItem: ToastItem?

    /// Seeded with a plausible first-frame value so the sheet does not open
    /// at zero and animate open; the real measurement lands on the same
    /// frame (same seeding trick `TripEditSheet` uses).
    @State private var headerHeight: CGFloat = 96

    /// Unlike `TripEditSheet`'s form (fixed fields, so its total height is a
    /// real property of the content worth measuring), this list is
    /// inherently unbounded — cursor paging keeps growing it. Measuring ITS
    /// height would mean the sheet keeps growing as more pages load, which
    /// is the opposite of what a scrolling list wants. So only the fixed
    /// header above (title + search field) is measured; the list gets a
    /// constant height budget and scrolls its own content within it.
    private static let listAreaHeight: CGFloat = 440

    private var decision: CompanionsPickerModel.Decision {
        // Before this session's own first `load(reset: true)` has resolved,
        // `store.candidatesLoadState` may still be a PREVIOUS session's
        // leftover verdict — see `hasCompletedInitialLoad`'s doc comment.
        guard hasCompletedInitialLoad else { return .empty(.loading) }
        return CompanionsPickerModel.decide(
            candidates: displayedCandidates, invitedIds: invitedIds, loadState: store.candidatesLoadState)
    }

    private var sheetHeight: CGFloat {
        min(headerHeight + Self.listAreaHeight + 12, UIScreen.main.bounds.height * 0.9)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            headerAndSearch(c)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
                    }
                )

            listContent(c)
                .frame(height: Self.listAreaHeight)
        }
        .background(c.bg)
        .onPreferenceChange(HeaderHeightKey.self) { height in
            guard height > 0 else { return }
            headerHeight = height
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .toast(item: $toastItem)
        .task(id: tripId) {
            await load(reset: true)
        }
    }

    // MARK: - Header + search

    private func headerAndSearch(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Text(AppStrings.companionsPickerTitle(lang.language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 50)

                HStack {
                    Spacer()
                    SheetCloseButton()
                }
            }

            searchField(c)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func searchField(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(c.textTertiary)
            TextField(
                text: $query,
                prompt: Text(AppStrings.companionsSearchPlaceholder(lang.language))
                    .foregroundStyle(c.textTertiary)
            ) {
                Text(AppStrings.companionsSearchPlaceholder(lang.language))
            }
            .font(.system(size: 15))
            .foregroundStyle(c.text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier("companions_picker_search_field")
            .onChange(of: query) { _, newValue in
                debouncedSearch(newValue)
            }

            if !query.isEmpty {
                Button {
                    Haptics.tap()
                    searchTask?.cancel()
                    query = ""
                    // Routed through `searchTask` (not an ad-hoc `Task`) so
                    // a keystroke right after clearing correctly cancels
                    // THIS load the same way it would a debounce timer —
                    // one single "current pending search" slot instead of
                    // two independent, uncoordinated ones.
                    searchTask = Task { await load(reset: true) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(c.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surfaceCard(cornerRadius: 12)
    }

    // MARK: - List

    @ViewBuilder
    private func listContent(_ c: AppTheme.Colors) -> some View {
        switch decision {
        case .empty(let banner):
            switch banner {
            case .loading:
                loadingState
            case .error:
                errorState(c)
            case .none, .loadingMore:
                // `.loadingMore` can't actually reach `.empty` (it only
                // ever comes from `hasRows == true`) — folded in here so
                // the switch stays exhaustive without a `default`.
                emptyFollowState(c)
            }
        case .rows(let rows, let banner):
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { row in
                        candidateRow(row, c: c)
                    }
                    if banner == .loadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    if banner == .error {
                        inlineErrorBanner(c)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.red)
            Text(AppStrings.companionsCandidatesLoadFailed(lang.language))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Button {
                Haptics.tap()
                Task { await load(reset: true) }
            } label: {
                Text(AppStrings.retry(lang.language))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(c.cardAlt, in: Capsule())
                    .foregroundStyle(c.text)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("companions_picker_retry")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("companions_picker_error_state")
    }

    private func emptyFollowState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "person.2.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(c.textTertiary)
            Text(AppStrings.companionsCandidatesEmptyTitle(lang.language))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Text(AppStrings.companionsCandidatesEmptyHint(lang.language))
                .font(.system(size: 12.5))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("companions_picker_empty_state")
    }

    private func inlineErrorBanner(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.red)
            Text(AppStrings.companionsCandidatesLoadFailed(lang.language))
                .font(.system(size: 12.5))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 8)
            Button(AppStrings.retry(lang.language)) {
                Haptics.tap()
                Task { await load(reset: false) }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .surfaceCard(cornerRadius: 12)
    }

    // MARK: - Row

    private func candidateRow(_ row: CompanionsPickerModel.Row, c: AppTheme.Colors) -> some View {
        Button {
            invite(row.candidate)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(c.cardAlt)
                    .frame(width: 36, height: 36)
                    .overlay { Text(row.candidate.avatarEmoji ?? "🙂").font(.system(size: 18)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.candidate.displayName ?? (lang.language == .ru ? "Без имени" : "No name"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text("LVL \(row.candidate.profileLevel)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if row.isInvited {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                        Text(AppStrings.companionsInvited(lang.language))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(c.textTertiary)
                } else {
                    Text(AppStrings.companionsInvite(lang.language))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(11)
            .surfaceCard(cornerRadius: 16)
            .opacity(row.isInvited ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.isInvited)
        .accessibilityIdentifier("companions_picker_row")
        .onAppear { loadMoreIfNeeded(current: row.candidate) }
    }

    // MARK: - Networking

    /// `reset: true` = initial load or a fresh search; `reset: false` =
    /// "load more" from `CompanionsStore`'s own stored cursor. Mirrors
    /// `store.candidates`'s own reset/append split rather than duplicating
    /// its cursor bookkeeping here.
    ///
    /// Race-guarded: `reset: true` bumps `loadGeneration` and captures a
    /// `token` BEFORE the `await` below. `store.candidates` already drops a
    /// stale response before writing `store.candidates` itself, but a
    /// slow, since-superseded call still resumes past this `await` — the
    /// `isCurrent` check after it is what stops THIS call from publishing
    /// unrelated data into `displayedCandidates` (see
    /// `CompanionsPickerModel.isCurrent`'s doc comment).
    private func load(reset: Bool) async {
        // Fix 10: clamp to the server's 60-char limit client-side so
        // ordinary typing can never turn into a validation-error response.
        let clampedQuery = CompanionsPickerModel.clampedQuery(query)
        if reset { loadGeneration &+= 1 }
        let token = loadGeneration
        await store.candidates(tripId: tripId, query: clampedQuery, reset: reset)
        guard CompanionsPickerModel.isCurrent(token: token, latest: loadGeneration) else { return }
        if reset {
            displayedCandidates = store.candidates
            hasCompletedInitialLoad = true
        } else {
            let known = Set(displayedCandidates.map(\.accountId))
            displayedCandidates.append(contentsOf: store.candidates.filter { !known.contains($0.accountId) })
        }
    }

    /// Debounced so search doesn't fire a request per keystroke — same
    /// 300ms shape `DiscoverView.debouncedSearch` already uses.
    private func debouncedSearch(_ text: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    /// Fires as the LAST currently-displayed row appears — same "near the
    /// end" trigger `SocialFeedStore.loadMoreIfNeeded(currentItem:)` uses
    /// for the main feed. `store.candidates(reset: false)` already guards
    /// `hasMore`/in-flight coalescing, so repeated calls here (e.g. during
    /// scroll bounce) are harmless no-ops.
    private func loadMoreIfNeeded(current: CompanionCandidate) {
        guard current.accountId == displayedCandidates.last?.accountId else { return }
        Task { await load(reset: false) }
    }

    /// Tap = invite. Flips the row to "приглашён" immediately (before the
    /// network call resolves); `CompanionsStore.invite` itself already
    /// rolls back its own optimistic candidate-list removal and rethrows on
    /// failure, so this only has to undo the LOCAL `invitedIds` flag and
    /// surface the error — never swallow it.
    private func invite(_ candidate: CompanionCandidate) {
        guard !invitedIds.contains(candidate.accountId) else { return }
        Haptics.tap()
        invitedIds.insert(candidate.accountId)
        Task {
            do {
                try await store.invite(tripId: tripId, accountId: candidate.accountId)
                Haptics.success()
            } catch {
                invitedIds.remove(candidate.accountId)
                toastItem = ToastItem(type: .error, message: AppStrings.companionsInviteFailed(lang.language))
            }
        }
    }

    private struct HeaderHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}
