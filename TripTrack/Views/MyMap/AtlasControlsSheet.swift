import SwiftUI

/// These choices change the existing map immediately; no second map is created.
struct AtlasAppearanceSheet: View {
    @Binding var appearance: AtlasMapAppearance
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            AtlasControlsHeader(title: AppStrings.atlasMapStyle(lang.language))
            ScrollView {
                VStack(spacing: 16) {
                    // Три в ряд — как рисует макет A7. Сетка, а не `HStack`:
                    // у трёх плиток подписи разной длины, и колонки обязаны
                    // быть равными, а не по содержимому.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                             count: 3),
                              spacing: 8) {
                        styleCard(.fog, title: AppStrings.atlasFogStyle(lang.language))
                        styleCard(.night, title: AppStrings.atlasNightStyle(lang.language))
                        styleCard(.cells, title: AppStrings.atlasCellsStyle(lang.language))
                    }
                    layerToggles
                }
                .padding(16)
            }
        }
        .background(AtlasTheme.background)
        .presentationBackground(AtlasTheme.background)
        .presentationCornerRadius(AtlasTheme.sheetRadius)
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("atlas_appearance_sheet")
    }

    private var layerToggles: some View {
        VStack(spacing: 0) {
            // Подписи городов убраны вовсе (владелец, 26 сен): наш «Геленджик»
            // ложился поверх «Gelendzhik», который рисует сама Apple. Имена
            // городов знает карта, и знает лучше — на тринадцати языках и без
            // нашего слоя. Вместе с подписями ушёл и тумблер: выключателя у
            // того, чего нет, быть не может.
            Toggle(AppStrings.atlasShowPhotos(lang.language), isOn: $appearance.showsPhotos)
                .frame(minHeight: 56)
                .accessibilityIdentifier("atlas_photos_toggle")
        }
        .font(.inter(16, weight: .semibold))
        .foregroundStyle(AtlasTheme.ink)
        .tint(AtlasTheme.accent)
        .padding(.horizontal, 16)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
    }

    private func styleCard(_ style: AtlasMapAppearance.Style, title: String) -> some View {
        let selected = appearance.style == style
        return Button {
            Haptics.tap()
            appearance.style = style
        } label: {
            VStack(spacing: 8) {
                AtlasStylePreview(style: style)
                    .frame(height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 5) {
                    Text(title).font(.inter(14, weight: .bold))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(selected ? AtlasTheme.accent : AtlasTheme.ink)
                .frame(minHeight: 24)
            }
            .padding(5)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity)
            .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(selected ? AtlasTheme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("atlas_style_\(style.rawValue)")
    }
}

/// S8's explanations cover the metrics the app really computes. Stamps and
/// geometric city-boundary promises are intentionally not part of this sheet.
struct AtlasExplanationSheet: View {
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            AtlasControlsHeader(title: AppStrings.atlasHowWeCount(lang.language))
            ScrollView {
                VStack(spacing: 12) {
                    explanation(
                        symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        title: AppStrings.atlasNewRoads(lang.language),
                        body: AppStrings.atlasRoadsExplanation(lang.language))
                    explanation(
                        symbol: "arrow.triangle.2.circlepath",
                        title: AppStrings.atlasTotalTravelled(lang.language),
                        body: AppStrings.atlasTripsExplanation(lang.language))
                    explanation(
                        symbol: "calendar",
                        title: AppStrings.atlasPeriod(lang.language),
                        body: AppStrings.atlasPeriodRoadsExplanation(lang.language))
                }
                .padding(16)
            }
        }
        .background(AtlasTheme.background)
        .presentationBackground(AtlasTheme.background)
        .presentationCornerRadius(AtlasTheme.sheetRadius)
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("atlas_explanation_sheet")
    }

    private func explanation(symbol: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AtlasTheme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppType.statCaption)
                    .tracking(AppType.statCaptionTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(AtlasTheme.ink)
            }
            Text(body)
                .font(.inter(15))
                .lineSpacing(3)
                .foregroundStyle(AtlasTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

private struct AtlasControlsHeader: View {
    let title: String
    var onBack: (() -> Void)? = nil
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Capsule().fill(AtlasTheme.handle).frame(width: 36, height: 5)
                .accessibilityHidden(true)
            HStack(spacing: 12) {
                if let onBack {
                    Button { Haptics.tap(); onBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AtlasTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(AtlasTheme.card, in: Circle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel(AppStrings.back(lang.language))
                    .accessibilityIdentifier("atlas_period_back")
                }
                Text(title)
                    .font(AppType.sheetTitle)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(AtlasTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AtlasTheme.secondary)
                        .frame(width: 36, height: 36)
                        .background(AtlasTheme.searchBackground, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel(AppStrings.close(lang.language))
                .accessibilityIdentifier("atlas_controls_close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// A small, code-native illustration of each real map appearance.
private struct AtlasStylePreview: View {
    let style: AtlasMapAppearance.Style

    var body: some View {
        Canvas { context, size in
            let night = style == .night
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(night
                ? Color(red: 0.11, green: 0.14, blue: 0.19)
                : Color(red: 0.90, green: 0.90, blue: 0.88)))
            let route = routePath(size)
            let openedColour = Color(red: 0.85, green: 0.82, blue: 0.69)
            if style == .cells {
                // У «Клеток» открытое — КЛЕТКИ, и превью обязано показывать
                // именно их: тайл, подписанный «Клетки», но нарисованный
                // мягким коридором, обещал бы не то, что человек увидит.
                context.fill(openedCells(route, size: size), with: .color(openedColour))
            } else {
                context.stroke(route, with: .color(night
                    ? Color(red: 0.20, green: 0.25, blue: 0.30)
                    : openedColour),
                    style: StrokeStyle(lineWidth: 28, lineCap: .round, lineJoin: .round))
            }
            var streets = Path()
            for x in stride(from: CGFloat(-20), through: size.width + 40, by: 26) {
                streets.move(to: CGPoint(x: x, y: 0))
                streets.addLine(to: CGPoint(x: x + 40, y: size.height))
            }
            context.stroke(streets, with: .color(.white.opacity(night ? 0.07 : 0.55)), lineWidth: 1)
            context.stroke(route, with: .color(.white.opacity(night ? 0.25 : 0.95)),
                           style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            context.stroke(route, with: .color(night
                ? Color(red: 1, green: 0.58, blue: 0.34)
                : Color(red: 0.78, green: 0.28, blue: 0.18)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for point in [CGPoint(x: size.width * 0.16, y: size.height * 0.75),
                          CGPoint(x: size.width * 0.78, y: size.height * 0.23)] {
                let dot = Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(.white))
                context.stroke(dot, with: .color(.black.opacity(0.65)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    /// Клетки, которых коридор касается. Сторона взята «на глаз кадра», а не
    /// из `FogCellGrid`: превью это рисунок в восемьдесят точек, и настоящая
    /// сторона в точках карты здесь ничего не значит — значит только то, что
    /// открытое выглядит квадратами такого же порядка, как на карте.
    private func openedCells(_ route: Path, size: CGSize) -> Path {
        let side: CGFloat = 13
        let halo: CGFloat = 14
        let wide = route.strokedPath(StrokeStyle(lineWidth: halo * 2,
                                                 lineCap: .round, lineJoin: .round))
        var cells = Path()
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let cell = CGRect(x: x, y: y, width: side, height: side)
                if wide.contains(CGPoint(x: cell.midX, y: cell.midY)) {
                    cells.addRect(cell)
                }
                x += side
            }
            y += side
        }
        return cells
    }

    private func routePath(_ size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.75))
            path.addCurve(to: CGPoint(x: size.width * 0.78, y: size.height * 0.23),
                          control1: CGPoint(x: size.width * 0.59, y: size.height * 0.95),
                          control2: CGPoint(x: size.width * 0.42, y: size.height * 0.10))
        }
    }
}
