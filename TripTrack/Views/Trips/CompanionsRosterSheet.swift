import SwiftUI

/// The «Попутчики» screen behind the trip detail's summary plaque: the full
/// roster, one row per person, with everything you can DO to a companion.
///
/// The detail used to draw this list inline. It grew a status note, a remove
/// button, an invite row and two failure strips, which is a lot of machinery
/// for a screen whose subject is the trip — so the detail keeps the glance
/// (`CompanionsSummaryModel`) and the machinery moved here.
///
/// Roles, same three as the plaque:
///  - **Own trip.** Every row the server sent, including pending and
///    declined ones (nobody else is told about those), each removable, plus
///    «Позвать» to open the candidate picker.
///  - **Companion / stranger on someone else's trip.** The identical list
///    minus the remove control and the invite row. Leaving a trip you were
///    invited to lives in the detail's «…» menu, not here — it's an action
///    on your own participation, not on the roster.
///
/// Tapping anyone opens their profile, pushed INSIDE this sheet
/// (`PreviewNavigator` in a `fullScreenCover`, the same navigator every
/// other social flow uses) rather than by dismissing back to the detail —
/// coming back from a profile should land you on the roster you were
/// reading, not on the screen before it.
struct CompanionsRosterSheet: View {
    let tripId: UUID
    let isOwn: Bool
    /// Task 7's offline cache for this trip, forwarded from the detail so a
    /// roster opened with no connection shows the same people the plaque
    /// just showed instead of an empty screen.
    var cachedCompanions: [TripCompanion] = []
    /// Whether anyone can still be added — true exactly while the trip is on
    /// the server, private or not, because that is what an invite points at.
    /// Reading the roster is unaffected: who rode along is the owner's to look
    /// at either way.
    var canInvite: Bool = true

    @ObservedObject private var store = CompanionsStore.shared
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme

    @State private var companionToRemove: CompanionItem?
    @State private var showPicker = false
    @State private var openedProfile: SocialAuthor?
    @State private var profilePath: [ProfilePreviewDest] = []
    @State private var toastItem: ToastItem?
    /// Seeded with a plausible first-frame value so the sheet opens at
    /// roughly its final size instead of animating up from nothing — the
    /// same trick `TripEditSheet` and `CompanionsPickerSheet` use.
    @State private var contentHeight: CGFloat = 200

    private static let headerHeight: CGFloat = 64

    /// Reuses the plaque's own state machine so the roster can never
    /// disagree with it about who counts — including the defensive filter
    /// that keeps a pending or declined row off a non-owner's screen even
    /// if one reached the client (`CompanionsCardModel`'s doc comment).
    private var decision: CompanionsCardModel.Decision {
        CompanionsCardModel.decide(
            companions: store.companionsByTrip[tripId] ?? [],
            isOwn: isOwn,
            loadState: store.loadState(for: tripId),
            cached: cachedCompanions.map(\.asCompanionItem),
            // The roster is only reachable from a plaque, and a plaque only
            // exists for a trip whose roster the server already answered —
            // so unlike the section, this screen is never in the
            // "not published yet" case it would need to gate.
            gate: .allowed
        )
    }

    /// What, if anything, to say about the state of the request itself. The
    /// roster is a screen you open to CHECK something, so a refresh that
    /// failed has to say so here too — otherwise the rows read as current
    /// when they're merely the last thing we knew.
    private var banner: CompanionsCardModel.Banner {
        switch decision {
        case .own(_, let banner), .readOnly(_, let banner): return banner
        case .hidden: return .none
        }
    }

