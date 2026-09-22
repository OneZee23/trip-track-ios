import Foundation

/// Выключатель Metal-тумана на «Атласе» (0.8.0).
///
/// `false` возвращает «Атласу» растровую вуаль 0.7.0 ЦЕЛИКОМ и без единой
/// правки: `MapHostController` не создаёт `FogMetalVeil`, `vectorOnly` у
/// экранной вуали остаётся снятым, и туман снова рисует растр — тот же путь,
/// которым «Атлас» жил до этой версии. Второго пути отката не заводится:
/// `FogMetalVeil.make()`, вернувший `nil` (Metal на устройстве недоступен),
/// приводит ровно туда же.
///
/// Это не флаг фичи и не заготовка настройки: выключить его — решение
/// владельца, а не побочный эффект задачи. Поэтому значение сторожит тест
/// (`FogMetalAvailabilityTests`), и менять их полагается вместе.
///
/// Тестовый шов `isEnabledOverride` — по образцу `RiddleHints`: `nil` значит
/// «как в проде», а тест, тронувший его, обязан вернуть `nil` в `tearDown`
/// (см. CLAUDE.md «Ловушки»: хвост, не обнулённый между тестами, роняет
/// чужой класс).
enum FogMetalAvailability {
    static let isEnabled = true

    static var isEnabledOverride: Bool?

    static var isActive: Bool { isEnabledOverride ?? isEnabled }
}
