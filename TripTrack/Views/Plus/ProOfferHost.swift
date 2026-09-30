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
            // ОДИН лист, содержимое решает перечисление.
            //
            // Двух системных презентаций подряд UIKit не даёт (CLAUDE.md), а
            // переход «Подробнее о PRO» → пейвол — это ровно «закрыть один
            // лист и открыть другой в том же нажатии». `ManualTripEntry` в
            // этой же версии решает ту же задачу («сначала замок, потом
            // форма») тем же способом; два `.sheet` рядом означали бы уметь
            // показать оба сразу (находка ревью).
            .sheet(item: stage) { stage in
                switch stage {
                case .context(let moment):
                    contextSheet(moment)
                case .paywall(let feature):
                    PlusPaywallSheet(feature: feature)
                }
            }
    }

    /// Что показывать в единственном листе. `nil` — ничего.
    ///
    /// Запись в это состояние идёт ТОЛЬКО через координатор и `paywall`:
    /// у листа нет своего «открыт/закрыт», и рассинхронизироваться этим двум
    /// нечем.
    private var stage: Binding<Stage?> {
        Binding(
            get: {
                if let feature = paywall { return .paywall(feature) }
                if let moment = coordinator.pending, data != nil {
                    return .context(moment)
                }
                return nil
            },
            set: { value in
                guard value == nil else { return }
                // Закрытие жестом. У пейвола цены нет, у контекстного листа
                // есть: свайп вниз — то же «Не сейчас», и два подряд дают
                // паузу 90 дней. Иначе правило частоты обходилось бы жестом.
                if paywall != nil {
                    paywall = nil
                } else if let moment = coordinator.pending {
                    if ProContextOffer.sells(
                        moment,
                        storefrontHidesPlus: PlusAccess.shared.storefrontHidesPlus) {
                        coordinator.declined()
                    } else {
                        // Извещение закрывают, а не отказываются от него.
                        coordinator.acknowledged()
                    }
                }
            })
    }

    enum Stage: Identifiable, Equatable {
        case context(ProOfferMoment)
        case paywall(PlusFeature)

        var id: String {
            switch self {
            case .context(let moment): return "context.\(moment.rawValue)"
            case .paywall(let feature): return "paywall.\(feature.proIcon)"
            }
        }
    }

    @ViewBuilder
    private func contextSheet(_ moment: ProOfferMoment) -> some View {
        if let data {
            let sells = ProContextOffer.sells(
                moment,
                storefrontHidesPlus: PlusAccess.shared.storefrontHidesPlus)
            ProContextSheet(
                moment: moment,
                data: data,
                sells: sells,
                onOpen: { feature in
                    // Один лист: содержимое сменится, презентация — та же.
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
