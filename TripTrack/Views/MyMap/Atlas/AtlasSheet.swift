import SwiftUI

/// Шторка «Атласа»: один слот у нижнего края, три положения, одна пружина.
///
/// Своя, а не `presentationDetents`: системный лист накрывает таб-бар и
/// забирает жесты у карты, а здесь карта под шторкой обязана остаться живой
/// (принцип 4) и таб-бар — стоять на месте (спека §4). Плюс `peek` — не
/// «маленький детент», а состояние, в которое шторку уводит выбор места, и
/// системному листу такое не выразить.
///
/// Геометрию и правила жеста держит `AtlasSlot` — чистый и под тестами;
/// здесь только руки.
struct AtlasSheet<Content: View>: View {
    let slot: AtlasSlot
    let variant: AtlasSummaryVariant
    @Binding var detent: AtlasSheetDetent
    /// Живой верх во время жеста. Наружу — потому что за ним следуют кнопки
    /// карты и подпись Apple: «одна пружина на всё нижнее» (принцип 5)
    /// означает, что и во время жеста они идут за тем же числом.
    @Binding var liveTop: CGFloat?
    /// Тап по свёрнутой шторке раскрывает список; по строке подсказки —
    /// снимает выбор места и тоже раскрывает.
    var onTapCollapsed: () -> Void = {}
    /// Закрыть подсостояние. Непустое значение и ПЕРЕВОДИТ шторку в режим
    /// подсостояния: тянуть вверх там некуда (верх держится не выше 420,
    /// чтобы заголовок вкладки и кнопки карты остались), и жест вниз
    /// означает «закрыть», а не «свернуть».
    var onDismissSubstate: (() -> Void)?
    /// «Итоги атласа, свёрнуто / раскрыто» — собирает зовущий, у него язык.
    var accessibilityTitle: String = ""
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStart: CGFloat?

    /// Пружина всего нижнего (спека §6). «Уменьшить движение» заменяет её
    /// кроссфейдом 0.2 с — тем же правилом, что у всей вкладки.
    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)
    }

    private var top: CGFloat { liveTop ?? slot.top(of: detent, variant: variant) }

    /// Верх шторки В КООРДИНАТАХ КОНТЕЙНЕРА, а не экрана.
    ///
    /// `AtlasSlot` считает от края ЭКРАНА, а слой шторки живёт внутри
    /// безопасной зоны — и обязан там остаться. Прежняя редакция выносила его
    /// наружу `.ignoresSafeArea()`, и это стоило экрана: в РАСКРЫТОМ
    /// положении внутри шторки стоит `ScrollView`, а он считает свои вставки
    /// от безопасной зоны; вынесенный за неё, он менял её У ВСЕГО ОКНА.
    /// Замер 27 сентября: заголовок вкладки уезжал с 59 pt на 19.7 (то есть
    /// под часы), а таб-бар — с 768 на 773.7. Видно это становилось на
    /// экране региона, потому что его и открывают из раскрытого списка, —
    /// и выглядело как «шапка налезает на статус-бар» (владелец на
    /// устройстве). Держит `AtlasChromeGeometryTests`.
    ///
    /// Низ при этом достаёт до физического края и без вылета за безопасную
    /// зону: `ContentView` отдаёт вкладкам низ целиком
    /// (`.ignoresSafeArea(edges: .bottom)`), а сумма `offset + height` по
    /// построению равна высоте экрана при любом верхе, включая резинку.
    private var containerTop: CGFloat { top - slot.safeTop }

    var body: some View {
        VStack(spacing: 0) {
            handle
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: max(0, slot.height - top), alignment: .top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: AtlasTheme.sheetRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: AtlasTheme.sheetRadius
            )
            .fill(AtlasTheme.background)
            .shadow(color: .black.opacity(scheme == .dark ? 0.32 : 0.16), radius: 14, y: -8)
            .ignoresSafeArea(edges: .bottom)
        )
        .offset(y: containerTop)
        .gesture(drag)
        .accessibilityElement(children: .contain)
    }

    private var isSubstate: Bool { onDismissSubstate != nil }

    private var handle: some View {
        Capsule()
            .fill(AtlasTheme.handle)
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            // Ручку и полосу вокруг неё нажимают, чтобы раскрыть: в сводке
            // это то же действие, что тап по блоку.
            .contentShape(Rectangle())
            .onTapGesture(perform: onTapCollapsed)
            // Ручка — настоящий элемент: её нажимают, чтобы раскрыть список,
            // и по ней же сторож меряет, где стоит верх шторки.
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityIdentifier("atlas_sheet_handle")
    }

    private var drag: some Gesture {
        isSubstate ? AnyGesture(substateDrag.map { _ in () })
                   : AnyGesture(detentDrag.map { _ in () })
    }

    /// Жест подсостояния: вверх — к списку, вниз ниже своей высоты — закрыть.
    private var substateDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? slot.top(of: detent, variant: variant)
                dragStart = start
                liveTop = slot.substateTop(dragged: start + value.translation.height,
                                           variant: variant)
            }
            .onEnded { value in
                let start = dragStart ?? slot.top(of: detent, variant: variant)
                let landed = slot.substateTop(dragged: start + value.translation.height,
                                              variant: variant)
                dragStart = nil
                if AtlasSlot.substateDismisses(top: landed, velocity: value.velocity.height,
                                               slot: slot, variant: variant) {
                    withAnimation(settleAnimation) { liveTop = nil }
                    onDismissSubstate?()
                    return
                }
                let settled = AtlasSlot.settle(top: landed, velocity: value.velocity.height,
                                               slot: slot, variant: variant)
                withAnimation(settleAnimation) {
                    detent = settled
                    liveTop = nil
                }
            }
    }

    private var detentDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? slot.top(of: detent, variant: variant)
                dragStart = start
                // Нижняя граница — сводка; пока шторка в подсказке, ею
                // становится сама подсказка, иначе карточка места
                // подпрыгивала бы от любого касания.
                let lower: AtlasSheetDetent = detent == .peek ? .peek : .collapsed
                liveTop = slot.clamped(top: start + value.translation.height,
                                       lowerBound: lower, variant: variant)
            }
            .onEnded { value in
                let start = dragStart ?? slot.top(of: detent, variant: variant)
                let landed = slot.clamped(top: start + value.translation.height,
                                          lowerBound: detent == .peek ? .peek : .collapsed,
                                          variant: variant)
                dragStart = nil
                let settled = AtlasSlot.settle(top: landed, velocity: value.velocity.height,
                                               slot: slot, variant: variant)
                withAnimation(settleAnimation) {
                    detent = settled
                    liveTop = nil
                }
            }
    }
}
