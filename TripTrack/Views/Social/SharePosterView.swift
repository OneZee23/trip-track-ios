import SwiftUI
import MapKit

/// The SHAPE of the export — aspect ratio, pixel size and whether the PNG
/// keeps its alpha. Nothing about what the card is drawn on: that used to be
/// conflated here, so the chip row labelled «Фото-фон / Карта / Минимал»
/// silently picked an aspect ratio and the photo-backed poster the canon
/// draws (117:1959) had no code path at all. Background now lives in
/// `SharePosterBackground`.
enum SharePosterFormat: String, CaseIterable, Identifiable {
    /// 4:5 card — the chat/post shape.
    case poster
    /// 9:16 — Instagram/Telegram stories.
    case story
    /// Transparent PNG of just the route + numbers, to drop onto someone
    /// else's photo or a story background.
    case sticker

    var id: String { rawValue }

    func title(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .poster: return AppStrings.sharePosterPoster(lang)
        case .story: return AppStrings.sharePosterStory(lang)
        case .sticker: return AppStrings.sharePosterStickerPng(lang)
        }
    }

    /// width / height.
    var aspect: CGFloat {
        switch self {
        case .poster: return 4.0 / 5.0
        case .story: return 9.0 / 16.0
        case .sticker: return 1.0
        }
    }

    /// Export pixel size. Story matches the platform's native canvas; the
    /// others are sized so text stays crisp when re-compressed by chat apps.
    var exportSize: CGSize {
        switch self {
        case .poster: return CGSize(width: 1080, height: 1350)
        case .story: return CGSize(width: 1080, height: 1920)
        case .sticker: return CGSize(width: 1080, height: 1080)
        }
    }

    /// Everything is laid out at half the export size and rasterised at 2×.
    /// Same pixel count, but text, the sprite and the map tiles all render
    /// through their retina path instead of the 1× one, which is what made
    /// the saved cards look soft.
    static let renderScale: CGFloat = 2

    /// Point size to lay the card out at before the 2× rasterisation.
    var renderPointSize: CGSize {
        CGSize(width: exportSize.width / Self.renderScale,
               height: exportSize.height / Self.renderScale)
    }

    /// Sticker exports keep their alpha; the cards are flattened.
    var isTransparent: Bool { self == .sticker }

    /// Cards can carry a background layer; the sticker is route-only so it
    /// can sit on any background of someone else's choosing.
    var showsMap: Bool { self != .sticker }
}

/// What the card is drawn ON — the canon chip row «Фото-фон / Карта /
/// Минимал» (117:1987). Ignored by the sticker, which is a transparent PNG
/// and so has no ground to paint.
enum SharePosterBackground: String, CaseIterable, Identifiable {
    /// The trip's first photo, full-bleed.
    case photo
    /// Real map tiles under the route — what every card used to be.
    case map
    /// The navy gradient: route and numbers, nothing else.
    case minimal

    var id: String { rawValue }

    /// Inline like `SharePosterFormat.title` rather than in `AppStrings`:
    /// this sheet already keeps its own chip copy local.
    func title(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .photo: return AppStrings.sharePosterPhoto(lang)
        case .map: return AppStrings.tabMap(lang)
        case .minimal: return AppStrings.sharePosterMinimal(lang)
        }
    }
}

/// Map tiles + the route projected onto them. Produced by
/// `SharePosterRenderer` so the route lines up with the roads exactly —
/// points come from the snapshotter's own projection rather than a
/// re-derived one.
struct SharePosterMap {
    let image: UIImage
    /// Route points normalised to 0…1 of the image, in draw order.
    let points: [CGPoint]
}

/// The shareable card. One view drives the in-sheet preview and the export:
/// every size is a ratio of the rendered width, so the 1080pt export is the
/// preview blown up, not a second layout.
struct SharePosterView: View {
    let data: StoryShareData
    let format: SharePosterFormat
    /// Which layer sits under the route. Defaults to the pre-background-axis
    /// behaviour so nothing renders a hole if a call site forgets it.
    var background: SharePosterBackground = .map
    /// Nil while the snapshot is still loading, or for the sticker.
    var map: SharePosterMap?
    /// The trip's first photo, already decoded. Nil while it loads, or when
    /// the trip has none.
    var photo: UIImage?

    /// Reference width the ratios below were drawn against.
    private static let canonWidth: CGFloat = 201

