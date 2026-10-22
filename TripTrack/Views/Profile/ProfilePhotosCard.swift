import SwiftUI
import PhotosUI
import OSLog

struct ProfilePhotosCard: View {
    var remotePhotos: [ProfilePhotoDTO]? = nil
    var isOwn = false
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = ProfilePhotoStore.shared
    @ObservedObject private var auth = AuthService.shared
    @State private var picking: [PhotosPickerItem] = []
    @State private var saving = false
    @State private var selected: Selection?
    @State private var viewerPages: [PhotoFullScreenView.Page] = []
    @State private var firstId: UUID?
    @State private var toastItem: ToastItem?
    private struct Selection: Identifiable { let id: Int }
    private static let log = Logger(subsystem: "com.triptrack", category: "profile.photos.picker")
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var pages: [PhotoFullScreenView.Page] {
        if isOwn {
            return store.photos.map {
                PhotoFullScreenView.Page(
                    id: $0.id,
                    source: $0.filename.map { .profile(filename: $0) }
                        ?? .remote(url: $0.originalURL ?? $0.thumbnailURL),
                    timestamp: $0.takenAt ?? Date(timeIntervalSince1970: 0))
            }
        }
        return (remotePhotos ?? []).map {
            PhotoFullScreenView.Page(id: $0.id, source: .remote(url: $0.originalUrl ?? $0.thumbnailUrl),
                                     timestamp: $0.takenAt.flatMap(ISODate.parse) ?? Date(timeIntervalSince1970: 0))
        }
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppStrings.photos(lang.language)).font(AppType.section)
                Spacer()
                if isOwn {
                    Text(AppStrings.profilePhotoCount(lang.language, n: store.photos.count, max: 9))
                        .font(.interScaled(12, relativeTo: .caption)).foregroundStyle(c.textSecondary)
                }
            }
            if isOwn && pages.isEmpty { picker(wide: true) }
            else {
                LazyVGrid(columns: Self.columns, spacing: 6) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        Button {
                            Haptics.tap()
                            viewerPages = pages
                            firstId = store.photos.first?.id
                            selected = Selection(id: index)
                        } label: {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .overlay { thumbnail(page) }
                                .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityLabel(AppStrings.photos(lang.language))
                        .accessibilityIdentifier("profile_photo_\(index)")
                    }
                    if isOwn && pages.count < 9 { picker(wide: false) }
                }
            }
            if isOwn && !auth.isSignedIn {
                Text(AppStrings.profilePhotosSignIn(lang.language))
                    .font(.interScaled(12, relativeTo: .caption)).foregroundStyle(c.textSecondary)
            }
        }
        .foregroundStyle(c.text)
        .padding(16).surfaceCard()
        .onChange(of: picking) { _, items in
            guard !items.isEmpty else { return }
            Task { await save(items) }
        }
        .onChange(of: store.limitReached) { _, reached in
            if isOwn && reached {
                toastItem = ToastItem(type: .info, message: AppStrings.profilePhotosLimit(lang.language))
                store.limitReached = false
            }
        }
        .toast(item: $toastItem)
        .fullScreenCover(item: $selected) { item in
            PhotoFullScreenView(
                pages: viewerPages, initialIndex: item.id, language: lang.language,
                onDelete: isOwn ? { store.delete($0) } : nil,
                onSetMain: isOwn ? { store.makeFirst($0); firstId = $0 } : nil,
                setMainTitle: AppStrings.profilePhotoFirst(lang.language),
                isMain: isOwn ? { $0 == firstId } : nil,
                onDismiss: { selected = nil })
        }
    }

    @ViewBuilder private func thumbnail(_ page: PhotoFullScreenView.Page) -> some View {
        if isOwn, let photo = store.photos.first(where: { $0.id == page.id }) {
            if let filename = photo.filename { ProfilePhotoThumbnail(filename: filename) }
            else if let url = URL(string: photo.thumbnailURL ?? photo.originalURL ?? "") {
                VehiclePhotoImage(source: .remote(url: url), maxSize: 140)
            }
        } else if let item = remotePhotos?.first(where: { $0.id == page.id }),
                let url = URL(string: item.thumbnailUrl ?? item.originalUrl ?? "") {
            VehiclePhotoImage(source: .remote(url: url), maxSize: 140)
        }
    }

    private func picker(wide: Bool) -> some View {
        PhotosPicker(selection: $picking, maxSelectionCount: max(1, 9 - store.photos.count),
                     matching: .images, photoLibrary: .shared()) {
            Group {
                if wide {
                    Text(AppStrings.profilePhotosEmpty(lang.language))
                        .font(.interScaled(14, relativeTo: .subheadline))
                        .multilineTextAlignment(.center).padding(20)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                        .overlay { Image(systemName: "plus").font(.system(size: 24, weight: .medium)) }
                }
            }
            .foregroundStyle(AppTheme.accent)
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableCardStyle()).disabled(saving)
        .accessibilityLabel(AppStrings.addPhotos(lang.language))
        .accessibilityIdentifier("profile_photos_add")
    }

    private func save(_ items: [PhotosPickerItem]) async {
        saving = true
        defer { saving = false; picking = [] }
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                try await store.add(data)
            } catch ProfilePhotoStore.StoreError.limitReached {
                toastItem = ToastItem(type: .info, message: AppStrings.profilePhotosLimit(lang.language))
                break
            } catch {
                Self.log.error("profile photo import failed: \(error.localizedDescription)")
            }
        }
    }
}
