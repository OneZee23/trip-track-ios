import SwiftUI

/// Strava-style feed card for social feed items (author's trips).
/// Visual layout mirrors FeedTripCardView but shows author row instead of vehicle,
/// plus an action bar with reactions + share.
struct SocialFeedCardView: View {
    let trip: SocialFeedTrip
    var onTapCard: (() -> Void)?
    var onTapAuthor: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onReact: ((String) -> Void)?
    var onShare: (() -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var showReport = false

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
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                onTapAuthor?()
            } label: {
                Circle()
                    .fill(AppTheme.accentBg)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text(trip.author.avatarEmoji ?? "🚗")
                            .font(.system(size: 17))
                    }
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                onTapAuthor?()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.author.displayName ?? (isRu ? "Пользователь" : "User"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(dateRegionText(isRu: isRu))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer()

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
            }

            Menu {
                Button {
                    Haptics.tap()
                    showReport = true
                } label: {
                    Label(isRu ? "Пожаловаться" : "Report", systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(c.textTertiary)
                    .frame(width: 28, height: 28)
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(target: .trip(trip.id))
                .environmentObject(lang)
        }
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

    private func metricsStrip(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 4) {
            metricBlock(
                value: String(format: "%.1f", trip.distanceKm),
                unit: AppStrings.km(lang.language),
                label: AppStrings.distance(lang.language),
                c: c
            )
            metricBlock(
                value: trip.formattedDuration,
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
                // No reactions yet — show a single "add reaction" pill
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
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(trip.reactionBreakdown, id: \.emoji) { tally in
                            reactionTallyPill(tally, c: c)
                        }
                        // Plus-picker pill at the end to add new emoji
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isRu ? "ru_RU" : "en_US")
        formatter.dateFormat = "d MMM"
        var result = formatter.string(from: trip.startDate)
        if let r = trip.region, !r.isEmpty {
            result += " · \(r)"
        }
        return result
    }
}
