import SwiftUI

/// Затемнение под статус-баром и домашним индикатором.
///
/// Статус-бар iOS не имеет собственной подложки: часы, связь и заряд рисуются
/// прямо поверх экрана. Пока сверху стоит наша шапка — это и не нужно, но на
/// экранах, где карта или фотография идут во весь экран, глифы ложатся на
/// светлые кварталы и снег и пропадают. Градиент возвращает им фон, не отбирая
/// у карты ни точки высоты.
///
/// Накладка (`overlay`), а не подложка: под картой её никто бы не увидел.
/// Нажатия она не берёт — под ней живые карты и кнопки, — и не уважает
/// безопасную зону, потому что затемняет ровно её.
///
/// Низ по умолчанию выключен: домашний индикатор система рисует сама и
/// подкрашивает под фон, а у большинства наших полноэкранных карт внизу и так
/// стоит своя плашка. Включать его стоит там, где под индикатором пусто.
struct EdgeScrims: ViewModifier {
    let top: Bool
    let bottom: Bool
    let topStrength: Double
    let bottomStrength: Double

    /// Высота считается от окна, а не от вёрстки: накладка стоит на экранах,
    /// которые безопасную зону нарочно игнорируют, и `GeometryReader` вернул
    /// бы им нули (см. `tt_safeAreaInsets`).
    ///
    /// +28 — чтобы градиент не обрывался ровно по нижней кромке часов: резкая
    /// граница читается как полоса поперёк карты, а плавный хвост не читается
    /// вовсе.
    private var topHeight: CGFloat { (UIApplication.tt_safeAreaInsets?.top ?? 47) + 28 }

    private var bottomHeight: CGFloat { (UIApplication.tt_safeAreaInsets?.bottom ?? 34) + 24 }

    func body(content: Content) -> some View {
        content.overlay {
            VStack(spacing: 0) {
                if top {
                    LinearGradient(
                        colors: [.black.opacity(topStrength), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: topHeight)
                }
                Spacer(minLength: 0)
                if bottom {
                    LinearGradient(
                        colors: [.clear, .black.opacity(bottomStrength)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: bottomHeight)
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

extension View {
    /// Затемнение краёв на экране, который идёт под статус-бар.
    ///
    /// Ставить НИЖЕ собственной шапки экрана: кнопки и заголовок должны
    /// остаться чёткими, затемняется то, что под ними.
    func edgeScrims(
        top: Bool = true,
        bottom: Bool = false,
        topStrength: Double = 0.42,
        bottomStrength: Double = 0.30
    ) -> some View {
        modifier(EdgeScrims(
            top: top, bottom: bottom,
            topStrength: topStrength, bottomStrength: bottomStrength
        ))
    }
}
