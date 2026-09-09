import SwiftUI

/// Дымка под статус-баром и домашним индикатором.
///
/// Статус-бар iOS не имеет собственной подложки: часы, связь и заряд рисуются
/// прямо поверх экрана. Пока сверху стоит наша шапка — это и не нужно, но на
/// экранах, где карта или фотография идут во весь экран, глифы ложатся на
/// пёстрые кварталы и пропадают. Градиент возвращает им фон, не отбирая у
/// карты ни точки высоты.
///
/// **Цвет дымки идёт от ТЕМЫ, а не один на всё.** Стиль статус-бара у нас
/// общий на окно (`ThemeManager.paint`), пер-экранного переключателя нет: в
/// светлой теме глифы ЧЁРНЫЕ, и под ними нужна светлая дымка — чёрная съела бы
/// последний контраст; в тёмной глифы БЕЛЫЕ, и нужна тёмная. Одна чёрная
/// накладка на обе темы чинила бы одну ценой другой.
///
/// Белого нужно заметно больше по непрозрачности: чёрный текст на светлом фоне
/// теряет контраст быстрее, чем белый на тёмном, и полупрозрачная белизна над
/// пёстрой картой гасит её слабее, чем та же доля черноты.
///
/// Накладка (`overlay`), а не подложка: под картой её никто бы не увидел.
/// Нажатия она не берёт — под ней живые карты и кнопки, — и не уважает
/// безопасную зону, потому что закрывает ровно её.
///
/// Низ по умолчанию выключен: домашний индикатор система рисует сама и
/// подкрашивает под фон, а у большинства наших полноэкранных карт внизу и так
/// стоит своя плашка. Включать его стоит там, где под индикатором пусто.
struct EdgeScrims: ViewModifier {
    let top: Bool
    let bottom: Bool
    /// Непрозрачность ЧЁРНОЙ дымки — то есть тёмной темы. У светлой свои числа
    /// (`lightTop` / `lightBottom`): пересчитать одно из другого нечем, белизна
    /// и чернота гасят карту по-разному.
    let topStrength: Double
    let bottomStrength: Double

    @Environment(\.colorScheme) private var scheme

    private static let lightTop: Double = 0.72
    private static let lightBottom: Double = 0.55

    /// Высота считается от окна, а не от вёрстки: накладка стоит на экранах,
    /// которые безопасную зону нарочно игнорируют, и `GeometryReader` вернул
    /// бы им нули (см. `tt_safeAreaInsets`).
    ///
    /// +28 — чтобы градиент не обрывался ровно по нижней кромке часов: резкая
    /// граница читается как полоса поперёк карты, а плавный хвост не читается
    /// вовсе.
    private var topHeight: CGFloat { (UIApplication.tt_safeAreaInsets?.top ?? 47) + 28 }

    private var bottomHeight: CGFloat { (UIApplication.tt_safeAreaInsets?.bottom ?? 34) + 24 }

    private var haze: Color { scheme == .dark ? .black : .white }

    private var topOpacity: Double { scheme == .dark ? topStrength : Self.lightTop }

    private var bottomOpacity: Double { scheme == .dark ? bottomStrength : Self.lightBottom }

    func body(content: Content) -> some View {
        content.overlay {
            VStack(spacing: 0) {
                if top {
                    LinearGradient(
                        colors: [haze.opacity(topOpacity), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: topHeight)
                }
                Spacer(minLength: 0)
                if bottom {
                    LinearGradient(
                        colors: [.clear, haze.opacity(bottomOpacity)],
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
    /// Дымка по краям экрана, который идёт под статус-бар. Цвет выбирает тема:
    /// светлая в светлой, тёмная в тёмной — см. `EdgeScrims`.
    ///
    /// Ставить НИЖЕ собственной шапки экрана: кнопки и заголовок должны
    /// остаться чёткими, приглушается то, что под ними.
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