    private var rows: [CompanionsCardModel.Row] {
        let unsorted: [CompanionsCardModel.Row]
        switch decision {
        case .own(let rows, _): unsorted = rows
        case .readOnly(let rows, _): unsorted = rows
        case .hidden: unsorted = []
        }
        // Who came first, then who hasn't answered, then who said no —
        // reading order by how much each row still asks of the owner.
        // `enumerated` keeps the server's order inside each group instead
        // of letting a sort with equal keys reshuffle it.
        return unsorted.enumerated()
            .sorted { lhs, rhs in
                let l = Self.groupRank(lhs.element.status), r = Self.groupRank(rhs.element.status)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    private static func groupRank(_ status: CompanionStatus) -> Int {
        switch status {
        case .accepted: return 0
        case .pending: return 1
        case .declined: return 2
        }
    }

    private var sheetHeight: CGFloat {
        min(Self.headerHeight + contentHeight + 24, UIScreen.main.bounds.height * 0.85)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            header(c)
            ScrollView {
                rosterCard(c)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RosterContentHeightKey.self, value: proxy.size.height)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(c.bg)
        .onPreferenceChange(RosterContentHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .task(id: tripId) { await load() }
        .toast(item: $toastItem)
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
        .sheet(isPresented: $showPicker) {
            CompanionsPickerSheet(tripId: tripId)
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        // `fullScreenCover` rather than a nested `NavigationStack`, for the
        // documented reason in `ProfileView`: a sheet-hosted NavigationStack
        // flashes a system nav bar during pushes.
        .fullScreenCover(
            isPresented: Binding(
                get: { openedProfile != nil },
                set: { if !$0 { openedProfile = nil } }
            ),
            onDismiss: { profilePath = [] }
        ) {
            if let author = openedProfile {
                PreviewNavigator(
                    rootDest: .profile(author.id, author),
                    path: $profilePath,
                    onCloseSheet: { openedProfile = nil }
                )
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        // `.contain` for the same reason the card documents: without it this
        // identifier floods every leaf below and makes the rows' own
        // identifiers unaddressable from XCUITest.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companions_roster")
    }

    // MARK: - Header

    private func header(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Text(AppStrings.companionsSection(lang.language))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .padding(.horizontal, 50)

            HStack {
                Spacer()
                SheetCloseButton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Roster

    private func rosterCard(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                companionRow(row, c: c)
                if isOwn || row.id != rows.last?.id { divider(c) }
            }
            if isOwn, canInvite { inviteRow(c) }
            // Same rule the plaque follows: a failed refresh is appended to
            // the people it couldn't update, never substituted for them.
            if banner == .error {
                divider(c)
                errorStrip(c)
            } else if banner == .stale {
                divider(c)
                staleStrip(c)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
        // Without `.contain` this identifier floods every leaf in the
        // subtree and makes the rows' own identifiers unaddressable — the
        // same trap the inline card documented.
        .accessibilityElement(children: .contain)
    }

    private func divider(_ c: AppTheme.Colors) -> some View {
        Rectangle().fill(c.border).frame(height: 1)
    }

    /// The remove control is a SIBLING of the tap target, never inside its
    /// label: a `Button` nested in another `Button`'s label doesn't reliably
    /// receive the tap — the outer one swallows it — which would trade
    /// "can't open the profile" for "can't remove the companion".
    private func companionRow(_ row: CompanionsCardModel.Row, c: AppTheme.Colors) -> some View {
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                openedProfile = socialAuthor(for: row.companion)
            } label: {
                rowContent(row, c: c)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("companion_row")

            if isOwn {
                Button {
                    Haptics.tap()
                    companionToRemove = row.companion
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.red.opacity(0.85))
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .accessibilityLabel(AppStrings.companionsRemove(lang.language))
                .accessibilityIdentifier("companion_remove")
            }
        }
    }

    private func rowContent(_ row: CompanionsCardModel.Row, c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(c.cardAlt)
                .frame(width: 38, height: 38)
                .overlay { Text(row.companion.avatarEmoji ?? "🙂").font(.system(size: 18)) }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.companion.displayName ?? AppStrings.companionsNoName(lang.language))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                if let note = statusNote(row.status) {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.leading, 14)
        // On an own row the remove button supplies the trailing margin.
        .padding(.trailing, isOwn ? 4 : 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// An accepted companion carries no note — they're simply on the trip.
    private func statusNote(_ status: CompanionStatus) -> String? {
        switch status {
        case .accepted: return nil
        case .pending: return AppStrings.companionsWaiting(lang.language)
        case .declined: return AppStrings.companionsDeclinedNote(lang.language)
        }
    }

    private func inviteRow(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            showPicker = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(c.cardAlt).frame(width: 38, height: 38)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                Text(AppStrings.companionsInvite(lang.language))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("companions_invite_more")
    }

    private func errorStrip(_ c: AppTheme.Colors) -> some View {
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

    private func staleStrip(_ c: AppTheme.Colors) -> some View {
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

    // MARK: - Actions

    /// Refreshed on open, not just inherited from the plaque: this is the
    /// screen you come to when you want to know whether anyone answered,
    /// and the section's own fetch may be minutes old by then.
    private func load() async {
        _ = try? await store.list(tripId: tripId, treatTripNotFoundAsEmpty: isOwn)
    }

    private func remove() {
        guard let target = companionToRemove else { return }
        companionToRemove = nil
        Haptics.action()
        Task {
            do {
                try await store.remove(tripId: tripId, accountId: target.accountId)
            } catch {
                toastItem = ToastItem(
                    type: .error, message: AppStrings.companionsRemoveFailed(lang.language))
            }
        }
    }

    /// `PublicProfileView`'s preload summary carries a `profileLevel`
    /// `CompanionItem` doesn't have — 0 renders for the instant it takes the
    /// screen to fetch the real profile underneath, same as every other
    /// preload built from a partial DTO.
    private func socialAuthor(for companion: CompanionItem) -> SocialAuthor {
        SocialAuthor(
            id: companion.accountId,
            displayName: companion.displayName,
            avatarEmoji: companion.avatarEmoji,
            profileLevel: 0
        )
    }
}

private struct RosterContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
