import SwiftUI

/// «Со мной» — trips the SIGNED-IN user rode as an accepted companion, not
/// their own. Sits right after `historySection` in `ProfileView` (task
/// brief). All rendering decisions (hidden / rows+banner) live in the pure
/// `WithMeSectionModel.decide`, covered by `TripTrackTests/WithMeSectionTests
/// .swift` — this view only draws whatever that returns.
///
/// Reuses `ProfileTripRow` — the exact card `historySection` draws for the
/// viewer's own trips (task brief: "reuse the same trip-card component, do
/// not draw a new one") — converting each `SocialFeedTrip` via
/// `Trip(social:)` (`SocialTripAdapter.swift`), the same adapter the feed and
/// notifications inbox already use to open someone else's trip through
/// `TripDetailView`. Each row additionally names the driver via
/// `ProfileTripRow`'s `driverName` — the one fact that tells a companion
/// trip apart from the viewer's own history.
///
/// `onTapTrip` is a closure, not a shared nav-path type: `ProfileView`'s
/// `MeDest` enum (the thing that actually pushes `TripDetailView`) is
/// private to that file, so this view stays decoupled from it — mirrors
/// `ProfileTripRow`'s own `onTap: () -> Void`.
///
/// **Profile aggregates stay untouched.** This view never reads or writes
/// `MapViewModel.cachedTripCount`/`cachedTotalKm`, `MeAggregates`, or
/// anything CoreData-backed — it only reads `CompanionsStore.myTrips`
/// (in-memory, network-sourced) and calls `Trip(social:)` to get a display
/// value for `ProfileTripRow`, which is never saved anywhere. See
/// `TripTrackTests/WithMeSectionTests.swift`'s
/// `testProfileAggregatesComputedFromLocalRepositoryExcludeCompanionTrip`.
struct WithMeSection: View {
    let onTapTrip: (SocialFeedTrip) -> Void

    @ObservedObject private var store = CompanionsStore.shared
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    private var decision: WithMeSectionModel.Decision {
        WithMeSectionModel.decide(myTrips: store.myTrips, loadState: store.myTripsLoadState)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Group {
            switch decision {
            case .hidden:
                EmptyView()
            case .content(let rows, let banner):
                sectionBody(rows: rows, banner: banner, c: c)
            }
        }
        // Fires once regardless of `decision` — the section starts hidden
        // until the first page resolves, so gating this .task on "already
        // visible" would mean it never gets to ask in the first place.
        .task {
            await store.loadMyTrips(reset: true)
        }
    }

    @ViewBuilder
    private func sectionBody(
        rows: [WithMeSectionModel.Row], banner: WithMeSectionModel.Banner, c: AppTheme.Colors
    ) -> some View {
        ProfileSectionLabel(text: AppStrings.withMeSection(lang.language))
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

        // `historySection`'s own rows sit in a plain `ForEach` because that
        // list is capped at 10 (`MeAggregates.recentTrips`). This one grows
        // unbounded through its own cursor pagination (`loadMoreIfNeeded`
        // below) — the exact case CLAUDE.md's `LazyVStack`-inside-`ScrollView`
        // rule exists for. `LazyVStack` stays lazy nested inside the plain
        // outer `VStack`/`ScrollView` `ProfileView` already provides; it does
        // not need to own the `ScrollView` itself.
        LazyVStack(spacing: 0) {
            ForEach(rows) { row in
                tripRow(row)
            }
        }

        if banner == .loadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.bottom, 10)
            .accessibilityIdentifier("profile_with_me_loading_more")
        }

        if banner == .error {
            errorRow(hasRows: !rows.isEmpty, c: c)
        }
    }

    private func tripRow(_ row: WithMeSectionModel.Row) -> some View {
        ProfileTripRow(
            trip: Trip(social: row.trip),
            vehicleName: nil,
            driverName: row.trip.author.displayName ?? AppStrings.withMeDriverNoName(lang.language),
            onTap: { onTapTrip(row.trip) }
        )
        .accessibilityIdentifier("profile_with_me_row")
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onAppear { loadMoreIfNeeded(currentId: row.id) }
    }

    private func errorRow(hasRows: Bool, c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.red)
            Text(AppStrings.withMeLoadFailed(lang.language))
                .font(.system(size: 12.5))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 8)
            Button(AppStrings.retry(lang.language)) {
                Haptics.tap()
                // Rows already on screen → the failure was a "load more"
                // page, retry forward from the still-intact cursor. Nothing
                // cached yet → the failure was the first page, start over.
                Task { await store.loadMyTrips(reset: !hasRows) }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .surfaceCard(cornerRadius: 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityIdentifier("profile_with_me_error")
    }

    /// Same "fires as the last currently-displayed row appears" trigger
    /// `CompanionsPickerSheet.loadMoreIfNeeded` uses for candidates.
    /// `store.loadMyTrips(reset: false)` already guards `hasMoreMyTrips` and
    /// in-flight coalescing, so a repeat call here (scroll bounce, SwiftUI
    /// re-running `.onAppear`) is a harmless no-op.
    private func loadMoreIfNeeded(currentId: UUID) {
        guard currentId == store.myTrips.last?.id else { return }
        Task { await store.loadMyTrips(reset: false) }
    }
}
