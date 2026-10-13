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
    @State private var pendingPaywall: ProShowcaseKind?

    func body(content: Content) -> some View {
        content
            .sheet(item: $kind, onDismiss: presentPendingPaywall) { kind in
                ProShowcaseSheet(
                    kind: kind,
                    current: current(kind),
                    vehicleID: vehicle?.id,
                    onPick: { pick(kind, $0) },
                    onOpenPro: {
                        // Request the next sheet here; present it only after
                        // SwiftUI finishes dismissing the current one.
                        pendingPaywall = kind
                        self.kind = nil
                    })
                .environmentObject(lang)
            }
            .sheet(item: $paywall) { kind in
                PlusPaywallSheet(feature: kind.feature).environmentObject(lang)
            }
    }

    private func presentPendingPaywall() {
        guard let next = pendingPaywall else { return }
        pendingPaywall = nil
        paywall = next
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
        case .vehicleCard:        onPickVehicleCard(id)
        default:
            settings.selectCosmetic(kind, id: id, isPlus: PlusAccess.shared.isPlus)
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
