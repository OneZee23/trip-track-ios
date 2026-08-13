import SwiftUI

/// Loads a photo thumbnail asynchronously with caching, avoiding main-thread blocking.
struct AsyncThumbnailView: View {
    let filename: String
    var maxSize: CGFloat = 150
    /// Told what actually came back, so a strip can react to a dead row
    /// (fall back to a server copy, offer to clean it up) instead of
    /// guessing from a tile that never finishes loading.
    var onOutcome: ((PhotoStorageService.ThumbnailOutcome) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @State private var image: UIImage?
    @State private var unavailable = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        return Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if unavailable {
                // The load finished and there was no picture. This used to
                // draw the SAME spinner tile as "still loading" — so a photo
                // whose file is gone sat there as a grey slab with a car in
                // it, indistinguishable from a slow read, forever.
                Rectangle()
                    .fill(c.cardAlt)
                    .overlay {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 20))
                            .foregroundStyle(c.textTertiary)
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .overlay {
                        CarLoadingView(size: .compact)
                    }
            }
        }
        .task(id: filename) {
            image = nil
            unavailable = false
            let outcome = await PhotoStorageService.loadThumbnailOutcome(
                filename: filename, maxSize: maxSize)
            if Task.isCancelled { return }
            image = outcome.image
            unavailable = outcome.image == nil
            onOutcome?(outcome)
        }
    }
}
