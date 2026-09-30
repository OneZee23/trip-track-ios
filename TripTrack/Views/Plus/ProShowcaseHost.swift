import SwiftUI

/// Вешает витрину оформления на экран — состояния 21…27.
///
/// Модификатором и с ЧТЕНИЕМ-ЗАПИСЬЮ внутри, потому что входов четыре:
/// «Фон профиля» и «Рамка аватара» из хаба «Мой профиль», «Фон карточки» из
/// формы машины, «Линия маршрута» из настроек. Четыре копии «что выбрано и
/// куда писать» разошлись бы — и разошлись бы там, где это дорого: в
/// сохранении выбора.
///
/// Вторая причина — предел вывода типов SwiftUI. `ProfileView.body` уже
/// упирался в него на ОДНОМ добавленном модификаторе (CLAUDE.md, «Ловушки»), и
/// два `.sheet` с замыканиями внутри цепочки его уронили: сборка отвечает
/// «unable to type-check this expression in reasonable time». Здесь они живут
/// вне `body` вызывающего.
struct ProShowcaseHost: ViewModifier {
    /// Какая витрина открыта. `nil` — никакая.
    @Binding var kind: ProShowcaseKind?
    /// Машина, чей фон карточки правим. `nil` у трёх остальных видов.
    var vehicle: Vehicle?
    /// Выбор фона карточки машины — он живёт не в `SettingsManager`, а в
    /// самой машине, и писать его умеет только форма.
    var onPickVehicleCard: (String) -> Void = { _ in }

    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared

    /// Пейвол, открытый ИЗ витрины. Хранится ВИДОМ витрины, а не фичей:
    /// `PlusFeature` живёт в гейте, и вешать на него `Identifiable` значило бы
    /// протащить требование SwiftUI в сервисный тип. Фича выводится.
    @State private var paywall: ProShowcaseKind?

    func body(content: Content) -> some View {
        content
            .sheet(item: $kind) { kind in
                ProShowcaseSheet(
                    kind: kind,
                    current: current(kind),
                    onPick: { pick(kind, $0) },
                    onOpenPro: {
                        // Витрина не продаёт сама: она закрывается, и продаёт
                        // пейвол. Два листа подряд здесь не выходит — второй
                        // открывается ПОСЛЕ закрытия первого, своим состоянием.
                        self.kind = nil
                        paywall = kind
                    })
                .environmentObject(lang)
            }
            .sheet(item: $paywall) { kind in
                PlusPaywallSheet(feature: kind.feature).environmentObject(lang)
            }
    }

    /// Что выбрано в базе. Витрина примеряет у себя, а сохранённое читает
    /// отсюда.
    private func current(_ kind: ProShowcaseKind) -> String {
        switch kind {
        case .profileBackground: return settings.profileBackground
        case .avatarFrame:        return settings.avatarFrame ?? ""
        case .vehicleCard:        return vehicle?.cardStyle ?? ""
        case .routeLine:          return RouteLineStyle.stored.rawValue
        }
    }

    /// Человек выбрал доступный ему вариант. Платный без подписки сюда НЕ
    /// приходит — витрина его только примеряет.
    private func pick(_ kind: ProShowcaseKind, _ id: String) {
        switch kind {
        case .profileBackground: settings.profileBackground = id
        case .avatarFrame:        settings.setAvatarFrame(id.isEmpty ? nil : id)
        case .vehicleCard:        onPickVehicleCard(id)
        case .routeLine:          RouteLineStyle.stored = RouteLineStyle.from(id)
        }
    }
}

extension View {
    /// Витрина оформления. Зовут четыре входа, и все четыре — через это.
    func proShowcase(
        _ kind: Binding<ProShowcaseKind?>,
        vehicle: Vehicle? = nil,
        onPickVehicleCard: @escaping (String) -> Void = { _ in }
    ) -> some View {
        modifier(ProShowcaseHost(kind: kind,
                                 vehicle: vehicle,
                                 onPickVehicleCard: onPickVehicleCard))
    }
}
