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
    /// Trip region for the bottom caption («14 апр, 10:40 · Тверская обл.»).
    var region: String? = nil
    var language: LanguageManager.Language = .en
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
                    photoPage(index: index, photo: photo)
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

            // Top chrome (Figma 117:1086): dismiss circle left + «2 / 6»
            // counter centered. (Figma also shows a share circle on the
            // right — deferred, no share pipeline for a single photo yet.)
            VStack {
                ZStack {
                    Text("\(currentIndex + 1) / \(photos.count)")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                    HStack {
                        Button(action: onDismiss) {
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
            }

            // Bottom chrome: page dots + timestamp/region caption.
            VStack(spacing: 10) {
                Spacer()
                if photos.count > 1 {
                    PhotoPageDots(count: photos.count, current: currentIndex)
                }
                if let caption = captionLine {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.bottom, 24)
            .allowsHitTesting(false)
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

    /// One swipeable page: the image with pinch-zoom, pan-while-zoomed, and
    /// double-tap-to-zoom. Extracted from `body` so the type-checker doesn't
    /// choke on the combined gesture chain.
    @ViewBuilder
    private func photoPage(index: Int, photo: TripPhoto) -> some View {
        AsyncFullPhotoView(filename: photo.filename)
            .scaledToFit()
            .scaleEffect(index == currentIndex ? scale : 1.0)
            .offset(index == currentIndex ? imageOffset : .zero)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                    }
                    .onEnded { _ in
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
            .onTapGesture(count: 2) {
                if index == currentIndex { toggleZoom() }
            }
            .onTapGesture(count: 1) {
                guard index == currentIndex else { return }
                // While zoomed, a single tap resets to fit (not dismiss) — only a
                // tap at fit scale dismisses, matching standard photo viewers and
                // the backdrop tap above. (count:2 is declared first so a double
                // tap is consumed by the zoom toggle, not this.)
                if scale > 1.0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1.0
                        lastScale = 1.0
                        imageOffset = .zero
                        lastImageOffset = .zero
                    }
                } else {
                    onDismiss()
                }
            }
    }

    private static let captionFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMM, HH:mm"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMM, HH:mm"
        return (ru, en)
    }()

    /// «14 апр, 10:40 · Тверская обл.» — photo timestamp + trip region.
    private var captionLine: String? {
        guard photos.indices.contains(currentIndex) else { return nil }
        let f = language == .ru ? Self.captionFormatters.ru : Self.captionFormatters.en
        var line = f.string(from: photos[currentIndex].timestamp)
        if let region, !region.isEmpty {
            line += " · \(region)"
        }
        return line
    }

    /// Double-tap toggles between fit and 2.5× (centered). Pinch still allows
    /// finer zoom up to 4×; panning stays available while zoomed.
    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            if scale > 1.0 {
                scale = 1.0
                lastScale = 1.0
                imageOffset = .zero
                lastImageOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }
}
