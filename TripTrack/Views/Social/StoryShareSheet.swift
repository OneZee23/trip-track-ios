import SwiftUI
import MapKit
import Photos
import UIKit

/// Decoupled data for the story preview — built from either a local `Trip`
/// or a `SocialFeedTrip`.
struct StoryShareData {
    let title: String
    let dateText: String
    let distanceKmText: String
    let durationText: String
    let avgSpeedKmhText: String
    let region: String?
    let coordinates: [CLLocationCoordinate2D]
    let authorEmoji: String
    let authorName: String
}

extension StoryShareData {
    static func from(_ trip: SocialFeedTrip, lang: LanguageManager.Language) -> StoryShareData {
        let df = DateFormatter()
        df.locale = Locale(identifier: lang == .ru ? "ru_RU" : "en_US")
        df.dateFormat = "d MMM yyyy"
        return StoryShareData(
            title: trip.title ?? df.string(from: trip.startDate),
            dateText: df.string(from: trip.startDate),
            distanceKmText: String(format: "%.1f", trip.distanceKm),
            durationText: trip.formattedDuration,
            avgSpeedKmhText: String(format: "%.0f", trip.averageSpeedKmh),
            region: trip.region,
            coordinates: trip.previewCoordinates,
            authorEmoji: trip.author.avatarEmoji ?? "🚗",
            authorName: trip.author.displayName ?? (lang == .ru ? "Пользователь" : "User")
        )
    }
}

struct StoryShareSheet: View {
    let data: StoryShareData
    let shareUrl: String

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var savedToPhotos = false
    @State private var linkCopied = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard
                        .frame(maxWidth: .infinity)
                        .aspectRatio(9.0/16.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        actionButton(
                            icon: "square.and.arrow.up",
                            title: isRu ? "Поделиться" : "Share",
                            subtitle: isRu ? "Картинка + ссылка" : "Image + link",
                            isPrimary: true,
                            c: c,
                            action: shareImage
                        )
                        actionButton(
                            icon: savedToPhotos ? "checkmark.circle.fill" : "photo.on.rectangle",
                            title: savedToPhotos
                                ? (isRu ? "Сохранено" : "Saved")
                                : (isRu ? "Сохранить в Фото" : "Save to Photos"),
                            subtitle: isRu
                                ? "Для загрузки в сторис вручную"
                                : "Upload to your story manually",
                            isPrimary: false,
                            c: c,
                            action: savePhoto
                        )
                        actionButton(
                            icon: linkCopied ? "checkmark.circle.fill" : "link",
                            title: linkCopied
                                ? (isRu ? "Ссылка скопирована" : "Link copied")
                                : (isRu ? "Скопировать ссылку" : "Copy link"),
                            subtitle: shareUrl,
                            isPrimary: false,
                            c: c,
                            action: copyLink
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(c.bg)
            .navigationTitle(isRu ? "Поделиться поездкой" : "Share trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
        }
    }

    // MARK: - Preview card (used both in-sheet and for image rendering)

    private var previewCard: some View {
        StoryPreviewCard(data: data)
    }

    // MARK: - Action button

    private func actionButton(
        icon: String,
        title: String,
        subtitle: String,
        isPrimary: Bool,
        c: AppTheme.Colors,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isPrimary ? .white : AppTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isPrimary ? AppTheme.accent : AppTheme.accentBg)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
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
        guard let url = URL(string: shareUrl) else { return }
        let av = UIActivityViewController(activityItems: [image, url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?
            .present(av, animated: true)
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
            // Dark background gradient
            LinearGradient(
                colors: [
                    Color(red: 12/255, green: 14/255, blue: 18/255),
                    Color(red: 24/255, green: 20/255, blue: 16/255)
                ],
                startPoint: .top, endPoint: .bottom
            )

            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Brand header
                    HStack(spacing: 8) {
                        Image("PixelCar")
                            .resizable()
                            .scaledToFit()
                            .frame(height: geo.size.height * 0.028)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ROAD  TRIP")
                                .font(.custom("PressStart2P-Regular", size: geo.size.height * 0.014))
                                .foregroundStyle(AppTheme.accent)
                            Text("TRACKER")
                                .font(.system(size: geo.size.height * 0.015, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .tracking(2)
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
                            LightRoutePreview(
                                coordinates: data.coordinates
                            )
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
                                unit: "km",
                                fontScale: geo.size.height * 0.028
                            )
                            metricCell(
                                value: data.durationText,
                                unit: "time",
                                fontScale: geo.size.height * 0.028
                            )
                            metricCell(
                                value: data.avgSpeedKmhText,
                                unit: "km/h",
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
