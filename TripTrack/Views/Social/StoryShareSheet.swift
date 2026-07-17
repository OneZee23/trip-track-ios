import SwiftUI
import MapKit
import Photos
import UIKit

/// Decoupled data for the story preview — built from either a local `Trip`
/// or a `SocialFeedTrip`.
struct StoryShareData {
    let tripId: UUID
    let title: String
    let dateText: String
    let distanceKmText: String
    let durationText: String
    let avgSpeedKmhText: String
    let region: String?
    let coordinates: [CLLocationCoordinate2D]
    let authorEmoji: String
    let authorName: String
    /// Carried in the data (not read from the environment) so the poster
    /// localizes identically on screen and inside ImageRenderer exports.
    let language: LanguageManager.Language
}

extension StoryShareData {
    static func from(_ trip: SocialFeedTrip, lang: LanguageManager.Language) -> StoryShareData {
        let df = DateFormatter()
        df.locale = Locale(identifier: lang == .ru ? "ru_RU" : "en_US")
        df.dateFormat = "d MMM yyyy"
        return StoryShareData(
            tripId: trip.id,
            title: trip.title ?? df.string(from: trip.startDate),
            dateText: df.string(from: trip.startDate),
            distanceKmText: String(format: "%.1f", trip.distanceKm),
            // Compact format ("1ч 19м") fits the story card's metric strip
            // without the wider "1 ч 19 мин" wrapping or auto-shrinking.
            durationText: trip.formattedDurationCompact(lang),
            avgSpeedKmhText: String(format: "%.0f", trip.averageSpeedKmh),
            region: trip.region,
            coordinates: trip.previewCoordinates,
            authorEmoji: trip.author.avatarEmoji ?? "🚗",
            authorName: trip.author.displayName ?? (lang == .ru ? "Пользователь" : "User"),
            language: lang
        )
    }

    /// Build share data from a local `Trip` (own trip from TripDetail).
    static func from(_ trip: Trip, authorName: String, authorEmoji: String, lang: LanguageManager.Language) -> StoryShareData {
        let df = DateFormatter()
        df.locale = Locale(identifier: lang == .ru ? "ru_RU" : "en_US")
        df.dateFormat = "d MMM yyyy"
        return StoryShareData(
            tripId: trip.id,
            title: trip.title ?? df.string(from: trip.startDate),
            dateText: df.string(from: trip.startDate),
            distanceKmText: String(format: "%.1f", trip.distanceKm),
            durationText: trip.formattedDuration,
            avgSpeedKmhText: String(format: "%.0f", trip.averageSpeedKmh),
            region: trip.region,
            coordinates: trip.previewCoordinates,
            authorEmoji: authorEmoji,
            authorName: authorName,
            language: lang
        )
    }
}

