import SwiftUI

/// Гейт «Плюса» у ручной поездки — в ОДНОМ месте на оба входа.
///
/// Входов в лист два («+» в «Мои» и «…» на ленте), и решение «показывать ли
/// его вообще» у них обязано быть одно. Разойдясь, они дали бы на витрине,
/// которая не продаёт платное, кнопку в одном экране и пустоту в другом —
/// ровно тем способом, каким расползались единицы измерения до `Measure`.
@MainActor
enum ManualTripEntry {

    /// Что сейчас с фичей. Читает `PlusAccess` СВЕЖО на каждом вызове: витрина
    /// и подписка приезжают асинхронно, и закэшированный ответ однажды
    /// оказался бы вчерашним.
    static var level: PlusAccessLevel {
        PlusGate.allows(
            .manualTrip,
            isPlus: PlusAccess.shared.isPlus,
            storefrontHidesPlus: PlusAccess.shared.storefrontHidesPlus
        )
    }

    /// Рисовать ли вход вообще. `.hidden` — не «замок, который не работает»,
    /// а отсутствие пункта: спека §1 требует, чтобы платного не было ВИДНО.
    static var isVisible: Bool { level != .hidden }

    /// Стоит ли рядом со входом замок.
    static var isLocked: Bool { level == .locked }
}

private struct ManualTripHost: ViewModifier {
    @Binding var isPresented: Bool
    let tripManager: TripManager
    let onCreated: (UUID) -> Void

    @EnvironmentObject private var lang: LanguageManager

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            // Один лист, содержимое решает гейт. Две презентации подряд
            // («сначала замок, потом форма») UIKit не даёт, а держать здесь
            // два `.sheet` значило бы уметь показать оба сразу.
            if ManualTripEntry.isLocked {
                PlusPaywallSheet()
                    .environmentObject(lang)
            } else {
                ManualTripSheet(tripManager: tripManager, onCreated: onCreated)
                    .environmentObject(lang)
            }
        }
    }
}

extension View {
    /// Вешает лист ручной поездки (или пейвол, если «Плюса» нет) на экран.
    /// Кнопку рисует вызывающий — она у двух входов разная, а лист один.
    func manualTripHost(
        isPresented: Binding<Bool>,
        tripManager: TripManager,
        onCreated: @escaping (UUID) -> Void = { _ in }
    ) -> some View {
        modifier(ManualTripHost(
            isPresented: isPresented, tripManager: tripManager, onCreated: onCreated))
    }
}
