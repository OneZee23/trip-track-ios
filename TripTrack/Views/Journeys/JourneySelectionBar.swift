import SwiftUI

/// Второй вход в путешествие (0.6.6): человек держит палец на карточке в «Мои»,
/// отмечает ещё пару поездок и складывает их в одну историю.
///
/// Здесь живут ОБА куска этого режима — плавающая полоса внизу и обёртка
/// вокруг карточки, — потому что порознь они бессмысленны: полоса без галочек
/// не объясняет, что происходит, а галочки без полосы не дают выйти. Экран
/// («Мои») держит только состояние выбора.

// MARK: - Плавающая полоса

/// Появляется, пока что-то выбрано, и встаёт ровно туда, где стоял таб-бар:
/// «Мои» на время выбора его прячет. Так делает и «Фото» — уводить человека
/// на другую вкладку с недособранным путешествием некуда, а полоса поверх
/// таб-бара оставила бы под пальцем две панели сразу.
struct JourneySelectionBar: View {
    let count: Int
    let onCreate: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                onCancel()
            } label: {
                Text(AppStrings.cancel(lang.language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(c.cardAlt, in: Capsule())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("journey_selection_cancel")

            Button {
                Haptics.action()
                onCreate()
            } label: {
                Text(AppStrings.journeySelectAction(lang.language, count: count))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("journey_selection_create")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            // Та же стеклянная пилюля, что у таб-бара: полоса занимает его
            // место, и другой материал читался бы как чужая панель.
            ZStack {
                RoundedRectangle(cornerRadius: 30).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 30).stroke(c.glassBorder, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 3, y: 3)
        .padding(.horizontal, 11)
        // Ровно как у `CustomTabBar`: экран не уважает нижнюю безопасную зону,
        // и пилюля поднимается над домашним индикатором вручную.
        .padding(.bottom, 14)
    }
}

// MARK: - Карточка в режиме выбора

/// Обёртка вокруг ГОТОВОЙ карточки поездки — списочной или сеточной.
///
/// Внутрь `ProfileTripCardView` / `ProfileTripTile` она не лезет и кнопку у них
/// не отбирает: вне режима выбора обе карточки обязаны вести себя ровно как
/// прежде, вместе со своим тактильным откликом. Оба жеста — долгое нажатие и
/// тап-отметка — идут `simultaneousGesture`, то есть ВМЕСТЕ с кнопкой
/// карточки, а не вместо неё.
///
/// Отсюда правило на стороне экрана: `onOpen` в режиме выбора обязан молчать.
/// Кнопка карточки доложит о нажатии и тогда, когда человек просто отпустил
/// палец после долгого нажатия, — и без этого молчания каждый вход в режим
/// выбора увозил бы на экран поездки.
struct JourneySelectable: ViewModifier {
    let isSelecting: Bool
    let isSelected: Bool
    /// Тап в режиме выбора — поставить/снять галочку.
    let onToggle: () -> Void
    /// Долгое нажатие — вход в режим выбора.
    let onLongPress: () -> Void

    @Environment(\.colorScheme) private var scheme
    /// Палец на карточке. `@GestureState`, а не `@State`: прокрутка забирает
    /// жест себе, и сбросить сжатие вручную было бы уже некому.
    @GestureState private var holding = false

    /// Полсекунды — столько же ждёт система до контекстного меню, и столько же
    /// длится сжатие в `HoldableCardStyle`, чьи числа здесь и повторены:
    /// карточка «поддаётся» ровно к тому моменту, когда режим включается.
    /// Своим стилем кнопки это не сделать — кнопка у карточки уже своя.
    private static let holdDuration: TimeInterval = 0.5

    func body(content: Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content
                .scaleEffect(holding ? 0.945 : 1)
                .animation(.easeOut(duration: holding ? 0.5 : 0.18), value: holding)
                // Долгий тап здесь что-то открывает — значит это видно под
                // пальцем (CLAUDE.md, «Нажатие обязано отвечать»).
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: Self.holdDuration)
                        .updating($holding) { pressing, state, _ in state = pressing }
                        .onEnded { _ in onLongPress() }
                )
                // Вне режима выбора жест выключен маской `.subviews`: тап
                // остаётся кнопке карточки, как и был.
                .simultaneousGesture(
                    TapGesture().onEnded { onToggle() },
                    including: isSelecting ? .all : .subviews
                )
            if isSelecting { tick }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Галочка в верхнем углу. Под ней сплошной кружок цвета карточки: без
    /// подложки пустой контур терялся на карте в сеточной плитке.
    private var tick: some View {
        let c = AppTheme.colors(for: scheme)
        return ZStack {
            Circle()
                .fill(c.card)
                .frame(width: 19, height: 19)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.accent : c.textTertiary)
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Карточка поездки, которую можно отметить в путешествие.
    func journeySelectable(
        isSelecting: Bool,
        isSelected: Bool,
        onToggle: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) -> some View {
        modifier(JourneySelectable(
            isSelecting: isSelecting,
            isSelected: isSelected,
            onToggle: onToggle,
            onLongPress: onLongPress
        ))
    }
}

// MARK: - Путешествие, пока идёт выбор

/// Карточка путешествия в режиме выбора приглушена и не нажимается: её плечи
/// УЖЕ в путешествии, второй раз их туда не сложить. Приглушить, а не спрятать
/// — иначе история на глазах меняла бы порядок под пальцем.
struct JourneyInertWhileSelecting: ViewModifier {
    let isSelecting: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isSelecting ? 0.5 : 1)
            .allowsHitTesting(!isSelecting)
    }
}
