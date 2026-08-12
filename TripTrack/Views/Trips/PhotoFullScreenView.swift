import SwiftUI

/// One page of the viewer, wherever the picture lives.
///
/// Our own photos are files in Documents; someone else's arrive as presigned
/// URLs. The viewer used to know only the first kind, which is why the photo
/// strip on another rider's trip was a row of pictures you could not open.
enum FullScreenPhotoSource: Hashable {
    case local(filename: String)
    case remote(url: String?)
}

struct PhotoFullScreenView: View {
    /// One entry per page: where the picture is, and when it was taken.
    struct Page: Identifiable, Hashable {
        let id: UUID
        let source: FullScreenPhotoSource
        let timestamp: Date
    }

    let pages: [Page]
    let initialIndex: Int
    /// Trip region for the bottom caption («14 апр, 10:40 · Тверская обл.»).
    var region: String? = nil
    var language: LanguageManager.Language = .en
    let onDismiss: () -> Void

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    /// Zoom scale of the page on screen. Anything above 1 means the scroll
    /// view owns the touches, so the viewer's own swipes stand down.
    @State private var zoomScale: CGFloat = 1

    private var isZoomed: Bool { zoomScale > 1.01 }

    /// How far through a dismissing swipe we are, 0…1.
    private var dismissProgress: CGFloat {
        min(abs(dragOffset) / 260, 1)
    }

    var body: some View {
        ZStack {
            // Fades as the picture is pulled away, so the trip underneath comes
            // back into view instead of the photo jumping off a black wall.
            Color.black
                .opacity(1 - dismissProgress * 0.55)
                .ignoresSafeArea()

            pager
                .ignoresSafeArea()
                .offset(y: dragOffset)
                // Shrinking as it goes is what makes the swipe feel like it is
                // putting the picture back where it came from.
                .scaleEffect(1 - dismissProgress * 0.12)
                .gesture(dismissDrag)

            // Chrome deliberately does NOT ignore the safe area: the close
            // button belongs under the status bar, not on top of the clock.
            chrome
                .opacity(isZoomed ? 0 : 1 - dismissProgress)
                .animation(.easeOut(duration: 0.18), value: isZoomed)
        }
        .statusBarHidden(false)
        .onAppear { currentIndex = initialIndex }
        .onChange(of: currentIndex) { _, _ in
            // A new page starts at fit scale; the zoom belonged to the old one.
            zoomScale = 1
        }
    }

    // MARK: - Pages

    private var pager: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                PhotoPage(
                    source: page.source,
                    onZoomChange: { scale in
                        guard index == currentIndex else { return }
                        zoomScale = scale
                    },
                    onSingleTap: {
                        // While zoomed a stray tap must not close the viewer —
                        // the scroll view will take it back to fit first.
                        guard !isZoomed else { return }
                        onDismiss()
                    }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// Pull down (or up) to put the photo away. Off while zoomed — there the
    /// same finger movement is panning around the picture.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isZoomed else { return }
                // Horizontal intent belongs to the pager.
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard !isZoomed else { return }
                let far = abs(value.translation.height) > 120
                let flung = abs(value.predictedEndTranslation.height) > 300
                if far || flung {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            ZStack {
                if pages.count > 1 {
                    Text("\(currentIndex + 1) / \(pages.count)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .accessibilityLabel(AppStrings.closeSheet(language))
                    .accessibilityIdentifier("photo_viewer_close")
                    Spacer(minLength: 0)
                    // No share button: a photo is shared as part of the trip,
                    // from the ↑ in the detail header. A per-photo share was a
                    // second, quieter way to publish someone else's picture.
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if pages.count > 1 {
                    PhotoPageDots(count: pages.count, current: currentIndex)
                }
                if let caption = captionLine {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                }
            }
            .padding(.bottom, 12)
            .allowsHitTesting(false)
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
        guard pages.indices.contains(currentIndex) else { return nil }
        let f = language == .ru ? Self.captionFormatters.ru : Self.captionFormatters.en
        var line = f.string(from: pages[currentIndex].timestamp)
        if let region, !region.isEmpty {
            line += " · \(region)"
        }
        return line
    }
}

/// Loads one photo — from Documents or from the network — and hands it to the
/// zoomable surface. Kept separate so a page that is still loading, or that
/// failed, is a state of the page rather than a branch inside the pager.
private struct PhotoPage: View {
    let source: FullScreenPhotoSource
    let onZoomChange: (CGFloat) -> Void
    let onSingleTap: () -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(
                    image: image,
                    onZoomChange: onZoomChange,
                    onSingleTap: onSingleTap
                )
            } else if failed {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 28))
                    Text(verbatim: "—")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSingleTap)
            } else {
                Color.clear
                    .overlay { CarLoadingView(size: .compact) }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSingleTap)
            }
        }
        .task(id: source) {
            await load()
        }
    }

    private func load() async {
        switch source {
        case .local(let filename):
            let loaded = await PhotoStorageService.loadPhotoAsync(filename: filename)
            if Task.isCancelled { return }
            image = loaded
            failed = loaded == nil
        case .remote(let urlString):
            guard let urlString, let url = URL(string: urlString) else {
                failed = true
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if Task.isCancelled { return }
                let decoded = UIImage(data: data)
                image = decoded
                failed = decoded == nil
            } catch {
                if Task.isCancelled { return }
                failed = true
            }
        }
    }
}
