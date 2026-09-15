import Foundation

/// Мир, каким он был на дату, — посчитанный один раз на дату.
///
/// `RevealedLayerStore.layer(before:)` перебирает ВСЮ библиотеку превью: это
/// честная цена одного снимка и совершенно неподъёмная — трёх. А их именно
/// три: карта-герой на экране поездки, полноэкранная карта, открытая с неё, и
/// та же карта, пересозданная после поворота или возврата назад. Дата у всех
/// трёх одна (`trip.endDate`), значит и ответ один.
///
/// Считается ВНЕ главного актёра (`Task.detached`): внутри стора на своём
/// контексте живёт только выборка, а сборка полилиний трёх уровней детали
/// возвращается в вызвавший актёр — и на главном это те самые сотни
/// миллисекунд, ради которых и заводили фоновый контекст.
@MainActor
final class TemporalFogCache {
    static let shared = TemporalFogCache()

    private var entry: (cutoff: Date?, layer: RevealedLayer)?
    private var pending: (cutoff: Date?, task: Task<RevealedLayer, Never>)?
    /// Растёт на каждой инвалидации. Считанный слой ложится в кэш ТОЛЬКО если
    /// поколение с начала счёта не сменилось: уведомление «открытое
    /// изменилось» приходит и посреди `await`, и без этой проверки следующая
    /// строка положила бы в только что очищенный кэш уже устаревший ответ.
    private var generation = 0

    init() {
        // Открытое изменилось (финиш поездки, фоновая сборка, стирание) —
        // снимок на дату мог измениться тоже: поездка, доехавшая со второго
        // телефона, лежит в прошлом.
        NotificationCenter.default.addObserver(
            forName: .revealedLayerChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    func invalidate() {
        generation &+= 1
        entry = nil
        // Отменяем, а не просто забываем: ответ этого перебора уже никому не
        // нужен, и помечать его отменённым честнее, чем терять ссылку.
        pending?.task.cancel()
        pending = nil
    }

    /// Пересчитать, не веря кэшу.
    ///
    /// Зовётся тем, кто САМ услышал `.revealedLayerChanged`: порядок
    /// наблюдателей у `NotificationCenter` не наш, и кэш мог ещё не узнать о
    /// том же уведомлении.
    func reload(before cutoff: Date?) async -> RevealedLayer {
        invalidate()
        return await layer(before: cutoff)
    }

    /// Снимок мира на дату. `nil` — открытое, как оно есть.
    ///
    /// Второй спрашивающий с той же датой не запускает второй перебор: он ждёт
    /// первый. Без этого карта-герой и полноэкранная карта, открытые подряд,
    /// перебирали бы библиотеку вдвоём.
    func layer(before cutoff: Date?) async -> RevealedLayer {
        if let entry, entry.cutoff == cutoff { return entry.layer }
        if let pending, pending.cutoff == cutoff { return await pending.task.value }

        let task = Task.detached(priority: .userInitiated) {
            await RevealedLayerStore.shared.layer(before: cutoff)
        }
        pending = (cutoff, task)
        let started = generation
        let layer = await task.value
        guard started == generation else { return layer }
        if pending?.cutoff == cutoff { pending = nil }
        entry = (cutoff, layer)
        return layer
    }
}
