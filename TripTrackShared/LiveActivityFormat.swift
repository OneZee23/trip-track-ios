import Foundation

/// Расстояние и скорость для локскрина, часов и Dynamic Island — то есть по ту
/// сторону границы процесса, где `Measure` не существует.
///
/// **Вход всегда метрический** (`km`, `kmh`), потому что метрический сам
/// провод: `ContentState.speedKmh` и `.distanceKm` продолжают везти километры,
/// а переименовать их нельзя — активность, начатая старым бинарником и
/// пережившая обновление, перестала бы декодироваться. Перевод случается
/// здесь, у самого показа, ровно как в приложении.
///
/// Живёт отдельным типом, а не приватной функцией в файле виджета, по одной
/// причине: приватную функцию виджета не может позвать тест. Таргет расширения
/// в тестовую схему не входит, а свойство, которое надо держать, — это
/// «локскрин и приложение печатают ОДНО И ТО ЖЕ». Проверить его можно только
/// там, где видны обе стороны, то есть из тестов приложения, куда
/// `TripTrackShared` компилируется тоже.
enum LiveActivityFormat {

    /// Число и подпись, собранные вместе — как `Measure.Parts` по ту сторону.
    struct Parts {
        let value: String
        let unit: String
    }

    /// «12.4» + «км» / «7.7» + «mi».
    ///
    /// Точность — `DistanceUnit.showsTenths`, то же правило, что у
    /// `Measure.Style.adaptive`: десятые ниже порога, дальше целое с
    /// разрядами. Порог в ЕДИНИЦАХ ПОКАЗА (10 км, 6 миль), поэтому меняется он
    /// на одном и том же физическом расстоянии, а не на числе, которое
    /// случайно читается как «десять».
    ///
    /// И ровно как у `adaptive`, ХВОСТА «.0» не бывает: «5.0» на локскрине —
    /// тот же след форматтера, что и в приложении. Копия правила здесь не по
    /// лени, а потому что `Measure` в таргет виджета не приезжает; что обе
    /// копии отвечают побайтово одинаково, держит `LiveActivityUnitTests`.
    static func distanceParts(km: Double, unit: DistanceUnit, code: String) -> Parts {
        let raw = unit.distance(fromMetres: km * 1000)
        let value = raw.isFinite ? raw : 0
        let rounded = (value * 10).rounded() / 10
        if unit.showsTenths(value), rounded != rounded.rounded() {
            return Parts(
                value: UnitNumber.tenths(value, code: code),
                unit: LiveActivityStrings.distanceShort(
                    code, unit: unit, value: rounded, fractionDigits: 1)
            )
        }
        let clamped = min(max(value.rounded(), -1e15), 1e15)
        return Parts(
            value: UnitNumber.grouped(Int(clamped), code: code),
            unit: LiveActivityStrings.distanceShort(
                code, unit: unit, value: clamped, fractionDigits: 0)
        )
    }

    /// «68» + «км/ч» / «42» + «mph».
    ///
    /// Округление, а не отбрасывание дробной части: `Int(67.9)` печатал «67»,
    /// и ровно на столько локскрин расходился со спидометром в приложении.
    static func speedParts(kmh: Double, unit: DistanceUnit, code: String) -> Parts {
        let raw = unit.speed(fromMetresPerSecond: kmh / 3.6)
        let value = raw.isFinite ? raw : 0
        let clamped = min(max(value.rounded(), -1e15), 1e15)
        return Parts(
            value: UnitNumber.grouped(Int(clamped), code: code),
            unit: LiveActivityStrings.speedShort(code, unit: unit)
        )
    }
}
