import SwiftUI

/// Async full-resolution photo loader for fullscreen viewer.
private struct AsyncFullPhotoView: View {
    let filename: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Color.clear
                    .overlay { CarLoadingView(size: .compact) }
            }
        }
        .task(id: filename) {
            image = await PhotoStorageService.loadPhotoAsync(filename: filename)
        }
    }
}

struct PhotoFullScreenView: View {
    let photos: [TripPhoto]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var lastImageOffset: CGSize = .zero

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
                    AsyncFullPhotoView(filename: photo.filename)
                        .scaledToFit()
                        .scaleEffect(index == currentIndex ? scale : 1.0)
                        .offset(index == currentIndex ? imageOffset : .zero)
                        .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = lastScale * value
                                    }
                                    .onEnded { value in
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            if scale < 1.0 {
                                                scale = 1.0
                                                imageOffset = .zero
                                                lastImageOffset = .zero
                                            } else if scale > 4.0 {
                                                scale = 4.0
                                            }
                                        }
                                        lastScale = scale
                                    }
                            )
                            .simultaneousGesture(
                                scale > 1.0 ?
                                DragGesture()
                                    .onChanged { value in
                                        imageOffset = CGSize(
                                            width: lastImageOffset.width + value.translation.width,
                                            height: lastImageOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastImageOffset = imageOffset
                                    }
                                : nil
                            )
                            .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: scale <= 1.0 ? dragOffset.height : 0)
            .gesture(
                scale <= 1.0 ?
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
                : nil
            )

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }

            // Counter
            VStack {
                Spacer()
                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.3), in: Capsule())
                    .padding(.bottom, 20)
            }
        }
        .onAppear { currentIndex = initialIndex }
        .onChange(of: currentIndex) { _ in
            // Reset zoom when switching photos
            scale = 1.0
            lastScale = 1.0
            imageOffset = .zero
            lastImageOffset = .zero
        }
    }
}
