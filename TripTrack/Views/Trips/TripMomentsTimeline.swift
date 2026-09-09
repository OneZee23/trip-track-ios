import SwiftUI

/// Лента «Моменты»: старт, отметки и снимки по порядку, финиш.
///
/// Так поездку рассказывают вслух: «выехали в девять, через час девятнадцать
/// были у поста, там сфотографировались, в половине двенадцатого — море».
/// Вертикальная линия слева — сама дорога; узлы на ней — то, что на дороге
/// случилось. Между узлами — отрезок: сколько заняла дорога от одного до
/// другого. Число «от старта» стоит у каждого узла — с него фича началась.
struct TripMomentsTimeline: View {
    let moments: [TripMoment]
    let startDate: Date
    let endDate: Date?
    let totalElapsed: TimeInterval
    let totalMetres: Double
    let language: LanguageManager.Language
    /// Строка, к которой экран только что прокрутил с карты, — подсвечена.
    var highlightedId: UUID?
    /// Нажатие на отметку. Владелец решает, что показать: переименование,
    /// снимки, удаление. Пусто — чужая поездка, строки не нажимаются.
    var onSelectCheckpoint: ((TripCheckpoint) -> Void)?
    /// «Назвать место» у стопки снимков без отметки: снимок становится
    /// обложкой новой отметки. Пусто — кнопки нет.
    var onNamePlace: ((TripPhoto) -> Void)?
    var onOpenPhoto: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var scheme

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            nodeRow(time: startDate, c: c, node: { startNode(c) }) {
                titleLine(AppStrings.momentStart(language), c: c)
            }
            ForEach(Array(moments.enumerated()), id: \.element.id) { pair in
                connector(before: pair.offset, c: c)
                momentRow(pair.element, c: c)
                    .background(highlightedId == pair.element.id ? AppTheme.accent.opacity(0.12) : .clear)
                    .animation(.easeInOut(duration: 0.25), value: highlightedId)
                    // Якорь для прокрутки с карты — по id отметки.
                    .id(pair.element.id)
            }
            connector(before: moments.count, c: c)
            nodeRow(time: endDate, c: c, node: { finishNode(c) }) {
                titleLine(AppStrings.momentFinish(language), c: c)
                measure(label: AppStrings.checkpointFromStart(language),
                        value: reading(time: totalElapsed, metres: totalMetres), c: c)
            }
        }
        .padding(.vertical, 6)
        // Дорога — одна линия от центра первого узла до центра последнего,
        // фоном под всеми. Узлы сообщают свои центры сами: у финиша две
        // строки, у отметки со снимками три, и никакой фиксированный отступ
        // не угадал бы, где линия должна кончиться.
        .backgroundPreferenceValue(MomentNodeAnchors.self) { anchors in
            GeometryReader { geo in
                let points = anchors.map { geo[$0] }
                if let x = points.first?.x,
                   let top = points.map(\.y).min(),
                   let bottom = points.map(\.y).max(),
                   bottom > top {
                    Rectangle()
                        .fill(c.border)
                        .frame(width: 2, height: bottom - top)
                        .position(x: x, y: (top + bottom) / 2)
                }
            }
        }
        .surfaceCard()
    }

    private static let nodeSize: CGFloat = 28
    private static let horizontalPadding: CGFloat = 14
    /// Колонка времени слева от рельса: «08:42» в 13 пт умещается в 40.
    private static let timeWidth: CGFloat = 40
    /// Равен шагу стека в строке — так рельс и коннектор считают одно и то же.
    private static let timeSpacing: CGFloat = 12
    private static let rowPadding: CGFloat = 8

    // MARK: - Узлы

    private func startNode(_ c: AppTheme.Colors) -> some View {
        Circle()
            .fill(c.card)
            .overlay(Circle().strokeBorder(AppTheme.accent, lineWidth: 3))
            .frame(width: 16, height: 16)
    }

    /// Глиф — цветом карточки на цвете текста: в тёмной теме круг белый,
    /// и белый флаг на нём пропадал.
    private func finishNode(_ c: AppTheme.Colors) -> some View {
        Image(systemName: "flag.checkered")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(c.card)
            .frame(width: Self.nodeSize, height: Self.nodeSize)
            .background(c.text, in: Circle())
    }

    private func cameraNode(_ c: AppTheme.Colors) -> some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(c.textSecondary)
            .frame(width: Self.nodeSize, height: Self.nodeSize)
            .background(c.card, in: Circle())
            .overlay(Circle().strokeBorder(c.border, lineWidth: 1.5))
    }

    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: Self.nodeSize, height: Self.nodeSize)
            .background(AppTheme.accent, in: Circle())
    }

    // MARK: - Строки

    @ViewBuilder
    private func momentRow(_ moment: TripMoment, c: AppTheme.Colors) -> some View {
        switch moment {
        case .checkpoint(let checkpoint, let number, let photos):
            checkpointRow(checkpoint, number: number, photos: photos, c: c)
        case .photos(let fix, let photos):
            nodeRow(time: fix.timestamp, c: c, node: { cameraNode(c) }) {
                titleLine("\(photos.count) \(AppStrings.nounPhotos(language, photos.count))", c: c)
                HStack(alignment: .center, spacing: 8) {
                    measure(label: AppStrings.checkpointFromStart(language),
                            value: reading(time: fix.elapsedFromStart, metres: fix.distanceFromStart), c: c)
                    Spacer(minLength: 6)
                    Button {
                        onOpenPhoto?(photos[0].id)
                    } label: {
                        photoStack(photos, c: c)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel(AppStrings.nounPhotos(language, photos.count))
                }
                if onNamePlace != nil {
                    Button {
                        Haptics.action()
                        onNamePlace?(photos[0])
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11, weight: .bold))
                            Text(AppStrings.momentNamePlace(language))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(PressableCardStyle())
                    .padding(.top, 4)
                }
            }
        }
    }

    /// Отметка — кнопка целиком, как строка в любом списке: шеврон говорит,
    /// что она открывается.
    private func checkpointRow(_ checkpoint: TripCheckpoint, number: Int,
                               photos: [TripPhoto], c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            onSelectCheckpoint?(checkpoint)
        } label: {
            nodeRow(time: checkpoint.timestamp, c: c, node: { numberBadge(number) }) {
                titleLine(checkpoint.name?.isEmpty == false
                          ? checkpoint.name!
                          : AppStrings.checkpointDefaultName(language, number: number),
                          chevron: onSelectCheckpoint != nil, c: c)
                HStack(alignment: .center, spacing: 8) {
                    measure(label: AppStrings.checkpointFromStart(language),
                            value: reading(time: checkpoint.elapsedFromStart,
                                           metres: checkpoint.distanceFromStart), c: c)
                    Spacer(minLength: 6)
                    if !photos.isEmpty { photoStack(photos, c: c) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .disabled(onSelectCheckpoint == nil)
    }

    /// Время слева, узел на рельсе, содержимое справа — как в расписании:
    /// глаз ведёт по колонке времени сверху вниз, не ища его в конце строки.
    /// Первая строка содержимого держится на высоте узла, чтобы имя стояло
    /// ровно против кружка.
    private func nodeRow<Node: View, Content: View>(
        time: Date?,
        c: AppTheme.Colors,
        @ViewBuilder node: () -> Node,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time.map { Self.timeFormatter.string(from: $0) } ?? "")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(c.textSecondary)
                .frame(width: Self.timeWidth, height: Self.nodeSize, alignment: .trailing)
            node()
                .frame(width: Self.nodeSize, height: Self.nodeSize)
                .anchorPreference(key: MomentNodeAnchors.self, value: .center) { [$0] }
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.rowPadding)
    }

    private func titleLine(_ title: String, chevron: Bool = false,
                           c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            // Имя ограничено сорока знаками в редакторе; две строки вмещают
            // его целиком на любом телефоне, дальше — многоточие.
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            // Шеврон только там, где строка открывается.
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .frame(minHeight: Self.nodeSize)
    }

    /// Отрезок между соседними узлами — короткой строкой на самой линии:
    /// «+1 ч 10 мин · 72 км». Плюс говорит «прибавилось с прошлого узла».
    /// От старта до первой отметки не пишем: это же число стоит у неё
    /// в «От старта», а два одинаковых числа рядом просят их сравнивать.
    @ViewBuilder
    private func connector(before index: Int, c: AppTheme.Colors) -> some View {
        let prev: (TimeInterval, Double) = index == 0
            ? (0, 0)
            : (moments[index - 1].elapsedFromStart, moments[index - 1].distanceFromStart)
        let next: (TimeInterval, Double) = index < moments.count
            ? (moments[index].elapsedFromStart, moments[index].distanceFromStart)
            : (totalElapsed, totalMetres)
        let dt = next.0 - prev.0
        let dm = next.1 - prev.1
        if index > 0, dt > 0 || dm > 0 {
            HStack(spacing: 12) {
                Color.clear.frame(width: Self.timeWidth + Self.timeSpacing + Self.nodeSize, height: 1)
                Text("+" + reading(time: max(0, dt), metres: max(0, dm)))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(c.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Детали

    /// Две миниатюры внахлёст и «+N» чипом на уголке — как у маркера на карте.
    private func photoStack(_ linked: [TripPhoto], c: AppTheme.Colors) -> some View {
        let shown = Array(linked.prefix(2))
        return HStack(spacing: -9) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { pair in
                AsyncThumbnailView(filename: pair.element.filename, maxSize: 56)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(c.card, lineWidth: 2))
                    .zIndex(Double(shown.count - pair.offset))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if linked.count > 2 {
                Text("+\(linked.count - 2)")
                    .font(.system(size: 9, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(c.card)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(c.text, in: Capsule())
                    .overlay(Capsule().strokeBorder(c.card, lineWidth: 1.5))
                    .offset(x: 4, y: 4)
            }
        }
        .fixedSize()
    }

    private func measure(label: String, value: String, c: AppTheme.Colors) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(c.textSecondary)
        }
        .lineLimit(1)
    }

    private func reading(time: TimeInterval, metres: Double) -> String {
        CheckpointReading.text(elapsed: time, metres: metres, lang: language)
    }
}

/// Центры узлов ленты — по ним рисуется рельс.
private struct MomentNodeAnchors: PreferenceKey {
    static let defaultValue: [Anchor<CGPoint>] = []
    static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
        value.append(contentsOf: nextValue())
    }
}
