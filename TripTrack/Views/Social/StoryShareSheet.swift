import SwiftUI
import MapKit
import Photos
import UIKit

/// Where the «Фото-фон» card's photo comes from. Our own trips read the file
/// in Documents; someone else's arrives as the 200px feed thumbnail, which is
/// mush blown up to a 1080px export — so for those the sheet re-presigns the
/// full-size original and only uses the thumbnail as the placeholder under it.
enum SharePosterPhotoSource: Hashable {
    case local(filename: String)
    case remote(thumbnail: String?)
}

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
    /// First photo of the trip, for the «Фото-фон» card. Nil = this trip has
    /// no photo, and that chip stays greyed out.
    let photoSource: SharePosterPhotoSource?
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
            // `photoCount`, not `firstPhotoThumbnail`: the thumbnail can still
            // be presigning while the count is already right, and the chip
            // should offer itself for any trip that has a photo at all.
            photoSource: trip.photoCount > 0
                ? SharePosterPhotoSource.remote(thumbnail: trip.firstPhotoThumbnail)
                : nil,
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
            photoSource: trip.photos.first.map { SharePosterPhotoSource.local(filename: $0.filename) },
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

    /// The two axes the card is built from — what it's drawn ON and what
    /// SHAPE it exports as. They used to be the same three-way chip row.
    @State private var background: SharePosterBackground
    @State private var format: SharePosterFormat = .poster
    /// Tiles for the selected format. Nil = still loading (or a route the
    /// snapshotter can't serve) — the card falls back to navy meanwhile.
    @State private var posterMap: SharePosterMap?
    @State private var isLoadingMap = false
    /// The trip's first photo, decoded. Nil = no photo, or still loading.
    @State private var posterPhoto: UIImage?
    @State private var isLoadingPhoto = false
    @State private var savedToPhotos = false
    /// «Разрешите доступ к Фото» (canon 510:119) — shown when saving the card
    /// is refused by the system.
    @State private var showPhotoAccessAlert = false
    @State private var linkCopied = false
    /// Summed height of the chrome + the card block. Drives a detent sized
    /// to the content: at a fixed fraction the sheet always ended with a
    /// slab of empty background under the link row.
    @State private var measuredHeight: CGFloat = 0

    /// Preview height is fixed; the width follows the chosen aspect so the
    /// chips visibly change the SHAPE of the card, not just its contents.
    private static let previewHeight: CGFloat = 290

    /// The canon (117:1959) opens on «Фото-фон». A trip with no photo opens
    /// on «Карта» instead, so the sheet never starts on a chip it has to grey
    /// out and show an empty poster behind.
    init(data: StoryShareData, shareUrl: String?) {
        self.data = data
        self.shareUrl = shareUrl
        _background = State(initialValue: data.photoSource == nil ? .map : .photo)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header(c)
                backgroundChips(c)
            }

            ScrollView {
                VStack(spacing: 14) {
                    preview(c)

                    // Under the preview, not next to the background chips:
                    // this row changes the card's SHAPE, and the shape it
                    // changes is the thing directly above it.
                    formatChips(c)

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
                // Just enough to clear the buttons. The sheet then adds the
                // home-indicator strip on top of this, and 20pt here made the
                // two together read as a slab of nothing under the actions.
                .padding(.bottom, 6)
                // Where the content actually ENDS in the sheet's own space.
                // Summing block heights over-counted by the sheet's chrome
                // and left a slab of dead background under the link row.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SharePosterSheetHeightKey.self,
                            value: geo.frame(in: .named(Self.space)).maxY
                        )
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .coordinateSpace(name: Self.space)
        .background(c.bg)
        // No `presentationCornerRadius` override: on iOS 26 a sheet is a card
        // that floats inset from the screen, and forcing the radius left its
        // bottom corners squared off against the screen edge — the reported
        // «обрезанная карточка». The system radius is correct on both.
        .presentationDetents([.height(sheetHeight)])
        .onPreferenceChange(SharePosterSheetHeightKey.self) { measuredHeight = $0 }
        // One key for both axes: the snapshot is cached per (trip, format),
        // so flipping away from «Карта» and back is free, and two separate
        // `.task(id:)` modifiers would both fire on first appear.
        .task(id: mapKey) { await loadMap() }
        // Eager, not on-demand: «Фото-фон» is the default chip whenever the
        // trip has a photo, so a lazy load would show navy for the first
        // second every single time the sheet opens.
        .task { await loadPhoto() }
        .appConfirm(
            isPresented: $showPhotoAccessAlert,
            title: AppStrings.photoAccessAlertTitle(lang.language),
            message: AppStrings.photoAccessAlertBody(lang.language),
            actions: [
                AppDialogAction(AppStrings.openSettings(lang.language)) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            ],
            cancelTitle: AppStrings.cancel(lang.language)
        )
    }

    private static let space = "shareSheetContent"

    /// Content bottom plus the home-indicator strip, clamped so a small phone
    /// gets a scrollable sheet rather than one taller than the screen. The
    /// pre-measurement default is close to the real value, so the sheet
    /// doesn't visibly resize as it opens.
    private var sheetHeight: CGFloat {
        let bottomInset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
        let screen = UIScreen.main.bounds.height
        guard measuredHeight > 0 else { return min(645, screen * 0.92) }
        return min(measuredHeight + bottomInset, screen * 0.92)
    }

    /// Identity of the snapshot the card currently wants. Background is part
    /// of it because only «Карта» needs tiles at all.
    private var mapKey: String { "\(background.rawValue)|\(format.rawValue)" }

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

    /// Canon 117:1987 — what the card is drawn on.
    private func backgroundChips(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            ForEach(SharePosterBackground.allCases) { item in
                // Greyed rather than dropped, in both cases: a chip that
                // disappears reflows the row, so the same sheet is a
                // different shape from one trip to the next and «Карта»
                // never sits where the user last found it. Dimmed reads as
                // "this style exists, this trip can't use it".
                //  • «Фото-фон» on a trip with no photo → an empty poster.
                //  • Anything at all on the sticker → it exports its alpha,
                //    so there is no ground to paint.
                let enabled = !format.isTransparent
                    && (item != .photo || data.photoSource != nil)
                chip(
                    item.title(lang.language),
                    isOn: background == item && !format.isTransparent,
                    isEnabled: enabled,
                    c: c
                ) {
                    withAnimation(.easeOut(duration: 0.22)) { background = item }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.2), value: format.isTransparent)
    }

    /// The other axis: aspect ratio + export shape. Deliberately quieter than
    /// the background row — it picks a container, not a look.
    private func formatChips(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            ForEach(SharePosterFormat.allCases) { item in
                chip(item.title(lang.language), isOn: format == item, isEnabled: true, c: c, compact: true) {
                    withAnimation(.easeOut(duration: 0.22)) { format = item }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func chip(
        _ title: String,
        isOn: Bool,
        isEnabled: Bool,
        c: AppTheme.Colors,
        compact: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: isOn ? .bold : .semibold))
                .foregroundStyle(isOn ? AppTheme.accent : c.textSecondary)
                .padding(.horizontal, compact ? 12 : 14)
                .padding(.vertical, compact ? 7 : 9)
                .background(c.card, in: Capsule())
                // `strokeBorder` — a centred stroke would be clipped by the
                // row's bounds.
                .overlay(Capsule().strokeBorder(isOn ? AppTheme.accent : .clear, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
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
            SharePosterView(
                data: data, format: format,
                background: background, map: posterMap, photo: posterPhoto
            )
            if isPreparingBackground {
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
        .animation(.easeOut(duration: 0.25), value: background)
        .animation(.easeOut(duration: 0.3), value: posterMap != nil)
        .animation(.easeOut(duration: 0.3), value: posterPhoto != nil)
    }

    /// True while the layer the user picked is still on its way. The card
    /// shows the navy fallback meanwhile, which without a spinner reads as
    /// "the chip did nothing".
    private var isPreparingBackground: Bool {
        guard !format.isTransparent else { return false }
        switch background {
        case .map: return isLoadingMap && posterMap == nil
        case .photo: return isLoadingPhoto && posterPhoto == nil
        case .minimal: return false
        }
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

    // MARK: - Background layers

    private func loadMap() async {
        // Tiles are only ever wanted by «Карта» — the photo and minimal cards
        // used to pay for a snapshot they then painted over.
        guard background == .map, format.showsMap else {
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

    private func loadPhoto() async {
        guard let source = data.photoSource else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        switch source {
        case .local(let filename):
            posterPhoto = await PhotoStorageService.loadPhotoAsync(filename: filename)
        case .remote(let thumbnail):
            // Thumbnail first so the card isn't navy for the length of a
            // presign round-trip; the 200px upload is mush at export size, so
            // the full-size original replaces it the moment it lands.
            if let thumbnail, let placeholder = await Self.download(thumbnail) {
                if Task.isCancelled { return }
                posterPhoto = placeholder
            }
            guard let original = await presignedOriginal(), !Task.isCancelled else { return }
            if let full = await Self.download(original), !Task.isCancelled {
                posterPhoto = full
            }
        }
    }

    /// Someone else's trip only reaches the feed as a thumbnail URL.
    /// `/social/trip/photos` re-presigns the 1440px original — the same call
    /// the detail screen's photo strip makes.
    private func presignedOriginal() async -> String? {
        do {
            let res: SocialTripPhotosResponse = try await APIClient.shared.post(
                APIEndpoint.socialTripPhotos,
                body: SocialTripPhotosRequest(tripId: data.tripId),
                requiresAuth: AuthService.shared.isSignedIn
            )
            guard let first = res.photos.first else { return nil }
            return first.originalUrl ?? first.thumbnailUrl
        } catch {
            // Non-fatal: whatever thumbnail already landed stays on the card.
            return nil
        }
    }

    private static func download(_ urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Export

    @MainActor
    private func renderImage() -> UIImage? {
        // Lay out at half size, rasterise at 2× — identical geometry, but
        // every glyph and image goes through its retina path (see
        // `SharePosterFormat.renderScale`).
        let size = format.renderPointSize
        let renderer = ImageRenderer(content:
            SharePosterView(
                data: data, format: format,
                background: background, map: posterMap, photo: posterPhoto
            )
                .frame(width: size.width, height: size.height)
                .environmentObject(lang)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = SharePosterFormat.renderScale
        // Stickers keep their alpha; cards flatten onto their own artwork.
        renderer.isOpaque = !format.isTransparent
        return renderer.uiImage
    }

    private func shareImage() {
        guard let image = renderImage() else { return }
        // A real .png FILE, not a bare UIImage: the system sheet then names
        // the item after the trip and reports «Изображение PNG» (canon), and
        // Telegram/WhatsApp send it as a photo rather than re-encoding a
        // pasteboard blob. Sticker exports keep their alpha this way too —
        // a UIImage handed to the activity controller loses it in JPEG
        // conversion on some targets.
        var items: [Any] = []
        if let png = image.pngData() {
            let name = data.title
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent(name.isEmpty ? "TripTrack" : name)
                .appendingPathExtension("png")
            if (try? png.write(to: file, options: .atomic)) != nil {
                items.append(file)
            } else {
                items.append(image)
            }
        } else {
            items.append(image)
        }
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
            guard status == .authorized || status == .limited else {
                // Silence here is indistinguishable from a broken button: the
                // user taps «Сохранить», nothing happens, and nothing says
                // why. Canon 510:119 is the alert that answers it.
                Task { @MainActor in
                    Haptics.error()
                    showPhotoAccessAlert = true
                }
                return
            }
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

/// Bottom edge of the sheet's content, in the sheet's own coordinate space.
private struct SharePosterSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

