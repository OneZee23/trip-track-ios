import Foundation

/// Живой, сейчасный ответ на два вопроса: «плюс активен?» и «эта витрина
/// вообще продаёт платное?».
///
/// Пятеро зовут `PlusGate.allows` — четыре косметики и ручная поездка — и
/// каждому нужны ровно эти два бита, а не всё состояние `PlusStore`
/// (продукты, триал/актив/грейс, покупка, восстановление). Здесь — только
/// то, что читает гейт; `PlusStore` держит остальное и пишет сюда.
///
/// Оба бита пишет `PlusStore`: `isPlus` — по `currentEntitlements` и статусу
/// группы, `storefrontHidesPlus` — по `Storefront.current.countryCode`.
/// Решение владельца 19 сентября: витрина РФ не показывает платное вовсе, но
/// уже купленный «Плюс» честно работает (см. `PlusGate` — `.hidden`
/// считается только с `!isPlus`).
@MainActor
final class PlusAccess: ObservableObject {
    static let shared = PlusAccess()

    /// Ключ последней ИЗВЕСТНОЙ витрины. Живёт здесь, а не в `PlusStore`,
    /// потому что читается раньше него — в `init` этого класса.
    static let storefrontKey = "plus.storefront.country.v1"

    /// Подписка активна прямо сейчас — триал, оплаченный период или грейс.
    @Published var isPlus = false

    /// Витрина устройства не продаёт платное (РФ).
    ///
    /// **Засевается ПАМЯТЬЮ, а не нулём.** `Storefront.current` отвечает
    /// асинхронно и в офлайне умеет ответить `nil`; пока он молчит, `false`
    /// здесь означал бы «платное показать» — то есть на витрине РФ каждый
    /// холодный старт открывался строкой «Плюс», замками у косметик и
    /// работающим пейволом. Первый запуск (памяти ещё нет) отвечает по
    /// региону устройства: он тоже не истина, но ошибается в безопасную
    /// сторону и исправляется первым же ответом StoreKit.
    @Published var storefrontHidesPlus = false

    private init() {
        let remembered = UserDefaults.standard.string(forKey: Self.storefrontKey)
            ?? Locale.current.region?.identifier
        storefrontHidesPlus = PlusStore.hidesPlus(countryCode: remembered)

        #if DEBUG
        // Косметику «Плюса» без витрины иначе не увидеть ни глазами, ни
        // снимком экрана: StoreKit в симуляторе покупку не оформит. Только в
        // Debug и только по явному аргументу запуска — в релизной сборке
        // этого кода нет. Держит флаг живым сам `PlusStore`: обновление прав
        // иначе стирало бы его через секунду после старта.
        if PlusStore.isDebugPlus {
            isPlus = true
            storefrontHidesPlus = false
        }
        #endif
    }
}
