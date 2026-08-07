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

    @State private var format: SharePosterFormat = .poster
    /// Tiles for the selected format. Nil = still loading (or a route the
    /// snapshotter can't serve) — the card falls back to navy meanwhile.
    @State private var posterMap: SharePosterMap?
    @State private var isLoadingMap = false
    @State private var savedToPhotos = false
    @State private var linkCopied = false

    /// Preview height is fixed; the width follows the chosen aspect so the
    /// chips visibly change the SHAPE of the card, not just its contents.
    private static let previewHeight: CGFloat = 290

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(spacing: 0) {
            header(c)
            formatChips(c)

            ScrollView {
                VStack(spacing: 14) {
                    preview(c)

                    Text(AppStrings.shareCardCaption(lang.language))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    actionButtons(c, isRu: isRu)

                    if let shareUrl {
                        linkRow(shareUrl, c: c, isRu: isRu)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(c.bg)
        .presentationCornerRadius(22)
        .task(id: format) { await loadMap() }
    }

    // MARK: - Header + chips

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(AppStrings.shareTripTitle(lang.language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                NavCircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.closeSheet(lang.language))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func formatChips(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            ForEach(SharePosterFormat.allCases) { item in
                let isOn = format == item
                Button {
                    Haptics.selection()
                    withAnimation(.easeOut(duration: 0.22)) { format = item }
                } label: {
                    Text(item.title(lang.language))
                        .font(.system(size: 13, weight: isOn ? .bold : .semibold))
                        .foregroundStyle(isOn ? AppTheme.accent : c.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(c.card, in: Capsule())
                        // `strokeBorder` — a centred stroke would be clipped
                        // by the row's bounds.
                        .overlay(Capsule().strokeBorder(isOn ? AppTheme.accent : .clear, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Preview

    private func preview(_ c: AppTheme.Colors) -> some View {
        let height = Self.previewHeight
        let width = height * format.aspect
        return ZStack {
            if format.isTransparent {
                // Checkerboard so «Стикер PNG» reads as transparent rather
                // than as a card with a grey background.
                TransparencyChecker()
            }
            SharePosterView(data: data, format: format, map: posterMap)
            if isLoadingMap && format.showsMap && posterMap == nil {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .animation(.easeOut(duration: 0.25), value: format)
        .animation(.easeOut(duration: 0.3), value: posterMap != nil)
    }

    // MARK: - Buttons

    private func actionButtons(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                shareImage()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text(AppStrings.share(lang.language))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                savePhoto()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "arrow.down.to.line")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(savedToPhotos ? AppTheme.green : c.text)
                    Text(savedToPhotos
                         ? (isRu ? "Сохранено" : "Saved")
                         : AppStrings.save(lang.language))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(c.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func linkRow(_ url: String, c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            Text(url)
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
                     : AppStrings.shareCopyLink(lang.language))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(linkCopied ? AppTheme.green : AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.accentBg, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(c.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .padding(.horizontal, 16)
    }

    // MARK: - Map

    private func loadMap() async {
        guard format.showsMap else {
            posterMap = nil
            return
        }
        posterMap = nil
        isLoadingMap = true
        defer { isLoadingMap = false }
        posterMap = await SharePosterRenderer.map(
            for: data.coordinates, tripId: data.tripId, format: format
        )
    }

    // MARK: - Export

    @MainActor
    private func renderImage() -> UIImage? {
        let size = format.exportSize
        let renderer = ImageRenderer(content:
            SharePosterView(data: data, format: format, map: posterMap)
                .frame(width: size.width, height: size.height)
                .environmentObject(lang)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1.0
        // Stickers keep their alpha; cards flatten onto their own artwork.
        renderer.isOpaque = !format.isTransparent
        return renderer.uiImage
    }

    private func shareImage() {
        guard let image = renderImage() else { return }
        var items: [Any] = [image]
        if let shareUrl, let url = URL(string: shareUrl) {
            items.append(url)
        }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topPresentedViewController()?.present(av, animated: true)
    }

    /// Walks up the presentation chain to find the topmost presented view
    /// controller — this sheet is itself presented, so presenting on the root
    /// fails with "already presenting".
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
        guard let image = renderImage() else { return }
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

/// Grey checkerboard behind the sticker preview — the universal "this part
/// is transparent" cue.
private struct TransparencyChecker: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 10
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.9)))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : step
                while x < size.width {
                    ctx.fill(
                        Path(CGRect(x: x, y: y, width: step, height: step)),
                        with: .color(.black.opacity(0.07))
                    )
                    x += step * 2
                }
                y += step
                row += 1
            }
        }
    }
}
