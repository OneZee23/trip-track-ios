import SwiftUI

/// Нижняя панель вкладки «Места»: одна на все состояния (принцип 1 спеки).
///
/// Выбор булавки, подсказка, поиск, порядок и группы меняют СОДЕРЖИМОЕ, а не
/// контейнер. Вторую панель поверх первой заводить нельзя: на «Атласе» это
/// читалось как «открылась какая-то другая модалка» и стоило нам целой волны
/// правок.
///
/// Устроена так же, как `AtlasSheet`, и по тем же причинам:
/// - положение задаётся СМЕЩЕНИЕМ в координатах контейнера, а не разметкой:
///   слой, вынесенный `.ignoresSafeArea()` или отодвинутый гигантским
///   отступом, перестаёт помещаться в контейнер, и SwiftUI отвечает на это
///   сдвигом безопасной зоны ВСЕГО ОКНА (CLAUDE.md, 27 сен 2026);
/// - первая строка ЗАКРЕПЛЕНА над скроллом: выход и заголовок обязаны быть на
///   месте, сколько бы человек ни пролистал;
/// - правила жеста общие с «Атласом» и живут в `SlotGesture`.
struct PlacesPanel<Header: View, Content: View>: View {
    let slot: PlacesSlot
    @Binding var stop: PlacesPanelStop
    /// Живой верх во время жеста: за ним в реальном времени идут поля карты.
    @Binding var liveTop: CGFloat?
    /// Пустые состояния держат одно положение и не тянутся (спека §4).
    var isPinned: Bool = false
    var accessibilityTitle: String = ""
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStart: CGFloat?
    /// Сколько экрана снизу занимает клавиатура.
    ///
    /// Нужна не ради отступов, а ради ВЫСОТЫ панели. Панель высокая
    /// (`экран − верх`), и с поднятой клавиатурой она перестаёт помещаться в
    /// свой контейнер — SwiftUI отвечает на это не обрезкой, а сдвигом всего
    /// содержимого ВВЕРХ: проба показала `top=115`, а настоящий кадр панели
    /// `y = −81`, то есть поле поиска легло на часы. Четыре попытки снять
    /// это через `ignoresSafeArea(.keyboard)` на четырёх уровнях дерева не
    /// дали ничего, потому что лечили не ту причину: контейнер сжимается
    /// законно, а не помещается в него именно панель.
    @State private var keyboardInset: CGFloat = 0

    private var top: CGFloat { liveTop ?? slot.top(of: stop) }

    /// Верх В КООРДИНАТАХ КОНТЕЙНЕРА: `PlacesSlot` считает от края экрана, а
    /// слой панели живёт внутри безопасной зоны и обязан там остаться.
    private var containerTop: CGFloat { top - slot.safeTop }

    var body: some View {
        VStack(spacing: 0) {
            handle
            header()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: max(0, slot.height - top - keyboardInset), alignment: .top)
        // Содержимое ОБРЕЗАЕТСЯ рамкой панели. В половине скролла нет по
        // спеке — он начинается в полном списке, — и без обрезки лишние
        // карточки просто вываливались бы поверх таб-бара: ровно тот кадр,
        // из-за которого «Атлас» и «Места» читались неаккуратными.
        .clipped()
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: AtlasTheme.sheetRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: AtlasTheme.sheetRadius,
                style: .continuous
            )
            .fill(AtlasTheme.background)
            .shadow(color: .black.opacity(scheme == .dark ? 0.32 : 0.16), radius: 28, y: -8)
            .ignoresSafeArea(edges: .bottom)
        )
        // ПРИБИТА К ВЕРХУ КОНТЕЙНЕРА, и это не косметика.
        //
        // `ZStack` центрирует детей, а у панели высота фиксированная. Стоит
        // контейнеру сжаться — а он сжимается, когда приезжает клавиатура, —
        // и центрированная панель уезжает вверх на половину этой разницы:
        // поле поиска ложилось на часы и на значок батареи. Смещение при
        // этом обязано отсчитываться от ВЕРХА, иначе оно означает разное на
        // разной высоте контейнера. Поймано кадром на симуляторе; три
        // попытки снять это через `ignoresSafeArea(.keyboard)` не дали
        // ничего, потому что лечили не ту причину.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: containerTop)
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect else { return }
            keyboardInset = max(0, slot.height - frame.origin.y)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardInset = 0
        }
        .gesture(isPinned ? nil : drag)
        .accessibilityElement(children: .contain)

    }

    private var handle: some View {
        Capsule()
            .fill(AtlasTheme.handle)
            .frame(width: 36, height: 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // Ручка — настоящий элемент: по ней сторож меряет верх панели.
            .accessibilityElement()
            .accessibilityLabel(accessibilityTitle)
            .accessibilityIdentifier("places_panel_handle")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? slot.top(of: stop)
                dragStart = start
                liveTop = slot.clamped(start + value.translation.height)
            }
            .onEnded { value in
                let start = dragStart ?? slot.top(of: stop)
                let landed = slot.clamped(start + value.translation.height)
                dragStart = nil
                let settled = slot.settle(top: landed, velocity: value.velocity.height, from: stop)
                withAnimation(SlotGesture.animation(reduceMotion: reduceMotion)) {
                    stop = settled
                    liveTop = nil
                }
            }
    }
}
