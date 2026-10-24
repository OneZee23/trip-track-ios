import SwiftUI

/// The same viewer for trip photos and the car photos referenced by a log entry.
struct GaragePhotoGrid: View {
    let title: String
    let pages: [PhotoFullScreenView.Page]
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Selection?
    private struct Selection: Identifiable { let id: Int }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            CustomNavBar(title: title)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        Button {
                            selected = Selection(id: index)
                        } label: {
                            // The cell sets the size and the photo fills it. A
                            // fill image framed only by height keeps its own
                            // width and spills over its neighbours.
                            Color.clear.frame(maxWidth: .infinity).frame(height: 112)
                                .overlay { GaragePhotoThumbnail(page: page) }
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                        }.buttonStyle(PressableCardStyle()).accessibilityLabel(AppStrings.photos(lang.language))
                            .accessibilityIdentifier("garage_photo_\(index)")
                    }
                }.padding(14)
            }
        }
        .background(c.bg)
        .environment(\.previewPop, nil)
        .fullScreenCover(item: $selected) { item in
            PhotoFullScreenView(
                pages: pages, initialIndex: item.id, language: lang.language,
                onDismiss: { selected = nil })
        }
    }
}

struct GaragePhotoThumbnail: View {
    let page: PhotoFullScreenView.Page
    var body: some View {
        switch page.source {
        case .local(let filename): AsyncThumbnailView(filename: filename)
        case .profile(let filename): ProfilePhotoThumbnail(filename: filename)
        case .vehicle(let filename):
            VehiclePhotoImage(source: .local(filename: filename), maxSize: 250)
        case .remote(let url): RemoteThumbnailView(urlString: url)
        }
    }
}

struct GarageTripPhotos: View {
    let pages: [PhotoFullScreenView.Page]
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var showGrid = false

    var body: some View {
        if !pages.isEmpty {
            let c = AppTheme.colors(for: scheme)
            Button {
                Haptics.tap()
                showGrid = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(AppStrings.garageTripPhotos(lang.language)).font(.inter(16, weight: .bold))
                            .foregroundStyle(c.text)
                        Spacer()
                        Text(String(pages.count)).font(.inter(12)).foregroundStyle(c.textSecondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(
                            c.textTertiary)
                    }
                    HStack(spacing: 7) {
                        ForEach(pages.prefix(4)) { page in
                            Color.clear.frame(maxWidth: .infinity).frame(height: 64)
                                .overlay { GaragePhotoThumbnail(page: page) }
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }.padding(16).surfaceCard(cornerRadius: 20)
            }.buttonStyle(PressableCardStyle()).accessibilityIdentifier("garage_trip_photos")
                .fullScreenCover(isPresented: $showGrid) {
                    GaragePhotoGrid(title: AppStrings.garageTripPhotos(lang.language), pages: pages)
                }
        }
    }
}
