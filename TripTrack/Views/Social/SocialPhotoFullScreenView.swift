import SwiftUI

/// Fullscreen viewer for another user's public photos. Unlike the owner's
/// `PhotoFullScreenView` which loads from the local Documents directory by
/// filename, this one loads presigned R2 URLs. Mirrors the owner viewer's
/// drag-to-dismiss gesture so the dismiss feel is consistent across local
/// and social trips — pinch/zoom can come later.
struct SocialPhotoFullScreenView: View {
    let photos: [SocialTripPhoto]
    let initialIndex: Int
    /// Author identity for the top-center pill (Figma 117:1589).
    var authorName: String? = nil
    var authorEmoji: String? = nil
    let onDismiss: () -> Void

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero

    private var opacity: Double {
        let progress = min(abs(dragOffset.height) / 300, 1.0)
        return 1.0 - progress * 0.5
    }

    var body: some View {
        ZStack {
            Color.black.opacity(opacity)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    photoPage(photo)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 300 {
                            onDismiss()
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )

            // Top chrome (Figma 117:1589): dismiss circle left + author pill
            // centered. (Figma also shows a «…» circle on the right —
            // deferred with the report/moderation entry point.)
            VStack {
                ZStack {
                    if let authorName, !authorName.isEmpty {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(red: 0xF4/255, green: 0xF2/255, blue: 0xEE/255))
                                .frame(width: 24, height: 24)
                                .overlay { Text(authorEmoji ?? "🚗").font(.system(size: 13)) }
                            Text(authorName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 12)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.42), in: Capsule())
                    }
                    HStack {
                        Button {
                            Haptics.tap()
                            onDismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Bottom chrome: page dots + photo caption.
                VStack(spacing: 10) {
                    if photos.count > 1 {
                        PhotoPageDots(count: photos.count, current: currentIndex)
                    }
                    if let caption = photos[safe: currentIndex]?.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
                .allowsHitTesting(false)
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
