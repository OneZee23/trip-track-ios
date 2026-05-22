import SwiftUI

/// Strava-style feed card for social feed items (author's trips).
/// Visual layout mirrors FeedTripCardView but shows author row instead of vehicle,
/// plus an action bar with reactions + share.
struct SocialFeedCardView: View {
    let trip: SocialFeedTrip
    /// When true, the card is rendered for the signed-in user's own trip — hides the
    /// report menu and "Reaction" pill, and swaps the author row for a vehicle-style
    /// header that matches the look of trips in the "Мои" tab.
    var isOwn: Bool = false
    /// Local Vehicle struct used to render the header on own-trip cards. If the vehicle
    /// has a pixel avatar we render the PNG instead of trying to draw the asset name
    /// as text.
    var ownVehicle: Vehicle?
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
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            // Body is wrapped so we can attach both tap + long-press gestures.
            VStack(alignment: .leading, spacing: 0) {
                if let title = trip.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 17, weight: .heavy))
                        .tracking(-0.1)
                        .foregroundStyle(c.text)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }

                mapSection(c)

                metricsStrip(c)
                    .padding(.horizontal, 14)
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

            if !trip.badgeIds.isEmpty {
                TripBadgesRow(badgeIds: trip.badgeIds, maxVisible: 4, size: 22)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            actionBar(c)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(c.border)
                        .frame(height: 0.5)
                }
        }
        .surfaceCard(cornerRadius: 16)
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
                .fill(AppTheme.accentBg)
                .frame(width: 34, height: 34)
                .overlay {
                    Text(trip.author.avatarEmoji ?? "🙂")
                        .font(.system(size: 17))
                }
                .onTapGesture {
                    Haptics.tap()
                    onTapAuthor?()
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(headerName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        // `truncationMode: .tail` is the default but be explicit
                        // since a long name + "Вы" pill needs the truncation
                        // to land on the name, not somewhere weird in the pill.
                        .truncationMode(.tail)
                    if isOwn {
                        // Subtle "this is you" badge — explicit signal that
                        // the card is yours without breaking the unified
                        // chrome. NN/g recognition heuristic. `fixedSize`
                        // stops the pill from being squeezed by a long name —
                        // the name truncates first, the pill stays full size.
                        Text(isRu ? "Вы" : "You")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accentBg, in: Capsule())
                            .fixedSize()
                    }
                }
                Text(dateRegionText(isRu: isRu))
                    .font(.system(size: 11))
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

            if isFreshlyPublished {
                Text(isRu ? "НОВОЕ" : "NEW")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent, in: Capsule())
                    .fixedSize()
            }

            if trip.photoCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                    Text("+\(trip.photoCount)")
                        .font(.system(size: 12, weight: .bold))
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
        }
    }

    /// True when the trip ended within the freshness window. Lives in the
    /// outer HStack of `authorRow` so the pill can never overlap the inline
    /// "Вы" badge that sits inside the name VStack — they're in different
    /// stacks so SwiftUI lays them out independently.
    private var isFreshlyPublished: Bool {
        let publishedAt = trip.endDate ?? trip.startDate
        return Date().timeIntervalSince(publishedAt) < 12 * 3600
    }

    // MARK: - Map

    @ViewBuilder
    private func mapSection(_ c: AppTheme.Colors) -> some View {
        let coords = trip.previewCoordinates
        if coords.count > 1 {
            MapSnapshotPreview(coordinates: coords, tripId: trip.id, height: 180)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
        }
    }

    // MARK: - Metrics

    @ViewBuilder
    private func metricsStrip(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                metricBlock(
                    value: String(format: "%.1f", trip.distanceKm),
                    unit: AppStrings.km(lang.language),
                    label: AppStrings.distance(lang.language),
                    c: c
                )
                metricBlock(
                    value: trip.formattedDurationCompact(lang.language),
                    unit: "",
                    label: AppStrings.duration(lang.language),
                    c: c
                )
                metricBlock(
                    value: String(format: "%.0f", trip.averageSpeedKmh),
                    unit: AppStrings.kmh(lang.language),
                    label: AppStrings.avgSpeed(lang.language),
                    c: c
                )
            }
            // Vehicle metadata sits BELOW the metrics row on every trip —
            // server now returns it on `SocialFeedTrip.vehicle` for own and
            // others' alike, so cards stay visually identical regardless of
            // who recorded the trip. The "what car was this in?" line is
            // metadata, not identity (the avatar slot handles identity).
            if let v = trip.vehicle {
                let trimmedName = v.name.trimmingCharacters(in: .whitespaces)
                if !trimmedName.isEmpty {
                    HStack(spacing: 6) {
                        // Pixel-car asset names are stored as `pixel_car_*`
                        // in `avatarEmoji`. The PNGs live in the iOS bundle,
                        // so they render for any author — own or others alike.
                        // Without this the asset name renders as literal text.
                        if v.isPixelAvatar {
                            Image(v.avatarEmoji)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        } else {
                            Text(v.avatarEmoji)
                                .font(.system(size: 12))
                        }
                        Text(trimmedName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func metricBlock(value: String, unit: String, label: String, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy).monospacedDigit())
                    .tracking(-0.2)
                    .foregroundStyle(c.text)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                }
            }
            .lineLimit(1)

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .font(.system(size: 12, weight: .semibold))
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
                                .font(.system(size: 12, weight: .semibold))
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
                // there are only a handful of reactions.
                let top = trip.reactionBreakdown
                    .sorted { $0.count > $1.count }
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
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 6)

            Button {
                Haptics.tap()
                onShare?()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private func reactionTallyPill(_ tally: ReactionTally, c: AppTheme.Colors) -> some View {
        let isMine = trip.myReaction == tally.emoji
        return Button {
            // Owner can't toggle their own reaction (Strava rule). Future
            // enhancement: tap should open the list of who reacted; for now
            // it's a no-op so we don't accidentally fire `onReact` from the
            // owner side and trigger a 4xx.
            guard !isOwn else { return }
            Haptics.selection()
            onReact?(tally.emoji)
        } label: {
            HStack(spacing: 4) {
                Text(tally.emoji)
                    .font(.system(size: 14))
                Text("\(tally.count)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(isMine ? AppTheme.accent : c.textSecondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isMine ? AppTheme.accentBg : c.cardAlt.opacity(0.6))
            )
            .overlay(
                Capsule()
                    .stroke(isMine ? AppTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatters

    private func dateRegionText(isRu: Bool) -> String {
        var result = RelativeTripDate.string(
            from: trip.startDate,
            language: isRu ? .ru : .en)
        if let r = trip.region, !r.isEmpty {
            result += " · \(r)"
        }
        return result
    }
}
