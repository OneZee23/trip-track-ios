import SwiftUI
import CoreLocation
import OSLog

/// Strava-style feed card for social feed items (author's trips).
/// Visual layout mirrors FeedTripCardView but shows author row instead of vehicle,
/// plus an action bar with reactions + share.
struct SocialFeedCardView: View {
    let trip: SocialFeedTrip
    /// When true, the card is rendered for the signed-in user's own trip — hides the
    /// report menu and "Reaction" pill, and swaps the author row for a vehicle-style
    /// header that matches the look of trips in the "Мои" tab.
    var isOwn: Bool = false
    var onTapCard: (() -> Void)?
    var onTapAuthor: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onReact: ((String) -> Void)?
    var onShare: (() -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    // Report flow paused until moderation UI exists; state intentionally omitted.

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(alignment: .leading, spacing: 0) {
            authorRow(c, isRu: isRu)
                .padding(.horizontal, 13)
                .padding(.top, 12)
                .padding(.bottom, 10)

            // Body is wrapped so we can attach both tap + long-press gestures.
            VStack(alignment: .leading, spacing: 0) {
                if let title = TripAutoTitle.localized(
                    trip.title, startDate: trip.startDate, language: lang.language
                ), !title.isEmpty {
                    Text(title)
                        .font(.inter(17, weight: .heavy))
                        .tracking(-0.085)
                        .foregroundStyle(c.text)
                        .lineLimit(2)
                        .padding(.horizontal, 13)
                        .padding(.bottom, 10)
                }

                mapSection(c)

                metricsStrip(c)
                    .padding(.horizontal, 13)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                onTapCard?()
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                Haptics.action()
                onLongPress?()
            }

            Rectangle()
                .fill(c.border)
                .frame(height: 1)

            actionBar(c)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
        }
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("social_trip_card")
        .onAppear { logMapDiagnostics() }
    }

    // MARK: - Diagnostics

    /// Lands in the on-device journal (Я → журнал логов, com.triptrack
    /// subsystem) so «карта не отображается» reports come with data instead
    /// of guesswork: exactly what the canvas guard saw for each card.
    private static let mapLog = Logger(subsystem: "com.triptrack", category: "feedcard")
    private static var loggedTripIds = Set<UUID>()

    private func logMapDiagnostics() {
        guard !Self.loggedTripIds.contains(trip.id) else { return }
        Self.loggedTripIds.insert(trip.id)
        let coords = trip.previewCoordinates
        let shown = coords.count > 1
        Self.mapLog.info("card map \(trip.id.uuidString.prefix(8), privacy: .public) '\(trip.title ?? "—", privacy: .public)': polyB64=\(trip.previewPolyline?.count ?? -1) coords=\(coords.count) dist=\(Int(trip.distance)) map=\(shown ? "SHOWN" : "HIDDEN", privacy: .public)")
    }

    // MARK: - Author Row

    private func authorRow(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        // Unified author chrome — own and others' trips share the same layout
        // (Strava/Komoot/Garmin convention). Swapping the user's avatar for a
        // vehicle icon on own cards made the user feel like a ghost in their
        // own feed; identity recognition belongs on the avatar slot. The
        // vehicle now lives in the metrics row as metadata, not identity.
        let rawName = trip.author.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        let headerName = rawName.isEmpty ? (isRu ? "Без имени" : "No name") : rawName
        return HStack(spacing: 10) {
            Circle()
                .fill(c.cardAlt)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(trip.author.avatarEmoji ?? "🙂")
                        .font(.system(size: 19))
                }
                .onTapGesture {
                    Haptics.tap()
                    onTapAuthor?()
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(headerName)
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        // `truncationMode: .tail` is the default but be explicit
                        // since a long name + "Вы" pill needs the truncation
                        // to land on the name, not somewhere weird in the pill.
                        .truncationMode(.tail)
                    // LVL tag — Handjet Black 13, baseline-aligned with the
                    // name: exact FeedCard spec (Components 115:45). The
                    // spec's gold varies per level, which is what the rank
                    // color already does. READ-ONLY use of `DriverRank`.
                    Text("LVL \(trip.author.profileLevel)")
                        // fixedSize — Dynamic Type must not rescale the tag
                        // (custom fonts scale with the text-size setting,
                        // the SF chrome around them doesn't).
                        .font(.custom("Handjet-Black", fixedSize: 13))
                        .foregroundStyle(DriverRank.from(level: trip.author.profileLevel).color)
                        .fixedSize()
                    if isOwn {
                        // Subtle "this is you" badge — explicit signal that
                        // the card is yours without breaking the unified
                        // chrome. NN/g recognition heuristic. `fixedSize`
                        // stops the pill from being squeezed by a long name —
                        // the name truncates first, the pill stays full size.
                        Text(isRu ? "Вы" : "You")
                            .font(.inter(10, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accentBg, in: Capsule())
                            .fixedSize()
                    }
                }
                Text(dateRegionText(isRu: isRu))
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }
            // Claim every pixel of leftover horizontal space. Without this
            // the VStack sized to its intrinsic content, so a short name
            // left a giant gap that the optional photo pill filled with
            // wildly different alignment depending on whether the trip had
            // photos. Forcing maxWidth=.infinity normalises the layout: the
            // photo pill (when present) sits flush right; otherwise the row
            // ends cleanly at the trailing edge.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                onTapAuthor?()
            }

