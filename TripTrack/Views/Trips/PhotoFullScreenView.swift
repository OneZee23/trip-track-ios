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
    /// Non-nil only where deleting is the viewer's to offer — the owner's
    /// own trip. The viewer closes itself before calling it: the page it is
    /// showing is about to stop existing.
    var onDelete: ((UUID) -> Void)? = nil
    let onDismiss: () -> Void

    /// Which page the pager has actually LANDED on. Driving the pager by
    /// index through a `TabView` is what this replaces — see `pager`.
    @State private var currentPageID: UUID?
    @State private var currentIndex: Int
    @State private var confirmingDelete = false
    @State private var dragOffset: CGFloat = 0
    /// Zoom scale of the page on screen. Anything above 1 means the scroll
    /// view owns the touches, so the viewer's own swipes stand down.
    @State private var zoomScale: CGFloat = 1
    /// Tap puts the chrome away so the picture is alone on screen, tap
    /// again brings it back — the gesture every photo app has. It used to
    /// CLOSE the viewer, which meant there was no way to look at a photo
    /// without a button sitting on it.
    @State private var chromeHidden = false

    /// `initialIndex` is a stored property, so seeding the state it feeds
    /// needs a real init — and seeding it is the point: the pager must be
    /// BORN on the right page. Setting it afterwards from `.onAppear` is
    /// what used to hand `UIPageViewController` a re-seat while the cover
    /// was still animating in.
    init(
        pages: [Page],
        initialIndex: Int,
        region: String? = nil,
        language: LanguageManager.Language = .en,
        onDelete: ((UUID) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.pages = pages
        self.initialIndex = initialIndex
        self.region = region
        self.language = language
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        let start = pages.indices.contains(initialIndex) ? initialIndex : 0
        _currentIndex = State(initialValue: start)
        _currentPageID = State(initialValue: pages.isEmpty ? nil : pages[start].id)
    }

    private var isZoomed: Bool { zoomScale > 1.01 }

    /// Zooming hides the chrome on its own — while you are inside the
    /// picture, nothing else belongs on screen.
    private var chromeVisible: Bool { !chromeHidden && !isZoomed }

    /// How far through a dismissing swipe we are, 0…1. Downward only —
    /// dragging up is resisted, not counted (see `applyDismissDrag`).
    private var dismissProgress: CGFloat {
        min(max(dragOffset, 0) / 260, 1)
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

            chrome
                .opacity(chromeVisible ? 1 - dismissProgress : 0)
                .allowsHitTesting(chromeVisible)
                .animation(.easeOut(duration: 0.18), value: isZoomed)
                .animation(.easeOut(duration: 0.18), value: chromeHidden)
        }
        .statusBarHidden(chromeHidden)
        .confirmationDialog(
            AppStrings.deletePhoto(language),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete(language), role: .destructive) {
                guard pages.indices.contains(currentIndex) else { return }
                onDelete?(pages[currentIndex].id)
            }
            Button(AppStrings.cancel(language), role: .cancel) {}
        }
        .onChange(of: currentPageID) { _, id in
            // `.scrollPosition` can publish nil while a target is off screen;
            // only a real landing counts as a page turn.
            guard let id, let index = pages.firstIndex(where: { $0.id == id }) else { return }
            currentIndex = index
            // A new page starts at rest scale; the zoom belonged to the old one.
            zoomScale = 1
        }
    }

    // MARK: - Pages

    /// A flat, paging `ScrollView` — deliberately NOT `TabView(.page)`.
    ///
    /// `TabView(.page)` is a `UIPageViewController`, which keeps a ±1 window
    /// of child controllers inside a private queuing scroll view and reseats
    /// its bookkeeping whenever a child is prepended, appended or re-seated
    /// programmatically. Swiping back to the previous photo could leave that
    /// bookkeeping stranded: the transition stopped at half a page and
    /// stayed there, two photos on screen at once, settling on neither.
    /// Two attempts to fix it from the outside — killing the open-time
    /// animation, then tightening the dismiss gesture's arming rule — both
    /// missed, because both were guesses about HOW the queue was being
    /// corrupted.
    ///
    /// A paging scroll view has no queue to corrupt. It is one scroll view
    /// whose content is N pages wide, and its resting offset is computed in
    /// `scrollViewWillEndDragging` — so an offset that is not a whole number
    /// of pages is not a state it can come to rest in. That is a property of
    /// the construction, not another theory about the cause.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    PhotoPage(
                        source: page.source,
                        onZoomChange: { scale in
                            guard index == currentIndex else { return }
                            // Writing this on every zoom frame rebuilds the
                            // whole body at display rate, during a gesture.
                            // Nothing here reads the exact scale; only "is it
                            // magnified" matters.
                            guard abs(scale - zoomScale) > 0.05 else { return }
                            zoomScale = scale
                        },
                        onDismissDrag: { translation in
                            guard index == currentIndex else { return }
                            applyDismissDrag(translation)
                        },
                        onDismissDragEnded: { translation, predicted in
                            guard index == currentIndex else { return }
                            endDismissDrag(translation: translation, predicted: predicted)
                        },
                        onSingleTap: {
                            // Tap shows/hides the chrome; it does NOT close
                            // the viewer. Closing has two deliberate ways —
                            // the ✕ and a swipe down — and neither can be
                            // triggered by the tap you make to see the
                            // picture unobstructed.
                            guard !isZoomed else { return }
                            chromeHidden.toggle()
                        }
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentPageID)
        .scrollIndicators(.hidden)
        // The one thing the old pager could not be told: while the picture is
        // magnified, paging stands down completely and every pan belongs to
        // the zoomed image.
        .scrollDisabled(isZoomed)
    }

    /// Pull DOWN to put the photo away.
    ///
    /// Down only, deliberately. Up used to dismiss as well, which meant the
    /// picture leapt off the top of the screen — the opposite direction
    /// from the strip it came back to, so it read as a glitch rather than
    /// as putting something down. An upward drag now just tugs against a
    /// rubber band and settles back.
    ///
    /// The gesture itself lives in `ZoomableImageContainer` — as a UIKit
    /// pan capped at one finger, so it cannot mistake the first finger of a
    /// pinch for a drag and steal the zoom (which is exactly what the
    /// SwiftUI `DragGesture` that used to be here did). This is only what
    /// the viewer does with it.
    private func applyDismissDrag(_ translation: CGFloat) {
        // A sixth of the travel upward: enough to feel the gesture land,
        // not enough to look like the photo is going anywhere.
        dragOffset = translation >= 0 ? translation : translation / 6
    }

    private func endDismissDrag(translation: CGFloat, predicted: CGFloat) {
        if translation > 120 || predicted > 300 {
            onDismiss()
        } else {
            // Critically damped: a bouncy spring here reads as the picture
            // wobbling back into place, which is the "подпрыгивание" this
            // replaces.
            withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                dragOffset = 0
            }
        }
    }

    // MARK: - Chrome

    /// Close top-RIGHT, position and caption at the BOTTOM.
    ///
    /// Was: close top-left, a small «3 / 3» pill centred on the top edge,
    /// dots at the bottom. Two problems the layout couldn't hide — the
    /// counter landed exactly where a photographed phone screen keeps its
    /// own status bar, so two clocks and two batteries stacked on top of
    /// each other; and a bare button dropped onto a full-bleed picture
    /// reads as pasted on rather than placed.
    ///
    /// Both fixed the way photo viewers normally do it: the picture keeps
    /// the whole screen, and the chrome rides on soft gradient scrims that
    /// guarantee contrast over any photo without cropping or insetting it.
    /// The counter moves down next to the caption — where the eye already
    /// goes for "where am I in this set" — and gets a readable size instead
    /// of the 13pt it had.
    private var chrome: some View {
        VStack(spacing: 0) {
            topRow
                .padding(.horizontal, 16)
                // The chrome is laid out INSIDE the safe area already —
                // adding the window's top inset here pushed the buttons a
                // second status bar down the screen, level with the middle
                // of the picture.
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background { band.ignoresSafeArea(edges: .top) }

            Spacer(minLength: 0)

            bottomBlock
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background { band.ignoresSafeArea(edges: .bottom) }
                .allowsHitTesting(false)
        }
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if onDelete != nil {
                circleButton("trash", label: AppStrings.delete(language), id: "photo_viewer_delete") {
                    confirmingDelete = true
                }
            }
            // No share button: a photo is shared as part of the trip, from
            // the ↑ in the detail header. A per-photo share was a second,
            // quieter way to publish someone else's picture.
            circleButton(
                "xmark", label: AppStrings.closeSheet(language), id: "photo_viewer_close",
                action: onDismiss
            )
        }
    }

    private func circleButton(
        _ systemImage: String, label: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// Position first, then what the picture is. Both sit on the bottom
    /// scrim rather than floating loose over whatever the photo happens to
    /// show there.
    private var bottomBlock: some View {
        VStack(spacing: 6) {
            if pages.count > 1 {
                Text("\(currentIndex + 1) / \(pages.count)")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("photo_viewer_counter")
            }
            if let caption = captionLine {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The bands the chrome sits on.
    ///
    /// These were soft gradients, which is fine over a photograph and
    /// useless over a photographed SCREEN: white 13pt type landed on a
    /// light-grey button and disappeared. A blurred band is unambiguous —
    /// it reads as the app's own furniture rather than as part of the
    /// picture, whatever the picture happens to be. It exists only while
    /// the chrome does: tap the photo and band, buttons and caption all go,
    /// leaving the picture edge to edge.
    private var band: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
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
    var onDismissDrag: (CGFloat) -> Void = { _ in }
    var onDismissDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
    let onSingleTap: () -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(
                    image: image,
                    onZoomChange: onZoomChange,
                    onSingleTap: onSingleTap,
                    onDismissDrag: onDismissDrag,
                    onDismissDragEnded: onDismissDragEnded
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
        // The page, not just the pager, has to ignore the safe area.
        // `TabView(.page)` is a `UIPageViewController`, and it insets its
        // CHILD view controllers by the safe area regardless of what the
        // TabView itself was told — so every page was ~60pt short at the
        // top and ~34pt at the bottom, the picture was scaled to fill a
        // screen it was never given, and the overflow was clipped. The
        // black bands that left behind sat exactly where the chrome bands
        // are, which is why this only became visible once tapping the photo
        // could hide them.
        .ignoresSafeArea()
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
