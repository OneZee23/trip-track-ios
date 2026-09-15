import Foundation

/// Пачка уведомлений — ОДИН пересчёт.
///
/// Финиш поездки присылает три подряд: `.tripRecordingEnded`,
/// `.revealedLayerChanged` и (после пересборки территории) `.territoryRebuilt`.
/// Поколение загрузки защищает только ПРИМЕНЕНИЕ результата — сама работа
/// делается трижды, а с 0.7.0 она стоит дорого: каждый `apply` создаёт новый
/// `FogVeilOverlay`, MapKit на него — новый `FogVeilRenderer`, а тот собирает
/// `MapPathIndex` по всей открытой библиотеке. Три полных сборки `CGPath` в ту
/// же секунду, когда телефон дописывает поездку, считает места и шлёт синк. И
/// видно это глазами: пока новый индекс собирается, тайлы рисуются сплошной
/// заливкой без коридоров, то есть подмена оверлея = вспышка «всё закрыто».
///
/// Отдельным типом — потому что правило проверяется тестом, а не финишем
/// поездки: «три уведомления подряд дают одну пересборку» иначе можно было бы
/// подтвердить только поездкой на машине.
@MainActor
final class ReloadCoalescer {
    private let window: Duration
    private let run: () async -> Void
    private var task: Task<Void, Never>?

    /// Сколько ждать следующего уведомления. Четверть секунды: три события
    /// финиша приходят в пределах десятков миллисекунд, а человек, открывший
    /// «Атлас» сразу после, ждёт первый кадр не дольше, чем раньше.
    static let defaultWindow: Duration = .milliseconds(250)

    init(window: Duration = ReloadCoalescer.defaultWindow, run: @escaping () async -> Void) {
        self.window = window
        self.run = run
    }

    /// Пришло уведомление. Предыдущее ожидание отменяется — считаем от
    /// последнего, а не от первого: пачка обязана схлопнуться целиком.
    func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.window)
            guard !Task.isCancelled else { return }
            self.task = nil
            await self.run()
        }
    }

    /// Отменить отложенное — например, когда пересчёт уже пошёл другим путём.
    func cancel() {
        task?.cancel()
        task = nil
    }
}
