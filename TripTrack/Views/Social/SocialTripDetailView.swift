import SwiftUI
import MapKit

/// Read-only detail view for a trip from the social feed.
/// Unlike the local TripDetailView, it shows a friend's trip — no editing,
/// no deletion, no photo picker. Just the map, metrics, reactions row, and share.
struct SocialTripDetailView: View {
    /// Initial trip snapshot — used as fallback if the store hasn't loaded
    /// this trip (e.g. direct push). Real rendering reads from
    /// `socialFeed.trips` so optimistic reaction updates re-render.
    let initialTrip: SocialFeedTrip
    var onShare: (() -> Void)?
    /// When present, author-avatar and reactor taps push onto this shared
    /// path instead of attaching a local `.navigationDestination`. Keeps us
    /// off the chained isPresented chain that triggers the depth-4 flash.
    var pushPath: Binding<[ProfilePreviewDest]>?

    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var auth = AuthService.shared
    @State private var signInPrompt: SignInPromptSheet.Action?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var socialFeed = SocialFeedStore.shared
    @State private var selectedAuthor: SocialAuthor?
    @State private var reactionEntries: [SocialReactionEntry] = []
    @State private var isLoadingReactions = false
    @State private var isMapFullscreen = false
    @State private var photos: [SocialTripPhoto] = []
    @State private var isLoadingPhotos = false
    @State private var selectedPhotoIndex: Int?
    @State private var selectedDetailBadge: Badge?
    /// Emojis whose pills are currently playing the "burst" animation.
    /// Set on tap-that-adds (not tap-that-removes), cleared 0.7s later.
    /// Uses Set so two quick consecutive reactions don't stomp the
    /// floating sprite for the first one.
    @State private var burstingEmojis: Set<String> = []
    /// Route playback for a friend's trip. previewPolyline is RDP-
    /// simplified (sparser points than a local Trip), so the animation
    /// is still smooth but a hair more "stepped" between sample points.
    @StateObject private var routePlayback = RoutePlaybackController()
    /// Cached decode of `trip.previewPolyline`. The base64 + polyline
    /// decode happens once per trip-id, not on every body re-render
    /// (which during 30Hz playback would mean 30 decodes/sec).
    @State private var cachedPreviewCoords: [CLLocationCoordinate2D] = []

    /// Always-current view of the trip: prefer store's copy (reflects
    /// optimistic reaction toggles) and fall back to the original snapshot
    /// if the store doesn't have the trip yet.
    private var trip: SocialFeedTrip {
        socialFeed.trips.first(where: { $0.id == initialTrip.id }) ?? initialTrip
    }

