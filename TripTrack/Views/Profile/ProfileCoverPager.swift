import SwiftUI
import PhotosUI
import OSLog

struct ProfileCoverPager: View {
    var remotePhotos: [ProfilePhotoDTO]? = nil
    var isOwn = false
    var onSettings: (() -> Void)? = nil
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var store = ProfilePhotoStore.shared
    @State private var picking: [PhotosPickerItem] = []
    @State private var saving = false
    @State private var page = 0
    @State private var showsPicker = false
    @State private var addsAfterViewer = false
    @State private var selected: Selection?
    @State private var toastItem: ToastItem?
    /// Carry the frozen pages in the presentation item itself. Publishing
    /// pages and selection as separate State values can present the old empty
    /// array on the first tap, before SwiftUI has read the new pages.
    private struct Selection: Identifiable {
        let id = UUID()
        let index: Int
        let pages: [PhotoFullScreenView.Page]
    }
    private static let log = Logger(subsystem: "com.triptrack", category: "profile.photos.picker")

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
        Group {
            if !pages.isEmpty {
                cover
            } else if isOwn {
                Button { showsPicker = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                        Text(AppStrings.profileAddCover(lang.language))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.interScaled(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(AppTheme.accent).padding(.horizontal, 14)
                    .frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle()).surfaceCard()
                .padding(.horizontal, 16).padding(.top, 12)
                .accessibilityIdentifier("profile_photos_add")
            }
        }
        .photosPicker(isPresented: $showsPicker, selection: $picking,
                      maxSelectionCount: max(1, 9 - store.photos.count), matching: .images)
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
        .onChange(of: pages.map(\.id)) { _, _ in page = 0 }
        .fullScreenCover(item: $selected, onDismiss: {
            if addsAfterViewer { addsAfterViewer = false; showsPicker = true }
        }) { item in
            PhotoFullScreenView(
                pages: item.pages, initialIndex: item.index, language: lang.language,
                onDelete: isOwn ? { store.delete($0) } : nil,
                onSetMain: isOwn ? { store.makeFirst($0) } : nil,
                setMainTitle: AppStrings.profileMakeCover(lang.language),
                onAdd: isOwn && store.photos.count < 9 ? {
                    addsAfterViewer = true
                    selected = nil
                } : nil,
                isMain: isOwn ? { $0 == store.photos.first?.id } : nil,
                onDismiss: { selected = nil })
        }
    }

    private var cover: some View {
        TabView(selection: $page) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                Button {
                    Haptics.tap()
                    selected = Selection(index: index, pages: pages)
                } label: {
                    Color.clear.overlay { thumbnail(item) }.clipped().contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel(AppStrings.photos(lang.language))
                .accessibilityIdentifier("profile_photo_\(index)")
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 232)
        .overlay(alignment: .topLeading) {
            Text("\(min(page + 1, pages.count)) / \(pages.count)")
                .font(.inter(12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color(white: 0.08), in: Capsule())
                .padding(.leading, 16)
                .padding(.top, (WindowLayoutMetrics.shared.safeAreaInsets?.top ?? 59) + (isOwn ? 8 : 54))
                .accessibilityIdentifier("profile_cover_counter")
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if let onSettings {
                Button { Haptics.tap(); onSettings() } label: {
                    Image(systemName: "gearshape").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(white: 0.12)).frame(width: 40, height: 40)
                        .background(.white, in: Circle()).contentShape(Circle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel(AppStrings.settingsTitle(lang.language))
                .accessibilityIdentifier("profile_gear")
                .padding(.trailing, 16).padding(.top, (WindowLayoutMetrics.shared.safeAreaInsets?.top ?? 59) + 4)
            }
        }
    }

    @ViewBuilder private func thumbnail(_ page: PhotoFullScreenView.Page) -> some View {
        if case .profile(let filename) = page.source {
            ProfilePhotoThumbnail(filename: filename, maxSize: 1200)
        } else if case .remote(let value) = page.source, let value, let url = URL(string: value) {
            VehiclePhotoImage(source: .remote(url: url), maxSize: 1200)
        }
    }

    private func save(_ items: [PhotosPickerItem]) async {
        saving = true
        defer { saving = false; picking = [] }
        let session = store.session
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                try await store.add(data, session: session)
            } catch is CancellationError {
                break
            } catch ProfilePhotoStore.StoreError.limitReached {
                toastItem = ToastItem(type: .info, message: AppStrings.profilePhotosLimit(lang.language))
                break
            } catch {
                Self.log.error("profile photo import failed: \(error.localizedDescription)")
            }
        }
    }
}
