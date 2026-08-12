import SwiftUI
import Photos

/// «Выберите фото» (Figma 117:587) — the app's own photo grid.
///
/// The system picker was here before, and it is a perfectly good picker; what
/// it cannot do is look like this one. The canon numbers each pick in the order
/// you made it and counts them into «Готово · 3», which is the whole point:
/// photos attach to a trip in the order you chose them, and you can see that
/// order while choosing.
///
/// The cost is real and worth stating: reading the library directly needs photo
/// permission, where the system picker needs none. So this asks for read access
/// only, works in «limited» mode without complaint, and never touches anything
/// the user has not shared with it.
struct TripPhotoPicker: View {
    /// Full-size images, in the order they were picked.
    let onPick: ([UIImage]) -> Void

    @State private var assets: [PHAsset] = []
    /// Asset ids in pick order — the order is the feature.
    @State private var picked: [String] = []
    @State private var status: PHAuthorizationStatus = .notDetermined
    @State private var isLoading = true
    @State private var isFetchingFullSize = false
    @State private var isCancelled = false

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            header(c)

            switch status {
            case .authorized, .limited:
                grid(c)
            case .denied, .restricted:
                deniedState(c)
            default:
                Color.clear
            }
        }
        .background(c.bg)
        .task { await requestAndLoad() }
    }

    // MARK: - Header

    private func header(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Text(AppStrings.choosePhotosTitle(lang.language))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)

            HStack {
                Button {
                    Haptics.tap()
                    // Full-size fetches can take a moment on iCloud photos;
                    // cancelling has to mean cancelled, not "attached anyway
                    // once the download lands".
                    isCancelled = true
                    dismiss()
                } label: {
                    Text(AppStrings.cancel(lang.language))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
                .accessibilityIdentifier("photo_picker_cancel")

                Spacer()

                Button {
                    Haptics.action()
                    Task { await deliver() }
                } label: {
                    Text(picked.isEmpty
                         ? AppStrings.done(lang.language)
                         : "\(AppStrings.done(lang.language)) · \(picked.count)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(picked.isEmpty ? c.textTertiary : AppTheme.accent)
                }
                .disabled(picked.isEmpty || isFetchingFullSize)
                .accessibilityIdentifier("photo_picker_done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Grid

    private func grid(_ c: AppTheme.Colors) -> some View {
        ScrollView {
            // «Limited» is not an error state: the user chose to share a few
            // photos, and the only thing missing is a way to share more.
            if status == .limited {
                Button {
                    Haptics.tap()
                    presentLimitedLibraryPicker()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                        Text(AppStrings.managePhotoAccess(lang.language))
                            .font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    cell(asset, c: c)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .overlay {
            if isLoading {
                CarLoadingView(size: .compact)
            } else if assets.isEmpty {
                Text(AppStrings.noPhotosInLibrary(lang.language))
                    .font(.system(size: 14))
                    .foregroundStyle(c.textTertiary)
            }
        }
    }

    private func cell(_ asset: PHAsset, c: AppTheme.Colors) -> some View {
        let order = picked.firstIndex(of: asset.localIdentifier).map { $0 + 1 }
        return PhotoGridThumbnail(asset: asset)
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(AppTheme.accent, lineWidth: order == nil ? 0 : 2)
            }
            .overlay(alignment: .topTrailing) {
                selectionBadge(order: order)
                    .padding(6)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(asset) }
            .accessibilityLabel(order.map { "\($0)" } ?? AppStrings.photos(lang.language))
    }

    @ViewBuilder
    private func selectionBadge(order: Int?) -> some View {
        if let order {
            ZStack {
                Circle().fill(AppTheme.accent)
                Text("\(order)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)
        } else {
            Circle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                .background(Circle().fill(.black.opacity(0.12)))
                .frame(width: 20, height: 20)
        }
    }

    private func deniedState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(c.textTertiary)
            Text(AppStrings.photoAccessDenied(lang.language))
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Text(AppStrings.openSettings(lang.language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Selection

    /// A trip is a handful of pictures, not an album. The cap also bounds the
    /// save loop, which holds every picked image in memory until it is done.
    private static let selectionLimit = 20

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        guard picked.contains(id) || picked.count < Self.selectionLimit else {
            Haptics.error()
            return
        }
        Haptics.selection()
        withAnimation(.easeOut(duration: 0.15)) {
            if let idx = picked.firstIndex(of: id) {
                // Everything after it renumbers itself, which is why the order
                // lives in an array rather than in each cell.
                picked.remove(at: idx)
            } else {
                picked.append(id)
            }
        }
    }

    // MARK: - Library

    private func requestAndLoad() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let resolved: PHAuthorizationStatus
        if current == .notDetermined {
            resolved = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            resolved = current
        }
        status = resolved
        guard resolved == .authorized || resolved == .limited else {
            isLoading = false
            return
        }
        await loadAssets()
    }

    private func loadAssets() async {
        let fetched: [PHAsset] = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let result = PHAsset.fetchAssets(with: options)
            var out: [PHAsset] = []
            out.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in out.append(asset) }
            return out
        }.value
        assets = fetched
        isLoading = false
    }

    /// Full-size images for the picks, in pick order.
    private func deliver() async {
        guard !picked.isEmpty else { return }
        isFetchingFullSize = true
        defer { isFetchingFullSize = false }

        let byId = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        var images: [UIImage] = []
        for id in picked {
            guard !isCancelled else { return }
            guard let asset = byId[id] else { continue }
            if let image = await Self.fullSizeImage(for: asset) {
                images.append(image)
            }
        }
        guard !isCancelled else { return }
        onPick(images)
        dismiss()
    }

    /// Long edge we ask Photos for. A trip photo is shown in a 74pt strip and a
    /// phone-sized viewer, so the full 48-megapixel original buys nothing and
    /// costs ~200MB a picture while a dozen of them sit in an array waiting to
    /// be saved.
    private static let maxEdge: CGFloat = 2048

    private static func fullSizeImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            // Photos can call the handler more than once (a degraded preview
            // first); resume exactly once on the final one.
            var resumed = false
            let scale = min(
                1,
                maxEdge / CGFloat(max(asset.pixelWidth, asset.pixelHeight, 1))
            )
            let target = CGSize(
                width: CGFloat(asset.pixelWidth) * scale,
                height: CGFloat(asset.pixelHeight) * scale
            )
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    /// Photos does not tell us when the limited selection changed, so we ask
    /// again when the app comes back — otherwise «Показать больше фото…»
    /// appeared to do nothing at all.
    private func reloadAfterLimitedPicker() async {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(400))
            if UIApplication.shared.applicationState == .active { break }
        }
        await loadAssets()
    }

    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController?.topMostPresented
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
        Task { await reloadAfterLimitedPicker() }
    }
}

// MARK: - Thumbnail

/// One square of the grid, loaded through the Photos image manager and sized
/// for the cell rather than for the screen.
private struct PhotoGridThumbnail: View {
    let asset: PHAsset

    @State private var image: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(c.cardAlt)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .task(id: asset.localIdentifier) {
                let scale = UIScreen.main.scale
                let target = CGSize(
                    width: geo.size.width * scale,
                    height: geo.size.height * scale
                )
                image = await Self.thumbnail(for: asset, target: target)
            }
        }
    }

    private static func thumbnail(for asset: PHAsset, target: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                // A degraded frame is worth showing — it is what keeps the grid
                // from being grey while scrolling — but only the final one ends
                // the await.
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}

private extension UIViewController {
    /// Deepest presented controller — Photos refuses to present onto one that
    /// is already covered.
    var topMostPresented: UIViewController {
        presentedViewController?.topMostPresented ?? self
    }
}
