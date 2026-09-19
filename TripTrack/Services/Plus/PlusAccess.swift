import Foundation

/// Живой, сейчасный ответ на два вопроса: «плюс активен?» и «эта витрина
/// вообще продаёт платное?».
///
/// Пятеро зовут `PlusGate.allows` — четыре косметики и ручная поездка — и
/// каждому нужны ровно эти два бита, а не всё состояние `PlusStore`
/// (продукты, триал/актив/грейс, покупка, восстановление). Здесь — только
/// то, что читает гейт; `PlusStore` (Задача 2) держит остальное и пишет сюда.
///
/// TODO(Задача 2): слушает `Transaction.updates` и `currentEntitlements` на
/// старте, ставит `isPlus` по состоянию подписки (`.trial/.active/.grace`).
/// TODO(Задача 2): кэширует `Storefront.current.countryCode` и ставит
/// `storefrontHidesPlus` по «RUS» — решение владельца 19 сентября: витрина
/// РФ не показывает платное вовсе, но уже купленный «Плюс» честно работает
/// (см. `PlusGate` — `.hidden` считается только с `!isPlus`).
@MainActor
final class PlusAccess: ObservableObject {
    static let shared = PlusAccess()

    /// Подписка активна прямо сейчас — триал, оплаченный период или грейс.
    /// Пока всегда `false`: настоящее значение заводит `PlusStore`.
    @Published var isPlus = false

    /// Витрина устройства не продаёт платное (РФ). Пока всегда `false`.
    @Published var storefrontHidesPlus = false

    private init() {
        #if DEBUG
        // Косметику «Плюса» без витрины иначе не увидеть ни глазами, ни
        // снимком экрана: `PlusStore` (Задача 2) ещё не существует, а
        // StoreKit в симуляторе покупку не оформит. Только в Debug и только
        // по явному аргументу запуска — в релизной сборке этого кода нет.
        if ProcessInfo.processInfo.arguments.contains("-debug-plus") {
            isPlus = true
        }
        #endif
    }
}
