import SwiftUI

/// Fullscreen viewer for another user's public photos. Unlike the owner's
/// `PhotoFullScreenView` which loads from the local Documents directory by
/// filename, this one loads presigned R2 URLs. Gestures are intentionally
/// minimal (swipe between pages, tap to dismiss) — pinch/zoom can come
/// later once the basic flow feels right.
struct SocialPhotoFullScreenView: View {
    let photos: [SocialTripPhoto]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { onDismiss() }

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    photoPage(photo)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        Haptics.tap()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                if let caption = photos[safe: currentIndex]?.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear { currentIndex = initialIndex }
    }

    @ViewBuilder
    private func photoPage(_ photo: SocialTripPhoto) -> some View {
        // Prefer the original when available — the user taps through to
        // fullscreen specifically to see detail. Fall back to the thumbnail
        // if the original is still uploading / presign failed.
        let urlString = photo.originalUrl ?? photo.thumbnailUrl
        if let s = urlString, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))
                case .empty:
                    CarLoadingView(size: .compact)
                @unknown default:
                    Color.clear
                }
            }
        } else {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
