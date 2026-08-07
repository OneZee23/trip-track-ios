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
                    NavCircleIcon(systemImage: "xmark")
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
                                Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "arrow.down.to.line")
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

// MARK: - StoryPreviewCard (canon 117:1739 — «02 · Лента · Шеринг (A постер)»)

/// The exported poster. Canon is a full-bleed route on navy: the track runs
/// corner to corner with a speed-style gradient (green at the start, red at
/// the finish), the wordmark rides the top-left, and the trip's name and
/// numbers sit in the bottom-left over the artwork.
///
/// It used to draw the route inside a small rounded inset with a pixel car on
/// it, plus a date line and an author footer — the route ended up a thumbnail
/// in the middle of a form, which is the opposite of what a shareable card is
/// for.
///
/// Everything scales off the rendered width (canon is drawn at 201pt wide), so
/// the same view is exact both as the 201×290 in-sheet preview and as the
/// 1080×1920 export.
struct StoryPreviewCard: View {
    let data: StoryShareData

    @EnvironmentObject private var lang: LanguageManager

    /// Canon poster width — every size below is expressed as a ratio of it.
    private static let canonWidth: CGFloat = 201

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / Self.canonWidth
            ZStack(alignment: .topLeading) {
                // Navy poster gradient — same constants as the trip-detail
                // hero, one poster identity across the app (FORK-10).
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0x29/255, green: 0x36/255, blue: 0x4F/255), location: 0.07),
                        .init(color: Color(red: 0x16/255, green: 0x1B/255, blue: 0x2C/255), location: 0.79)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                if data.coordinates.count > 1 {
                    SharePosterRoute(coordinates: data.coordinates, lineWidth: 7 * s)
                        .padding(.horizontal, 18 * s)
                        .padding(.top, 30 * s)
                        // Clear of the title block at the bottom.
                        .padding(.bottom, 86 * s)
                }

                // Wordmark (canon 117:1770): car + «TRIP TRACK» on one line.
                HStack(spacing: 8 * s) {
                    Image("PixelCar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22 * s, height: 22 * s)
                    Text("TRIP TRACK")
                        .font(.custom("PressStart2P-Regular", fixedSize: 7 * s))
                        .tracking(1.2 * s)
                        .foregroundStyle(.white)
                }
                .padding(.leading, 14 * s)
                .padding(.top, 14 * s)

                // Title + metrics (canon 117:1773), bottom-left over the art.
                VStack(alignment: .leading, spacing: 8 * s) {
                    Text(data.title)
                        .font(.system(size: 19 * s, weight: .heavy))
                        .tracking(-0.4 * s)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.35), radius: 6 * s, y: 1 * s)

                    HStack(alignment: .firstTextBaseline, spacing: 10 * s) {
                        metric(data.distanceKmText, unit: AppStrings.km(data.language), s: s)
                        metric(data.durationText, unit: nil, s: s)
                        metric(data.avgSpeedKmhText, unit: AppStrings.kmh(data.language), s: s)
                    }
                }
                .padding(.leading, 16 * s)
                .padding(.trailing, 14 * s)
                .padding(.bottom, 20 * s)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    /// Value in white bold with a small grey unit riding its baseline —
    /// «158.2 км  2:14  72 км/ч» reads as one line of numbers, not as a
    /// three-column table with shouty orange captions.
    private func metric(_ value: String, unit: String?, s: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2 * s) {
            Text(value)
                .font(.system(size: 17 * s, weight: .heavy).monospacedDigit())
                .tracking(-0.3 * s)
                .foregroundStyle(.white)
            if let unit {
                Text(unit)
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6 * s, y: 1 * s)
    }
}

/// The route itself: one stroked path across the whole card, coloured start →
/// finish, with a green dot where the drive began and a white one where it
/// ended. Deterministic vector drawing (no async map snapshot) so
/// `ImageRenderer` always captures a complete route in the export.
private struct SharePosterRoute: View {
    let coordinates: [CLLocationCoordinate2D]
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let pts = projected(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    routePath(pts)
                        .stroke(
                            gradient(from: pts[0], to: pts[pts.count - 1], in: geo.size),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: .black.opacity(0.35), radius: lineWidth * 0.8, y: lineWidth * 0.2)

                    endDot(at: pts[0], fill: Color(red: 0x5A/255, green: 0xC8/255, blue: 0x3C/255))
                    endDot(at: pts[pts.count - 1], fill: .white)
                }
            }
        }
    }

    private func routePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])
        // Quadratic smoothing through midpoints — a polyline of GPS samples
        // reads as a jagged scribble at poster scale.
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                              y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    /// Start-to-finish gradient, aligned to the actual travel direction so
    /// the green end is always where the drive began.
    private func gradient(from: CGPoint, to: CGPoint, in size: CGSize) -> LinearGradient {
        // UnitPoint is fractional — feeding it raw pixel coordinates would
        // put both ends far off-canvas and flatten the gradient to one colour.
        let start = UnitPoint(x: from.x / max(size.width, 1), y: from.y / max(size.height, 1))
        let end = UnitPoint(x: to.x / max(size.width, 1), y: to.y / max(size.height, 1))
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0x7A/255, green: 0xC8/255, blue: 0x28/255), location: 0.0),
                .init(color: Color(red: 0xE8/255, green: 0xC4/255, blue: 0x1E/255), location: 0.45),
                .init(color: Color(red: 0xF0/255, green: 0x7B/255, blue: 0x1E/255), location: 0.75),
                .init(color: Color(red: 0xE0/255, green: 0x3B/255, blue: 0x2C/255), location: 1.0),
            ],
            startPoint: start, endPoint: end
        )
    }

    private func endDot(at p: CGPoint, fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: lineWidth * 1.45, height: lineWidth * 1.45)
            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: lineWidth * 0.18))
            .position(p)
    }

    /// Equirectangular projection into the given rect, aspect-preserved and
    /// centred, with the latitude axis flipped so north is up.
    private func projected(in size: CGSize) -> [CGPoint] {
        guard coordinates.count > 1, size.width > 0, size.height > 0 else { return [] }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return [] }
        // Longitude degrees shrink with latitude — without this correction a
        // north-south drive renders squashed sideways.
        let latMid = (minLat + maxLat) / 2
        let lonScale = max(0.15, cos(latMid * .pi / 180))
        let spanX = max((maxLon - minLon) * lonScale, 1e-6)
        let spanY = max(maxLat - minLat, 1e-6)
        let inset = lineWidth
        let usable = CGSize(width: max(size.width - inset * 2, 1),
                            height: max(size.height - inset * 2, 1))
        let scale = min(usable.width / spanX, usable.height / spanY)
        let drawn = CGSize(width: spanX * scale, height: spanY * scale)
        let originX = inset + (usable.width - drawn.width) / 2
        let originY = inset + (usable.height - drawn.height) / 2
        return coordinates.map { c in
            CGPoint(
                x: originX + (c.longitude - minLon) * lonScale * scale,
                y: originY + (maxLat - c.latitude) * scale
            )
        }
    }
}
