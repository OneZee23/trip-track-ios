import SwiftUI

/// «История» entry in LIST mode (Figma 1864:321). The canon draws the exact
/// FeedCard master here, so this is `SocialFeedCardView`'s geometry rebuilt
/// around a LOCAL `Trip` instead of a server `SocialFeedTrip`: same 13pt
/// gutter, same Inter runs, same three-column metric strip.
///
/// The track slot is a REAL map. Figma paints it as a flat beige plate only
/// because Figma can't render tiles — porting that beige would ship the
/// "map failed to load" look the user rejected on the feed (2026-08-06).
struct ProfileTripCardView: View {
    let trip: Trip
    let level: Int
    /// The vehicle this trip was driven in, when it still exists in the garage.
    /// Nil for trips recorded without one, and for a vehicle since deleted.
    var vehicle: Vehicle? = nil
    let onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    /// Which average speed the user asked for (overall vs moving-only) is a
    /// setting, and the trip detail this card opens honours it. Observing the
    /// singleton — ProfileView's own pattern for it — keeps the card from
    /// printing a different number than the screen one tap deeper.
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        Button {
            Haptics.tap()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                authorRow(c)
                    .padding(.horizontal, 13)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                Text(titleText)
                    .font(.inter(17, weight: .heavy))
                    .tracking(-0.085)
                    .foregroundStyle(c.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 10)

                mapSection(c)

                metricsStrip(c)
                    .padding(.horizontal, 13)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                // Canon closes the card with a reaction + comment footer. Both
                // counts live on the server, and a local trip — one that was
                // never published, or published from another device — has none
                // to read, so the footer could only ever print a fabricated
                // «0». The card ends at the metric strip instead.
            }
            // Canon is drawn on a 360pt artboard; the card has to breathe out
            // to whatever width the device gives it, never pin to 332.
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile_trip_card")
    }

    // MARK: - Author Row

    /// One line: the level held when this was driven, the date and place, and
    /// what it was driven in. No avatar and no name.
    ///
    /// This card is a port of the FeedCard master, where that chrome tells you
    /// about a stranger. In your OWN history it tells you who you are, which
    /// you know — a tester put it exactly that way. The level survives only
    /// because it is now the level held AT THE TIME: a drive from two years ago
    /// says LVL 3 while yesterday says LVL 9. That is a fact about the drive
    /// rather than about the account, and reading down the list is the one
    /// place the app shows growth as a shape instead of a number.
    private func authorRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 7) {
            Text("LVL \(level)")
                // fixedSize twice over: the FONT must not rescale with Dynamic
                // Type (custom faces do, the SF chrome beside them does not),
                // and the LAYOUT must not compress — the line truncates on the
                // place name before the tag gives up a point.
                .font(.custom("Handjet-Black", fixedSize: 13))
                .foregroundStyle(AppTheme.gold)
                .fixedSize()

            Text(dateRegionText)
                .font(.inter(11))
                .foregroundStyle(c.textTertiary)
                .lineLimit(1)

            if let vehicle, let asset = vehicle.avatarImageName {
                // «Which car was this?» is a caption-weight fact, so it rides
                // on this line rather than growing the card a row of its own.
                Text("·")
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
                    .fixedSize()
                Image(asset)
                    .resizable()
                    // After `resizable()`, as at every pixel-art call site.
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 22, height: 14)
                    .fixedSize()
                Text(vehicleLabel(vehicle))
                    .font(.inter(11, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            Spacer(minLength: 6)

            // Canon hangs a «⋯» menu off this slot. Everything that menu opens
            // on the feed (edit / share / make private / delete) is either
            // already one tap deeper in the trip detail or meaningless for a
            // local trip, so the slot would open an empty sheet. It carries the
            // privacy state instead — the one fact the ProfileTripRow this card
            // replaces showed and that would otherwise be lost from История.
            if trip.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(c.textTertiary)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.green)
            }
        }
    }

    // MARK: - Map

    @ViewBuilder
    private func mapSection(_ c: AppTheme.Colors) -> some View {
        let coords = trip.previewCoordinates
        if coords.count > 1 {
            MapSnapshotPreview(coordinates: coords, tripId: trip.id, height: 178)
                .frame(height: 178)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            // The `count > 1` guard has to stay: with fewer points
            // MapSnapshotPreview bails BEFORE it can mark itself failed, so it
            // would shimmer forever. Dropping the whole 178pt band instead is
            // worse — the card collapses into a stub between full-height
            // neighbours — so the empty case gets that view's own failed
            // chrome, glyph centred since there's no faded route to defer to.
            ZStack {
                Rectangle().fill(c.cardAlt)
                Image(systemName: "map.slash")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .frame(height: 178)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Metrics

    private func metricsStrip(_ c: AppTheme.Colors) -> some View {
        // 4, matching the FeedCard master this card is ported from — the same
        // trip is laid out by both, and a 1pt disagreement shows when you
        // scroll from the feed into your own history.
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
                value: String(format: "%.0f", trip.displayAverageSpeedKmh(settings.avgSpeedMode)),
                unit: AppStrings.kmh(lang.language),
                label: AppStrings.avgSpeedShort(lang.language),
                c: c
            )
        }
    }

    /// The garage name, or the silhouette's own word when the vehicle was
    /// never named — «Кроссовер» beats an empty gap.
    private func vehicleLabel(_ vehicle: Vehicle) -> String {
        let name = vehicle.name.trimmingCharacters(in: .whitespaces)
        guard name.isEmpty else { return name }
        return AppStrings.avatarStyleName(lang.language, style: vehicle.avatarStyle)
    }

    /// Inter ExtraBold, not SF Heavy: nominally the same 800 weight, visibly
    /// thinner against the Figma render (the feed metrics bit us on exactly
    /// this). Static so a long history doesn't rebuild a Font per row.
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

    /// One metric column: value runs, 5pt, then the caps caption.
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

    /// «18 ч 05 мин» / "18 h 05 min" — numbers big (19), unit words small
    /// (11), one `Text` so the runs share a baseline. Minutes are zero-padded
    /// ONLY next to an hours run, the way canon 1864:321 prints them; a
    /// sub-hour trip must read «42 мин», never «05 мин».
    private func durationRuns(_ c: AppTheme.Colors) -> Text {
        let big = Self.metricValueFont
        let small = Font.inter(11, weight: .semibold)
        let total = Int(trip.duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        guard h > 0 else {
            return Text("\(m)").font(big).foregroundColor(c.text)
                + Text(" \(AppStrings.minutesUnitShort(lang.language))")
                    .font(small).foregroundColor(c.textSecondary)
        }
        return Text("\(h)").font(big).foregroundColor(c.text)
            + Text(" \(AppStrings.hoursUnitShort(lang.language)) ")
                .font(small).foregroundColor(c.textSecondary)
            + Text(String(format: "%02d", m)).font(big).foregroundColor(c.text)
            + Text(" \(AppStrings.minutesUnitShort(lang.language))")
                .font(small).foregroundColor(c.textSecondary)
    }

    // MARK: - Text

    /// Dot decimal even in RU: the feed card prints «316.4» for the very same
    /// trip after the user signed that off (2026-08-06), and the two cards
    /// must not disagree over one glyph.
    private func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// The same answer `TripDetailView` gives, so a card and the screen it opens
    /// can never name one trip two ways. An unnamed trip is headed by its
    /// region — repeating the date here, in the heading AND in the meta line
    /// under it, is what the detail screen already refuses to do.
    /// `TripAutoTitle.localized` re-renders titles frozen in the recording
    /// locale; real user titles pass through untouched.
    private var titleText: String {
        if trip.hasDisplayableName,
           let t = TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language),
           !t.isEmpty {
            return t
        }
        if let region = RegionDisplay.localized(trip.region, language: lang.language), !region.isEmpty {
            return region
        }
        return ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language)
    }

    /// «6 апр · Кабардино-Балкария». The region run is dropped whole when the
    /// trip has none, so the line never ends on a dangling separator — and
    /// also when the trip is unnamed, because then the region IS the heading
    /// two lines below and printing it twice tells the reader nothing new.
    private var dateRegionText: String {
        var parts = [ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language)]
        if trip.hasDisplayableName,
           let region = RegionDisplay.localized(trip.region, language: lang.language), !region.isEmpty {
            parts.append(region)
        }
        return parts.joined(separator: " · ")
    }
}
