import SwiftUI

/// Вешает контекстное предложение на экран — состояние 11 матрицы 0.8.4.
///
/// Модификатором, а не кодом внутри «Ленты» и «Я»: экранов два, и второй
/// копии этого решения быть не должно. Вешать его на третий экран нельзя —
/// спека перечисляет запрещённые места прямым текстом (запись, экран поездки,
/// лист ручной поездки), и добавление сюда четвёртого вызывающего это
/// решение, а не деталь.
///
/// Лист появляется САМ, и это единственное место в платной части, где
/// приложение обращается первым. Поэтому решение «показывать ли» принимается
/// не здесь, а в `ProContextOffer` — чистой функцией, под календарными
/// тестами.
struct ProOfferHost: ViewModifier {
    /// Сколько у человека поездок. Приходит параметром: у «Ленты» и у «Я» это
    /// число уже посчитано, и второй похода в базу ради порога быть не должно.
    let tripCount: Int

    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var coordinator = ProOfferCoordinator.shared
    @ObservedObject private var network = CacheManager.shared.networkMonitor
    @Environment(\.colorScheme) private var scheme

    /// Снимок данных для превью. Считается ТОЛЬКО когда момент выпал: на
    /// экране, где предложения не будет, за ним идти в базу не за чем.
    @State private var data: ProDemoData?
    @State private var paywall: PlusFeature?

    func body(content: Content) -> some View {
        content
            .onAppear {
                coordinator.screenAppeared(hasNetwork: !network.isOffline,
                                           tripCount: tripCount)
            }
            .task(id: coordinator.pending) {
                guard coordinator.pending != nil, data == nil else { return }
                data = await ProDemoData.current(lang: lang.language)
            }
            .sheet(isPresented: Binding(
                get: { coordinator.pending != nil && data != nil },
                // Свайп вниз — то же самое «Не сейчас», и цена у него та же:
                // два подряд дают паузу 90 дней. Иначе правило частоты
                // обходилось бы жестом.
                set: { if !$0 { coordinator.declined() } }
            )) {
                if let moment = coordinator.pending, let data {
                    let sells = ProContextOffer.sells(
                        moment,
                        storefrontHidesPlus: PlusAccess.shared.storefrontHidesPlus)
                    ProContextSheet(
                        moment: moment,
                        data: data,
                        sells: sells,
                        onOpen: { feature in
                            coordinator.accepted()
                            paywall = feature
                        },
                        onDecline: {
                            if sells { coordinator.declined() } else { coordinator.acknowledged() }
                        })
                    .presentationDetents([.height(sheetHeight(moment))])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $paywall) { feature in
                PlusPaywallSheet(feature: feature)
            }
    }

    /// Высота — ЧИСЛОМ (`ProLayout.contextSheet(titleLines:)`), а не
    /// измерением содержимого: правило проекта, купленное дважды сломанным
    /// экраном «Атласа». Число строк заголовка считается по его ДЛИНЕ, а не по
    /// номеру момента: длина зависит от языка, и угадывать по моменту значит
    /// угадывать за тринадцать языков сразу.
    private func sheetHeight(_ moment: ProOfferMoment) -> CGFloat {
        let metrics = WindowLayoutMetrics.shared
        let layout = ProLayout(height: metrics.size?.height ?? 844,
                               safeTop: metrics.safeAreaInsets?.top ?? 47,
                               safeBottom: metrics.safeAreaInsets?.bottom ?? 34)
        let title = ProContextSheet.title(moment, lang.language)
        return layout.contextSheet(titleLines: ProLayout.titleLines(for: title))
    }
}

extension View {
    /// Вешать ТОЛЬКО на «Ленту» и на «Я». Список закрыт спекой §11.
    func proContextOffer(tripCount: Int) -> some View {
        modifier(ProOfferHost(tripCount: tripCount))
    }
}

/// `sheet(item:)` для `PlusFeature`: у него нет `Identifiable`, а заводить его
/// у перечисления, которое лежит в гейте, значило бы протащить в сервис
/// требование SwiftUI.
private struct IdentifiedFeature: Identifiable {
    let id: String
    let feature: PlusFeature
}

private extension View {
    func sheet<Content: View>(
        item: Binding<PlusFeature?>,
        @ViewBuilder content: @escaping (PlusFeature) -> Content
    ) -> some View {
        sheet(item: Binding<IdentifiedFeature?>(
            get: { item.wrappedValue.map { IdentifiedFeature(id: $0.proIcon, feature: $0) } },
            set: { if $0 == nil { item.wrappedValue = nil } }
        )) { wrapped in
            content(wrapped.feature)
        }
    }
}
