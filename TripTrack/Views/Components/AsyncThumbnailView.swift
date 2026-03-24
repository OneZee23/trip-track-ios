import SwiftUI

/// Loads a photo thumbnail asynchronously with caching, avoiding main-thread blocking.
struct AsyncThumbnailView: View {
    let filename: String
    var maxSize: CGFloat = 150

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .overlay {
                        CarLoadingView(size: .compact)
                    }
            }
        }
        .task(id: filename) {
            image = await PhotoStorageService.loadThumbnail(filename: filename, maxSize: maxSize)
        }
    }
}
