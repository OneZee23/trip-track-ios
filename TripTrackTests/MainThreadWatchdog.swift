import Foundation

/// Меряет отклик главного потока СНАРУЖИ — тот же приём, что предложен для
/// живого сторожа в бриф-задаче H: фоновая очередь раз в `intervalMs` шлёт
/// `DispatchQueue.main.async` и ждёт семафор, а разрыв между отправкой и
/// исполнением и есть время, на которое главный поток был занят чем-то ещё
/// (синхронной работой) и не мог принять новую задачу. Если главный поток
/// заблокирован синхронным циклом на N миллисекунд, ОДИН такой разрыв будет
/// не меньше N — в отличие от простого `Date()`-до/после вокруг вызова, это
/// отличает «два потока работали параллельно 500 мс» от «главный стоял
/// 500 мс, пока фон считал».
final class MainThreadWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var _maxGapMs: Double = 0
    private var running = false
    /// Замер окончен — новые пробы больше не учитываются. См. `stop()`.
    private var frozen = false
    private let intervalMs: Double

    init(intervalMs: Double = 15) {
        self.intervalMs = intervalMs
    }

    /// Максимальный разрыв. ПОСЛЕ `stop()` не меняется — читать можно сколько
    /// угодно раз и получать одно и то же.
    var maxGapMs: Double {
        lock.lock(); defer { lock.unlock() }
        return _maxGapMs
    }

    func start() {
        lock.lock(); running = true; lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            while true {
                self.lock.lock()
                let stillRunning = self.running
                self.lock.unlock()
                guard stillRunning else { return }

                let sem = DispatchSemaphore(value: 0)
                let sentAt = DispatchTime.now()
                DispatchQueue.main.async { sem.signal() }
                sem.wait()
                let gapMs = Double(DispatchTime.now().uptimeNanoseconds - sentAt.uptimeNanoseconds) / 1_000_000

                self.lock.lock()
                // Пробу, начатую до `stop()`, а доехавшую после, НЕ учитываем:
                // её разрыв наполовину про то, что главный поток делал уже
                // после замера (разбор теста, следующий тест), и приписать его
                // измеряемой работе нельзя. Отбрасывается ровно одна —
                // пограничная; настоящий простой в N миллисекунд ловят пробы
                // целиком внутри окна, они идут каждые 15 мс.
                if !self.frozen {
                    self._maxGapMs = max(self._maxGapMs, gapMs)
                }
                self.lock.unlock()

                Thread.sleep(forTimeInterval: self.intervalMs / 1000)
            }
        }
    }

    /// Остановить замер и ЗАМОРОЗИТЬ результат, вернув его.
    ///
    /// Возвращает нарочно: до этого тесты читали `maxGapMs` дважды — один раз
    /// в печать, второй в проверку, — а между двумя чтениями доезжала
    /// пограничная проба и меняла число. Выглядело это как «в печати 0 мс, в
    /// упавшей проверке 219», то есть как невозможный отчёт, по которому не
    /// понять, был простой или нет. Берёшь число у `stop()` один раз —
    /// печать и проверка говорят об одном.
    @discardableResult
    func stop() -> Double {
        lock.lock(); defer { lock.unlock() }
        running = false
        frozen = true
        return _maxGapMs
    }
}