            if trip.photoCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                    Text("+\(trip.photoCount)")
                        .font(.inter(12, weight: .bold))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(c.cardAlt, in: Capsule())
                // Pin width — without this the pill could stretch when the
                // VStack on the left finds room, breaking the symmetry across
                // cards in the same scroll list.
                .fixedSize()
            }

            // «…» menu (Figma FeedCard trailing) — share lives here now;
            // the footer-right slot became the comment affordance. Report
            // row deferred until moderation UI exists.
            Menu {
                Button {
                    onShare?()
                } label: {
                    Label(AppStrings.share(lang.language), systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                    // ≥34pt hit target (project floor) — at 28×28 a leftward
                    // near-miss landed on the author-name tap area instead.
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("feed_card_menu")
        }
    }

    // MARK: - Map

    @ViewBuilder
    private func mapSection(_ c: AppTheme.Colors) -> some View {
        // Real street-map snapshot with the route on top — the release-app
        // look, restored by explicit user decision (2026-08-06): «надо
        // сделать так, как было до этого… мне реально надо показывать
        // настоящий маршрут своих поездок». The Figma beige cinema canvas
        // kept reading as a map that failed to load. MapSnapshotPreview
        // caches rendered tiles per trip+theme, so the feed stays cheap.
        let coords = trip.previewCoordinates
        if coords.count > 1 {
            MapSnapshotPreview(coordinates: coords, tripId: trip.id, height: 178)
                .frame(height: 178)
                .frame(maxWidth: .infinity)
                // Figma: the canvas is full-card-width with 12pt rounded
                // corners (measured off the FeedCard render), not a hard
                // rectangle.
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Metrics

    private func metricsStrip(_ c: AppTheme.Colors) -> some View {
        // FeedCard spec 115:58: three equal flex columns, 4pt gap,
        // leading-aligned; time renders as number(19)+unit(11) runs
        // («4 ч 58 мин»), not one flat string. Nothing below the row —
        // the spec card carries no vehicle line and no badge strip
        // (user call 2026-08-06: «нет Your car… нет списка ачивок»).
        HStack(spacing: 4) {
            metricBlock(
                value: oneDecimal(trip.distanceKm),
                unit: AppStrings.km(lang.language),
                label: AppStrings.distance(lang.language),
                c: c
            )
            metricBlock(
                valueText: durationRuns(c),
                label: AppStrings.duration(lang.language),
                c: c
            )
            metricBlock(
                value: String(format: "%.0f", trip.averageSpeedKmh),
                unit: AppStrings.kmh(lang.language),
                label: AppStrings.avgSpeedShort(lang.language),
                c: c
            )
        }
    }

    /// Big metric digits render in Inter ExtraBold — the design's actual
    /// typeface (115:61); SF Heavy is nominally the same 800 weight but
    /// visibly thinner, which the user flagged against the Figma render.
    private static let metricValueFont = Font.inter(19, weight: .heavy).monospacedDigit()

    private func metricBlock(value: String, unit: String, label: String, c: AppTheme.Colors) -> some View {
        metricBlock(
            valueText: Text(value)
                .font(Self.metricValueFont)
                .tracking(-0.19)
                .foregroundColor(c.text)
                + Text(unit.isEmpty ? "" : " \(unit)")
                .font(.inter(11, weight: .semibold))
                .foregroundColor(c.textSecondary),
            label: label,
            c: c
        )
    }

    /// Figma metric column: value runs, then 5pt, then the caps label.
    private func metricBlock(valueText: Text, label: String, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            valueText
                .lineLimit(1)

            Text(label)
                .font(.inter(11, weight: .bold))
                .tracking(0.55)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «4 ч 58 мин» / "4 h 58 min" — numbers big (19 Inter ExtraBold),
    /// units small (11), matching the Figma metric canon instead of one
    /// flat string.
    private func durationRuns(_ c: AppTheme.Colors) -> Text {
        let big = Self.metricValueFont
        let small = Font.inter(11, weight: .semibold)
        let h = trip.duration / 3600
        let m = (trip.duration % 3600) / 60
        let minutes = Text("\(m)").font(big).foregroundColor(c.text)
            + Text(" \(AppStrings.minutesUnitShort(lang.language))")
                .font(small).foregroundColor(c.textSecondary)
        guard h > 0 else { return minutes }
        return Text("\(h)").font(big).foregroundColor(c.text)
            + Text(" \(AppStrings.hoursUnitShort(lang.language)) ")
                .font(small).foregroundColor(c.textSecondary)
            + minutes
    }

    // MARK: - Action Bar (Telegram-style: one pill per used emoji)

    private func actionBar(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 6) {
            if trip.reactionBreakdown.isEmpty {
                if isOwn {
                    // Own trips can't be self-reacted (Strava rule). Replace
                    // the "React" CTA with quiet "no reactions yet" copy so
                    // the empty state isn't a button that does nothing.
                    HStack(spacing: 6) {
                        Image(systemName: "face.dashed")
                            .font(.system(size: 13, weight: .medium))
                        Text(lang.language == .ru ? "Пока нет реакций" : "No reactions yet")
                            .font(.inter(12, weight: .semibold))
                    }
                    .foregroundStyle(c.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                } else {
                    Button {
                        Haptics.selection()
                        onLongPress?()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 13, weight: .medium))
                            Text(lang.language == .ru ? "Реакция" : "React")
                                .font(.inter(12, weight: .semibold))
                        }
                        .foregroundStyle(c.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(c.cardAlt.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Show only the top-3 most popular reactions in the card — anything
                // extra lives in the trip detail's full reactions breakdown. Keeps the
                // action bar compact and removes the confusing horizontal scroll when
                // there are only a handful of reactions. Legacy prod emoji are
                // folded into their canonical keys BEFORE the top-3 cut, so a
                // trip with ❤️×2 + 👍×1 shows one 👍×3 pill, not two lookalikes.
                let top = ReactionEmoji.mergedTallies(trip.reactionBreakdown)
                    .prefix(3)
                HStack(spacing: 6) {
                    ForEach(Array(top), id: \.emoji) { tally in
                        reactionTallyPill(tally, c: c)
                    }
                    // "+" pill that opens the reaction palette is meaningless
                    // for owners — they can't react to their own trip. Hide it
                    // and let them tap any tally pill to see *who* reacted
                    // instead (handled below in `reactionTallyPill`).
                    if !isOwn {
                        Button {
                            Haptics.selection()
                            onLongPress?()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(c.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Capsule().fill(c.cardAlt.opacity(0.6)))
                                // Visual capsule stays 28pt; the tappable
                                // area meets the ≥34pt project floor.
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 6)

            // Comment affordance (Figma FeedCard footer-right) — comments
            // live in the trip detail, so this routes through `onTapCard`.
            // Share moved to the card's «…» menu.
            Button {
                Haptics.tap()
                onTapCard?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 16, weight: .medium))
                    Text("\(trip.commentCount)")
                        .font(.inter(12, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(c.textSecondary)
                // ≥34pt hit target (project floor) — the icon + 4pt padding
                // alone measured ~24pt and vertical misses were dead taps.
                .frame(minWidth: 34, minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.comments(lang.language))
            .accessibilityIdentifier("feed_card_comments")
        }
    }

    private func reactionTallyPill(_ tally: ReactionTally, c: AppTheme.Colors) -> some View {
        // Tallies arrive canonicalized (mergedTallies); my stored reaction
        // may still be a legacy emoji, so the ownership check must compare
        // through the same canonical lens.
        let isMine = trip.myReaction.map { ReactionEmoji.canonical($0) } == tally.emoji
        return Button {
            // Owner can't toggle their own reaction (Strava rule). Future
            // enhancement: tap should open the list of who reacted; for now
            // it's a no-op so we don't accidentally fire `onReact` from the
            // owner side and trigger a 4xx.
            guard !isOwn else { return }
            Haptics.selection()
            // Removing must send the RAW stored emoji — the store's
            // same-emoji check is what turns the POST into an unreact.
            // Sending the canonical key for a legacy reaction would
            // silently REPLACE ❤️ with 👍 instead of removing it.
            onReact?(isMine ? (trip.myReaction ?? tally.emoji) : tally.emoji)
        } label: {
            HStack(spacing: 4) {
                ReactionIconView(
                    emoji: tally.emoji,
                    size: 14,
                    filled: isMine,
                    tint: isMine ? AppTheme.accent : c.text
                )
                Text("\(tally.count)")
                    .font(.inter(12, weight: .bold).monospacedDigit())
                    .foregroundStyle(isMine ? AppTheme.accent : c.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isMine ? AppTheme.orangeDim : c.cardAlt)
            )
            .overlay(
                Capsule()
                    .stroke(isMine ? AppTheme.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatters

    /// Always a DOT decimal — FeedCard canon 115:61 renders «316.4» and the
    /// user explicitly confirmed the dot for this card (2026-08-06), so no
    /// RU-comma localization here.
    private func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func dateRegionText(isRu: Bool) -> String {
        let lang: LanguageManager.Language = isRu ? .ru : .en
        var result = RelativeTripDate.string(from: trip.startDate, language: lang)
        if let r = RegionDisplay.localized(trip.region, language: lang), !r.isEmpty {
            result += " · \(r)"
        }
        return result
    }
}