    private var mapBaseHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.bounds.height ?? 844) * 0.45
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 47
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 0) {
                    mapSection(c)
                        .frame(height: mapBaseHeight)

                    VStack(alignment: .leading, spacing: 16) {
                        authorRow(c, isRu: isRu)
                        titleSection(c)
                        descriptionSection(c)
                        metricsGrid(c, isRu: isRu)
                        if !trip.badgeIds.isEmpty {
                            TripBadgesRow(
                                badgeIds: trip.badgeIds,
                                maxVisible: 6,
                                size: 26,
                                onTap: { badge in selectedDetailBadge = badge }
                            )
                            .padding(.top, 2)
                        }
                        // Render a photos strip only when the server actually
                        // returned any — unlike the owner's detail view which
                        // keeps the section as an empty-state "add photos"
                        // prompt, there's nothing a viewer can do about a
                        // trip without photos, so we just hide it.
                        if !photos.isEmpty {
                            photosSection(c, isRu: isRu)
                        }
                        reactionsRow(c)
                        reactionsBreakdown(c)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 80)
                }
            }
            .scrollIndicators(.hidden)

            // Sticky floating back button + menu — matches TripDetailView pattern.
            HStack {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
                Spacer()
                // Report entry point removed pending a moderation/admin UI —
                // the server endpoint still accepts reports, but there's no
                // triage surface for us to act on them yet. Only share is
                // exposed here. Re-add the Menu when moderation is wired up.
                Button {
                    Haptics.tap()
                    onShare?()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
            }
            .padding(.top, safeAreaTop)
            .padding(.horizontal, 16)
        }
        .background(c.bg)
        .ignoresSafeArea()
        .navigationBarHidden(true)
        // NavBarKiller force-enables the interactive pop gesture in
        // viewWillAppear — without it, `.navigationBarHidden(true)` here
        // disabled the swipe-back-to-feed gesture (TripDetailView wires
        // this in for the same reason).
        .background(NavBarKiller())
        .modifier(SocialTripDetailLocalDestination(
            selectedAuthor: $selectedAuthor,
            enabled: pushPath == nil
        ))
        .hideAppTabBar()
        .fullScreenCover(isPresented: $isMapFullscreen) {
            FullscreenMapSheet(
                coordinates: trip.previewCoordinates,
                speeds: [],
                fogCutoffDate: nil,
                treatAsPreview: true
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoIndex != nil },
            set: { if !$0 { selectedPhotoIndex = nil } }
        )) {
            if let idx = selectedPhotoIndex {
                SocialPhotoFullScreenView(
                    photos: photos,
                    initialIndex: idx,
                    onDismiss: { selectedPhotoIndex = nil }
                )
            }
        }
        .task {
            // `loadReactions` and `loadPhotos` are independent network calls,
            // so kick them off in parallel — whichever finishes first lets
            // SwiftUI render its section before the other lands.
            async let r: Void = loadReactions()
            async let p: Void = loadPhotos()
            _ = await (r, p)
        }
        .task(id: trip.id) {
            // Decode the base64+polyline once per trip-id instead of on
            // every body re-render. Matters during 30Hz route playback —
            // the computed `previewCoordinates` getter would otherwise
            // base64-decode 30×/sec.
            cachedPreviewCoords = trip.previewCoordinates
        }
        .onDisappear { routePlayback.stop() }
        .sheet(item: $signInPrompt) { action in
            SignInPromptSheet(action: action)
                .environmentObject(lang)
                .environmentObject(auth)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .overlay {
            if let badge = selectedDetailBadge {
                BadgeDetailOverlay(
                    badge: badge,
                    isUnlocked: true,
                    language: lang.language,
                    colorScheme: scheme,
                    lastEarnedDate: nil,
                    onDismiss: { selectedDetailBadge = nil }
                )
            }
        }
    }

    private func loadReactions() async {
        isLoadingReactions = true
        defer { isLoadingReactions = false }
        do {
            let res: SocialReactionsResponse = try await APIClient.shared.post(
                APIEndpoint.socialReactions, body: SocialUnreactRequest(tripId: trip.id),
                requiresAuth: AuthService.shared.isSignedIn)
            reactionEntries = res.reactions
        } catch {
            // Non-fatal — breakdown stays empty
        }
    }

    private func loadPhotos() async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        do {
            let res: SocialTripPhotosResponse = try await APIClient.shared.post(
                APIEndpoint.socialTripPhotos,
                body: SocialTripPhotosRequest(tripId: trip.id),
                requiresAuth: AuthService.shared.isSignedIn)
            photos = res.photos
        } catch {
            // Non-fatal — photo strip just stays hidden.
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func mapSection(_ c: AppTheme.Colors) -> some View {
        // Fall back to a fresh decode on the very first render — `.task`
        // populates `cachedPreviewCoords` after first body, so without
        // this fallback the map would flash empty for one frame.
        let coords = cachedPreviewCoords.isEmpty ? trip.previewCoordinates : cachedPreviewCoords
        if coords.count > 1 {
            // Interactive RouteMapView matches TripDetailView so the user can
            // pan/zoom a friend's route the same way as their own. No speed
            // gradient here — social feed only carries `previewPolyline`, not
            // per-point speeds. `fogCutoffDate` stays nil because shared trips
            // aren't part of the viewer's own territory coverage.
            ZStack(alignment: .bottomTrailing) {
                RouteMapView(
                    coordinates: coords,
                    speeds: [],
                    isInteractive: true,
                    fogCutoffDate: nil,
                    treatAsPreview: true,
                    playbackProgress: routePlayback.progress
                )
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    RoutePlaybackButton(isPlaying: routePlayback.isPlaying) {
                        routePlayback.toggle()
                    }
                    Button {
                        Haptics.tap()
                        isMapFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
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
            if let pushPath {
                pushPath.wrappedValue.cappedAppend(.profile(trip.author.id, trip.author))
            } else {
                selectedAuthor = trip.author
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.accentBg)
                    .frame(width: 42, height: 42)
                    .overlay { Text(trip.author.avatarEmoji ?? "🚗").font(.system(size: 22)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.author.displayName ?? (isRu ? "Без имени" : "No name"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(dateLine(isRu: isRu))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                    // Vehicle metadata sits on the identity strip, Strava-
                    // style: the avatar is identity, the vehicle is "what
                    // they were driving". Server now ships this for every
                    // trip in the feed, so own + others show identical chrome.
                    if let v = trip.vehicle {
                        let n = v.name.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty {
                            HStack(spacing: 4) {
                                if v.isPixelAvatar {
                                    Image(v.avatarEmoji)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 13, height: 13)
                                } else {
                                    Text(v.avatarEmoji)
                                        .font(.system(size: 11))
                                }
                                Text(n)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(c.textTertiary)
                                    .lineLimit(1)
                            }
                            .padding(.top, 2)
                        }
                    }
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

    @ViewBuilder
    private func descriptionSection(_ c: AppTheme.Colors) -> some View {
        // Author's notes — surfaced inline below the title so viewers see the
        // story behind the trip the same way the owner does. Empty / null is
        // hidden so the section doesn't take space when there's nothing.
        if let raw = trip.description {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Text(trimmed)
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func metricsGrid(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        // Match the depth of the owner-side stat grid: distance, duration,
        // avg speed, max speed, elevation. Region used to live here but it's
        // redundant with the date line on the identity strip.
        let hasMaxSpeed = (trip.maxSpeed ?? 0) > 0
        let hasElevation = (trip.elevation ?? 0) > 0.5
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
            if hasMaxSpeed {
                metricCell(
                    value: String(format: "%.0f", trip.maxSpeedKmh),
                    unit: AppStrings.kmh(lang.language),
                    label: AppStrings.maxSpeed(lang.language),
                    color: AppTheme.red, c: c
                )
            }
            if hasElevation {
                metricCell(
                    value: String(format: "%.0f", trip.elevation ?? 0),
                    unit: AppStrings.m(lang.language),
                    label: isRu ? "Перепад высот" : "Elevation",
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

    private func photosSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((isRu ? "Фото" : "Photos").uppercased() + "  \(photos.count)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .tracking(0.5)
                .foregroundStyle(c.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        remoteThumbnail(photo, c: c)
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.tap()
                                selectedPhotoIndex = index
                            }
                    }
                }
            }
            .frame(height: 104)
        }
    }

    @ViewBuilder
    private func remoteThumbnail(_ photo: SocialTripPhoto, c: AppTheme.Colors) -> some View {
        // Thumbnail presign first, original second. AsyncImage falls back to
        // a neutral placeholder so the grid doesn't jitter while images load.
        let urlString = photo.thumbnailUrl ?? photo.originalUrl
        if let s = urlString, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle()
                        .fill(c.cardAlt)
                        .overlay {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 18))
                                .foregroundStyle(c.textTertiary)
                        }
                case .empty:
                    Rectangle()
                        .fill(c.cardAlt)
                        .overlay { CarLoadingView(size: .compact) }
                @unknown default:
                    Rectangle().fill(c.cardAlt)
                }
            }
        } else {
            Rectangle()
                .fill(c.cardAlt)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(c.textTertiary)
                }
        }
    }

    private func reactionsRow(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if trip.reactionCount > 0 {
                // Split into two stacked Texts so `contentTransition` /
                // `animation` (which return `some View`) don't break the
                // `Text + Text` concatenation that requires both sides
                // to stay `Text`-typed.
                HStack(spacing: 0) {
                    Text("\(trip.reactionCount)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                        .tracking(0.5)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: trip.reactionCount)
                    Text((lang.language == .ru ? " реакций" : " reactions").uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(c.textTertiary)
                }
            }
            // Horizontal scroll guards against overflow on iPhone SE /
            // mini — 8 pills × 44pt + spacing = 380pt, exceeds the 375pt
            // SE screen and the surrounding card padding. On wider
            // devices the row fits comfortably and scroll never fires.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ReactionEmoji.all, id: \.self) { emoji in
                        reactionPill(emoji, c: c)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }

    private func reactionPill(_ emoji: String, c: AppTheme.Colors) -> some View {
        let isMine = trip.myReaction == emoji
        let isOwnTrip = trip.author.id == TokenStore.shared.accountId
        return Button {
            Haptics.selection()
            guard auth.isSignedIn else {
                signInPrompt = .react
                return
            }
            // Owners can't react to their own trip (Strava rule). The pills
            // still render so the user sees what reactions ARE possible —
            // they just don't fire on tap.
            guard !isOwnTrip else { return }
            // Burst-animate only on the add direction. Tapping again to
            // remove your reaction shouldn't fire the celebratory sprite —
            // that would read as "you added it again" which is wrong.
            if !isMine {
                burstingEmojis.insert(emoji)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    burstingEmojis.remove(emoji)
                }
            }
            // Toggle + re-fetch chained in one task so `/social/reactions`
            // only fires after the `/social/react` write commits. Firing them
            // in parallel (prior bug) meant the fetch returned stale data —
            // the bottom list always showed the *previous* emoji because the
            // new react hadn't landed on the server yet.
            Task {
                await socialFeed.toggleReaction(for: trip.id, emoji: emoji)
                await loadReactions()
            }
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
                .overlay(alignment: .top) {
                    if burstingEmojis.contains(emoji) {
                        ReactionBurstSprite(emoji: emoji)
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reactions breakdown

    @ViewBuilder
    private func reactionsBreakdown(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        let isOwnTrip = trip.author.id == TokenStore.shared.accountId
        if reactionEntries.isEmpty {
            // Quiet empty-state line — different copy for own vs others'
            // matches Strava's "be the first" vs "no kudos yet" split.
            HStack(spacing: 8) {
                Image(systemName: "face.dashed")
                    .font(.system(size: 14))
                    .foregroundStyle(c.textTertiary)
                Text(isOwnTrip
                     ? (isRu ? "Пока никто не отреагировал" : "No reactions yet")
                     : (isRu ? "Будьте первым, кто отреагирует" : "Be the first to react"))
                    .font(.system(size: 13))
                    .foregroundStyle(c.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 4)
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
            if let pushPath {
                pushPath.wrappedValue.cappedAppend(.profile(entry.user.id, entry.user))
            } else {
                selectedAuthor = entry.user
            }
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
        // Single source of truth lives in `RelativeTripDate`. The previous
        // hand-rolled fork existed only to debug the timezone bug (now
        // fixed by `process.env.TZ='UTC'` server-side + `ISODate.parse`
        // client-side); the diag log it carried is no longer needed.
        return RelativeTripDate.string(from: date, language: isRu ? .ru : .en)
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

/// Gates the local-state `.navigationDestination` so it's only active when
/// no shared `pushPath` is wired in. Parallel to the gate in FollowListView
/// / PublicProfileView — same depth-4 flash avoidance.
private struct SocialTripDetailLocalDestination: ViewModifier {
    @Binding var selectedAuthor: SocialAuthor?
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.navigationDestination(isPresented: Binding(
                get: { selectedAuthor != nil },
                set: { if !$0 { selectedAuthor = nil } }
            )) {
                if let a = selectedAuthor {
                    PublicProfileView(accountId: a.id, preloaded: a)
                }
            }
        } else {
            content
        }
    }
}

