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
    private let intervalMs: Double

    init(intervalMs: Double = 15) {
        self.intervalMs = intervalMs
    }

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
                self._maxGapMs = max(self._maxGapMs, gapMs)
                self.lock.unlock()

                Thread.sleep(forTimeInterval: self.intervalMs / 1000)
            }
        }
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
    }
}