struct StoryShareSheet: View {
    let data: StoryShareData
    let shareUrl: String?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var savedToPhotos = false
    @State private var linkCopied = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(spacing: 0) {
            // Custom header (Figma 117:1739) — «Поделиться» + close. The
            // system grabber comes from the presenting sheet's
            // `.presentationDragIndicator(.visible)`.
            HStack {
                Text(AppStrings.share(lang.language))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(c.text)
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(c.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 16) {
                    // Poster preview (Figma: 201×290, radius 18). The share
                    // image itself still renders at full 1080×1920.
                    previewCard
                        .frame(width: 201, height: 290)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.top, 8)

                    // Primary «Поделиться» + secondary «Сохранить».
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            shareImage()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(AppStrings.share(lang.language))
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Haptics.tap()
                            savePhoto()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "photo.on.rectangle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(savedToPhotos ? AppTheme.green : AppTheme.accent)
                                Text(savedToPhotos
                                     ? (isRu ? "Сохранено" : "Saved")
                                     : AppStrings.save(lang.language))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(c.text)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .surfaceCard(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                    // Link row — public share URL + «Копировать» chip.
                    if let shareUrl {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(c.textTertiary)
                            Text(shareUrl)
                                .font(.system(size: 12))
                                .foregroundStyle(c.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                Haptics.tap()
                                copyLink()
                            } label: {
                                Text(linkCopied
                                     ? (isRu ? "Скопировано" : "Copied")
                                     : AppStrings.copyAction(lang.language))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(linkCopied ? AppTheme.green : AppTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.accentBg, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .surfaceCard(cornerRadius: 14)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(c.bg)
        .presentationCornerRadius(22)
    }

    // MARK: - Preview card (used both in-sheet and for image rendering)

    private var previewCard: some View {
        StoryPreviewCard(data: data)
    }

    // MARK: - Actions

    @MainActor
    private func renderStoryImage() -> UIImage? {
        let renderer = ImageRenderer(content:
            StoryPreviewCard(data: data)
                .frame(width: 1080, height: 1920)
                .environmentObject(lang)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1.0
        return renderer.uiImage
    }

    private func shareImage() {
        guard let image = renderStoryImage() else { return }
        var items: [Any] = [image]
        if let shareUrl, let url = URL(string: shareUrl) {
            items.append(url)
        }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topPresentedViewController()?.present(av, animated: true)
    }

    /// Walks up the presentation chain to find the topmost presented view controller.
    /// Needed because StoryShareSheet itself is a SwiftUI sheet on top of the root,
    /// so presenting directly on root fails with "already presenting" warning.
    private func topPresentedViewController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    private func savePhoto() {
        guard let image = renderStoryImage() else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                Task { @MainActor in
                    if success {
                        savedToPhotos = true
                        Haptics.success()
                    }
                }
            }
        }
    }

    private func copyLink() {
        guard let shareUrl else { return }
        UIPasteboard.general.string = shareUrl
        linkCopied = true
        Haptics.success()
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { linkCopied = false }
        }
    }
}

// MARK: - StoryPreviewCard (the actual 9:16 design)

struct StoryPreviewCard: View {
    let data: StoryShareData

    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        ZStack {
            // Navy poster gradient — same constants as the shipped
            // trip-detail PosterRouteCanvas (#29364F → #161B2C), one poster
            // identity across the app (FORK-10).
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0x29/255, green: 0x36/255, blue: 0x4F/255), location: 0.07),
                    .init(color: Color(red: 0x16/255, green: 0x1B/255, blue: 0x2C/255), location: 0.79)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Brand header
                    HStack(spacing: 8) {
                        Image("PixelCar")
                            .resizable()
                            .scaledToFit()
                            .frame(height: geo.size.height * 0.028)
                        // Product wordmark (Figma 117:1739) — this poster is
                        // the one asset users export outside the app, it must
                        // carry the real product name.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TRIP")
                                .font(.custom("PressStart2P-Regular", size: geo.size.height * 0.014))
                                .foregroundStyle(AppTheme.accent)
                            Text("TRACK")
                                .font(.custom("PressStart2P-Regular", size: geo.size.height * 0.014))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, geo.size.width * 0.06)
                    .padding(.top, geo.size.height * 0.05)

                    Spacer(minLength: 0)

                    // Map center, ~55% of height
                    ZStack {
                        RoundedRectangle(cornerRadius: geo.size.width * 0.05)
                            .fill(Color.white.opacity(0.04))

                        if data.coordinates.count > 1 {
                            // Poster-style route render — deterministic (no
                            // async tile snapshot), so ImageRenderer always
                            // captures the full route. Same navy poster
                            // surface as the trip-detail hero.
                            PosterRouteCanvas(
                                coordinates: data.coordinates,
                                speeds: [],
                                style: .poster
                            )
                            .clipShape(RoundedRectangle(cornerRadius: geo.size.width * 0.05))
                            .padding(geo.size.width * 0.04)
                        } else {
                            Image(systemName: "map")
                                .font(.system(size: 72, weight: .light))
                                .foregroundStyle(Color.white.opacity(0.2))
                        }
                    }
                    .frame(width: geo.size.width * 0.85,
                           height: geo.size.height * 0.48)
                    .overlay(
                        RoundedRectangle(cornerRadius: geo.size.width * 0.05)
                            .stroke(AppTheme.accent.opacity(0.15), lineWidth: 1)
                    )

                    Spacer(minLength: 0)

                    // Bottom info
                    VStack(alignment: .leading, spacing: geo.size.height * 0.018) {
                        Text(data.title)
                            .font(.system(size: geo.size.height * 0.033, weight: .heavy))
                            .tracking(-0.3)
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: geo.size.width * 0.05) {
                            metricCell(
                                value: data.distanceKmText,
                                unit: AppStrings.km(data.language),
                                fontScale: geo.size.height * 0.028
                            )
                            metricCell(
                                value: data.durationText,
                                unit: AppStrings.duration(data.language).lowercased(),
                                fontScale: geo.size.height * 0.028
                            )
                            metricCell(
                                value: data.avgSpeedKmhText,
                                unit: AppStrings.kmh(data.language),
                                fontScale: geo.size.height * 0.028
                            )
                        }
                        .padding(.top, geo.size.height * 0.012)

                        // Author footer
                        HStack(spacing: 8) {
                            Text(data.authorEmoji)
                                .font(.system(size: geo.size.height * 0.024))
                                .frame(width: geo.size.height * 0.04,
                                       height: geo.size.height * 0.04)
                                .background(Circle().fill(AppTheme.accentBg))
                            Text(data.authorName)
                                .font(.system(size: geo.size.height * 0.017, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                            if let region = data.region, !region.isEmpty {
                                Text("·")
                                    .foregroundStyle(Color.white.opacity(0.3))
                                Text(region)
                                    .font(.system(size: geo.size.height * 0.015))
                                    .foregroundStyle(Color.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.top, geo.size.height * 0.02)
                    }
                    .padding(.horizontal, geo.size.width * 0.07)
                    .padding(.bottom, geo.size.height * 0.07)
                }
            }
        }
    }

    private func metricCell(value: String, unit: String, fontScale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: fontScale, weight: .heavy).monospacedDigit())
                .tracking(-0.4)
                .foregroundStyle(Color.white)
            Text(unit)
                .font(.system(size: fontScale * 0.38, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(AppTheme.accent)
                .textCase(.uppercase)
        }
    }
}
