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
        .offset(y: top)
        .gesture(drag)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }

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
    }

    private var drag: some Gesture {
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
