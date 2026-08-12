import SwiftUI

/// A photo that lives on the server rather than in Documents.
///
/// Lifted out of the social trip detail when that screen was folded into
/// `TripDetailView` — the one screen now shows both our own photos (files on
/// disk) and someone else's (presigned R2 URLs), and only the thumbnail
/// differs.
///
/// Thumbnail presign first, original second: presigning either can fail
/// independently, and a failed thumbnail is no reason to show nothing when the
/// full-size URL came back fine.
struct RemoteThumbnailView: View {
    let urlString: String?
    var fallbackURLString: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        if let s = urlString ?? fallbackURLString, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder(c, icon: "photo.badge.exclamationmark")
                case .empty:
                    Rectangle()
                        .fill(c.cardAlt)
                        .overlay { CarLoadingView(size: .compact) }
                @unknown default:
                    Rectangle().fill(c.cardAlt)
                }
            }
        } else {
            placeholder(c, icon: "photo")
        }
    }

    private func placeholder(_ c: AppTheme.Colors, icon: String) -> some View {
        Rectangle()
            .fill(c.cardAlt)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(c.textTertiary)
            }
    }
}
