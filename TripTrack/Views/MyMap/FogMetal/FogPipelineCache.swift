import Metal

/// Шейдеры тумана компилируются ОДИН раз и вне главного потока.
///
/// `FogFrameEncoder.init` собирает два пайплайна, и на холодном кэше шейдеров
/// (первый запуск после обновления или после перезагрузки телефона) это
/// компиляция, а не чтение: Sentry APPLE-IOS-11, 0.9.1 (95), главный поток
/// стоял больше двух секунд в `newRenderPipelineState` при открытии «Атласа».
/// Поэтому прогрев стартует на запуске приложения, в фоне, и кладёт готовый
/// кодировщик сюда; экран и постер берут его, а не собирают свой.
///
/// Не успел прогреться — `encoder(device:)` собирает сам, как раньше: стоит
/// это не больше прежнего, а кэш шейдеров к тому моменту уже тёплый.
enum FogPipelineCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (device: MTLDevice, encoder: FogFrameEncoder)?
    nonisolated(unsafe) private static var warming = false

    /// Запускается из `AppBootstrap`, один раз. Без Metal или с выключенным
    /// Metal-туманом не делает ничего.
    static func prewarm() {
        guard FogMetalAvailability.isActive else { return }
        let start = lock.withLock { () -> Bool in
            guard cached == nil, !warming else { return false }
            warming = true
            return true
        }
        guard start else { return }
        DispatchQueue.global(qos: .utility).async {
            let device = MTLCreateSystemDefaultDevice()
            let encoder = device.flatMap { FogFrameEncoder(device: $0) }
            lock.withLock {
                warming = false
                if let device, let encoder, cached == nil { cached = (device, encoder) }
            }
        }
    }

    /// Готовый кодировщик для этого устройства, иначе собранный на месте.
    static func encoder(device: MTLDevice) -> FogFrameEncoder? {
        if let hit = lock.withLock({ cached }), hit.device === device { return hit.encoder }
        guard let built = FogFrameEncoder(device: device) else { return nil }
        // Прогрев мог закончить, пока собирали здесь: побеждает первый,
        // второй экземпляр выбрасывается, чтобы кодировщик был один.
        return lock.withLock {
            if let hit = cached, hit.device === device { return hit.encoder }
            cached = (device, built)
            return built
        }
    }

    /// Тестовый шов: забыть прогретое.
    static func resetForTesting() {
        lock.withLock { cached = nil; warming = false }
    }
}
