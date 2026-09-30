import SwiftUI

/// Пять страниц демонстрации — состояния 2 и 3 матрицы 0.8.4.
///
/// Именно сюда ведут ВСЕ замки и все строки набора: в список функций человек
/// попадает редко, а на замок нажимает посреди дела. Поэтому страница
/// показывает функцию на ЕГО данных — его имя, его аватар, его машина, его
/// последний маршрут, — а не картинку из стока.
///
/// Подвал с ценами тут ТОТ ЖЕ, что на витрине, и он никуда не девается: его
/// рисует `ProPaywallView`, а сюда приезжает только верх. Своего подвала у
/// страниц быть не должно — второй набор цен однажды разошёлся бы с первым.
struct ProDemoPager: View {
    /// С какой страницы открыли.
    let start: PlusFeature
    /// Данные человека — считаны один раз, до показа.
    let data: ProDemoData
    let onBack: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    @State private var current: PlusFeature?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let pages = ProDemoContent.pages(
            hasVehicle: data.vehicleTitle != nil, hasTrips: !data.route.isEmpty, lang: l)
        let shown = current ?? start

        VStack(spacing: 0) {
            header(c, l, shown)

            TabView(selection: Binding(
                get: { shown },
                set: { current = $0 }
            )) {
                ForEach(pages, id: \.feature) { page in
                    pageBody(page, c, l)
                        .tag(page.feature)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .frame(maxHeight: .infinity)
        }
        // `children: .contain` ОБЯЗАТЕЛЕН рядом с идентификатором на
        // контейнере: без него SwiftUI схлопывает всё поддерево в ОДИН
        // элемент и раздаёт ему это имя, а собственные имена детей пропадают —
        // и из VoiceOver, и из дерева UI-тестов. Поймано кадровым туром:
        // кнопка «Назад» (`pro_demo_back`) переставала находиться вовсе.
        // Та же ловушка, что у заголовка секции подсказок в 0.8.0 и у имени
        // листа дома в 0.8.2.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro_demo")
    }

    // MARK: - Шапка

    private func header(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language, _ shown: PlusFeature
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(c.cardAlt))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.back(l))
            .accessibilityIdentifier("pro_demo_back")

            Text(shown.proTitle(l))
                .font(AppType.navTitle)
                .foregroundStyle(c.text)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    // MARK: - Страница

    private func pageBody(
        _ page: ProDemoPage, _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        VStack(spacing: 14) {
            ProDemoPreviewView(preview: page.preview, data: data)
                .frame(height: 180)
                .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text(page.title)
                    .font(.inter(20, weight: .semibold))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                Text(page.text)
                    .font(AppType.body)
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityIdentifier("pro_demo_page_\(page.feature.proIcon)")
    }

}

/// Маршрут в коробке превью — рисованием, без `MKMapView`.
///
/// Карта здесь не нужна и вредна: демонстрация живёт внутри листа витрины,
/// а вторая `MKMapView` на листе — это те же «тяжёлые заходы», от которых
/// экран поездки лечили хостом в 0.6.5. Точки приходят В ЕДИНИЧНОМ
/// пространстве, поэтому вид ничего не считает и не знает про широту.
struct ProRouteArt: View {
    let points: [CGPoint]
    let color: Color
    var dashed = false
    var endpoints = false

    var body: some View {
        GeometryReader { geo in
            let box = geo.size.inset(by: 18)
            let path = Path { p in
                guard let first = points.first else { return }
                p.move(to: box.place(first))
                for point in points.dropFirst() { p.addLine(to: box.place(point)) }
            }
            ZStack {
                path.stroke(
                    color,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round,
                                       dash: dashed ? [8, 6] : [])
                )
                if endpoints, let first = points.first, let last = points.last {
                    dot(at: box.place(first), AppTheme.green)
                    dot(at: box.place(last), AppTheme.red)
                }
            }
        }
    }

    private func dot(at point: CGPoint, _ fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .position(point)
    }
}

private struct ArtBox {
    let origin: CGPoint
    let size: CGSize

    /// Единичная точка → точка коробки. Ось Y переворачивается: у геометрии
    /// широта растёт вверх, у экрана — вниз.
    func place(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + unit.x * size.width,
                y: origin.y + (1 - unit.y) * size.height)
    }
}

private extension CGSize {
    func inset(by pad: CGFloat) -> ArtBox {
        ArtBox(origin: CGPoint(x: pad, y: pad),
               size: CGSize(width: max(1, width - pad * 2),
                            height: max(1, height - pad * 2)))
    }
}