    /// Cools the tiles or the photo down so the route and the numbers stay
    /// the loudest things on the card.
    private static let tone = Color(red: 0x12/255, green: 0x18/255, blue: 0x28/255)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / Self.canonWidth
            ZStack(alignment: .topLeading) {
                backgroundLayer(size: geo.size)

                route(in: geo.size, s: s)

                if format != .sticker {
                    // Bottom scrim — map tiles are busy and a photo is worse,
                    // and white text on a sunlit field of roads (or on a
                    // bright sky) is unreadable without it. One scrim serves
                    // every background.
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .center, endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }

                wordmark(s: s)

                caption(s: s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    // MARK: - Layers

    /// Not `background(size:)` — that base name collides with the stored
    /// `background` property this now switches on.
    @ViewBuilder
    private func backgroundLayer(size: CGSize) -> some View {
        if format.isTransparent {
            Color.clear
        } else if background == .photo, let photo {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
                // Lighter than the map's tone: tiles are flat colour a scrim
                // can bury, a photo is the thing the user picked to show.
                .overlay(Self.tone.opacity(0.22))
        } else if background == .map, let map {
            Image(uiImage: map.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(Self.tone.opacity(0.28))
        } else {
            // Navy fallback — same constants as the trip-detail poster. It is
            // «Минимал» on purpose, and the stand-in while tiles or the photo
            // load (and for trips the snapshotter can't serve).
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0x29/255, green: 0x36/255, blue: 0x4F/255), location: 0.07),
                    .init(color: Color(red: 0x16/255, green: 0x1B/255, blue: 0x2C/255), location: 0.79)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private func route(in size: CGSize, s: CGFloat) -> some View {
        let width = (format == .sticker ? 9 : 7) * s
        // Only the map background may use the snapshot's projection — over a
        // photo or the navy those points are aligned to tiles that aren't
        // there, which drew the route hugging one corner.
        if background == .map, let map, !map.points.isEmpty {
            // Map-aligned: points are already in the snapshot's projection.
            SharePosterRoute(points: map.points.map {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height)
            }, lineWidth: width)
        } else if data.coordinates.count > 1 {
            SharePosterRoute(
                points: Self.project(data.coordinates, in: size, inset: width * 2.4),
                lineWidth: width
            )
            .padding(format == .sticker ? 12 * s : 0)
        }
    }

    private func wordmark(s: CGFloat) -> some View {
        // `poster_car`, not `PixelCar`: the sprite ships with a pixel-art
        // ground shadow, which on a dark poster read as a white pedestal
        // under the car. The wordmark is also two separate Texts — one
        // string with a space in it renders a huge gap in PressStart2P,
        // whose space glyph is a full em wide.
        HStack(spacing: 7 * s) {
            // `poster_car` is the sprite with its pixel-art ground shadow
            // flood-filled away and then upscaled 4× with nearest — so the
            // renderer's own downscale averages whole source pixels instead
            // of dropping them unevenly, which is what made the car look
            // chipped and half-smashed at export size.
            Image("poster_car")
                .resizable()
                .scaledToFit()
                .frame(height: 18 * s)
            HStack(spacing: 5 * s) {
                Text("TRIP")
                Text("TRACK")
            }
            .font(.custom("PressStart2P-Regular", fixedSize: 7 * s))
            .tracking(0.8 * s)
            .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.5), radius: 4 * s, y: 1 * s)
        .padding(.leading, 14 * s)
        .padding(.top, 14 * s)
    }

    private func caption(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text(data.title)
                .font(.system(size: 19 * s, weight: .heavy))
                .tracking(-0.4 * s)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // One line, always: at preview scale the row used to wrap and
            // drop «68.0» onto two lines as «68.» + «0».
            HStack(alignment: .firstTextBaseline, spacing: 10 * s) {
                metric(data.distanceKmText, unit: AppStrings.km(data.language), s: s)
                metric(data.durationText, unit: nil, s: s)
                metric(data.avgSpeedKmhText, unit: AppStrings.kmh(data.language), s: s)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .shadow(color: .black.opacity(0.55), radius: 6 * s, y: 1 * s)
        // A sticker lands on someone else's photo, where white-on-nothing is
        // a coin flip — give its text a plate to stand on. Cards already have
        // the scrim over the map.
        .padding(format == .sticker ? 12 * s : 0)
        .background {
            if format == .sticker {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .fill(.black.opacity(0.42))
            }
        }
        .padding(.leading, 16 * s)
        .padding(.trailing, 14 * s)
        .padding(.bottom, 20 * s)
    }

    private func metric(_ value: String, unit: String?, s: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2 * s) {
            // No `fixedSize` on either half. It was here to stop «68.0»
            // breaking across two lines, but a fixed-size Text cannot shrink,
            // so `minimumScaleFactor` above had nothing to work with and the
            // row simply overflowed the card instead: on a 142 km trip the
            // last metric's «км/ч» was pushed clean off the poster, leaving a
            // bare «142» against the edge. `lineLimit(1)` alone stops the
            // wrapping, and scaling now does what it was always meant to.
            Text(value)
                .font(.system(size: 17 * s, weight: .heavy).monospacedDigit())
                .tracking(-0.3 * s)
                .foregroundStyle(.white)
            if let unit {
                Text(unit)
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Fallback projection (sticker + no-tiles case)

    /// Equirectangular fit, aspect-preserved and centred, latitude flipped so
    /// north is up. Only used when there are no snapshot-projected points.
    static func project(
        _ coordinates: [CLLocationCoordinate2D], in size: CGSize, inset: CGFloat
    ) -> [CGPoint] {
        guard coordinates.count > 1, size.width > 0, size.height > 0 else { return [] }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return [] }
        // Longitude degrees shrink with latitude — without this a
        // north-south drive renders squashed sideways.
        let lonScale = max(0.15, cos(((minLat + maxLat) / 2) * .pi / 180))
        let spanX = max((maxLon - minLon) * lonScale, 1e-6)
        let spanY = max(maxLat - minLat, 1e-6)
        let usable = CGSize(width: max(size.width - inset * 2, 1),
                            height: max(size.height - inset * 2, 1))
        let scale = min(usable.width / spanX, usable.height / spanY)
        let drawn = CGSize(width: spanX * scale, height: spanY * scale)
        let originX = inset + (usable.width - drawn.width) / 2
        let originY = inset + (usable.height - drawn.height) / 2
        return coordinates.map { c in
            CGPoint(
                x: originX + (c.longitude - minLon) * lonScale * scale,
                y: originY + (maxLat - c.latitude) * scale
            )
        }
    }
}

/// The track itself: one stroked path coloured start → finish, with a dot at
/// each end. Vector drawing (no async work) so `ImageRenderer` always
/// captures a complete route in the export.
struct SharePosterRoute: View {
    let points: [CGPoint]
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            if points.count > 1 {
                ZStack {
                    path
                        .stroke(
                            gradient(in: geo.size),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: .black.opacity(0.45), radius: lineWidth * 0.7, y: lineWidth * 0.15)

                    dot(at: points[0], fill: Color(red: 0x5A/255, green: 0xC8/255, blue: 0x3C/255))
                    dot(at: points[points.count - 1], fill: .white)
                }
            }
        }
    }

    private var path: Path {
        var p = Path()
        p.move(to: points[0])
        // Quadratic smoothing through midpoints — raw GPS samples read as a
        // jagged scribble at poster scale.
        if points.count > 2 {
            for i in 1..<points.count - 1 {
                let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                                  y: (points[i].y + points[i + 1].y) / 2)
                p.addQuadCurve(to: mid, control: points[i])
            }
        }
        p.addLine(to: points[points.count - 1])
        return p
    }

    /// Start-to-finish gradient aligned to the actual travel direction, so
    /// green is always where the drive began.
    private func gradient(in size: CGSize) -> LinearGradient {
        // UnitPoint is fractional — raw pixel coordinates here would put both
        // ends off-canvas and flatten the ramp to a single colour.
        let from = points[0], to = points[points.count - 1]
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0x7A/255, green: 0xC8/255, blue: 0x28/255), location: 0.0),
                .init(color: Color(red: 0xE8/255, green: 0xC4/255, blue: 0x1E/255), location: 0.45),
                .init(color: Color(red: 0xF0/255, green: 0x7B/255, blue: 0x1E/255), location: 0.75),
                .init(color: Color(red: 0xE0/255, green: 0x3B/255, blue: 0x2C/255), location: 1.0),
            ],
            startPoint: UnitPoint(x: from.x / max(size.width, 1), y: from.y / max(size.height, 1)),
            endPoint: UnitPoint(x: to.x / max(size.width, 1), y: to.y / max(size.height, 1))
        )
    }

    private func dot(at p: CGPoint, fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: lineWidth * 1.5, height: lineWidth * 1.5)
            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: lineWidth * 0.16))
            .position(p)
    }
}
