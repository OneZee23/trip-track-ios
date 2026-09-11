import Foundation

/// Число, зашитое в описание значка, — и единственный способ его напечатать.
///
/// **Порог остаётся метрическим навсегда, меняется только запись.** «Марафон»
/// — это 42.195 км у всех, в любой стране и при любой настройке; американец
/// читает тот же порог как «26.2 mi» — число, которое он знает лучше, чем
/// сорок два. Экватор остаётся экватором: «24 901 mi — длина экватора» так же
/// верно, как «40 075 км». Правила игры одинаковы для всех, потому что значок
/// лежит в базе разблокированным, и подвинутый порог сдвинул бы достижения у
/// всех задним числом — ровно та поломка, которую не чинит следующий релиз.
///
/// Поэтому здесь хранятся МЕТРИЧЕСКИЕ величины (км, км/ч, м), те же самые, что
/// стоят в `checkUnlocked` рядом, — а перевод случается на показе, в
/// `Measure`, как и везде в 0.6.7.
struct BadgeFigure {

    enum Kind {
        /// Километры — `BadgeStats.totalDistanceKm`, `longestTripKm`.
        case distance
        /// Километры в час — `BadgeStats.maxSpeedKmh`.
        case speed
        /// Метры набора или высоты — `maxElevationGainSingleTrip`, `maxAltitude`.
        case elevation
    }

    let kind: Kind
    /// Значение В ЕДИНИЦАХ ХРАНЕНИЯ: км, км/ч, метры. Не то, что увидят.
    let value: Double
    /// «500+ км», «2 000+ м» — порог «не меньше».
    ///
    /// Плюс живёт ЗДЕСЬ, а не в тексте перевода, потому что стоит он между
    /// числом и подписью: в тексте «500+ км» его не отделить от числа, не
    /// разорвав строку на два куска. Одиннадцать таблиц с плюсом внутри
    /// шаблона дали бы одиннадцать шансов поставить его не туда.
    let atLeast: Bool
    /// Как округлять. У всех целое с разрядами, кроме марафона: 42.195 км —
    /// единственный порог, у которого десятая доля и есть весь смысл.
    let style: Measure.Style

    static func distance(
        _ km: Double, atLeast: Bool = false, style: Measure.Style = .grouped
    ) -> BadgeFigure {
        BadgeFigure(kind: .distance, value: km, atLeast: atLeast, style: style)
    }

    static func speed(_ kmh: Double) -> BadgeFigure {
        BadgeFigure(kind: .speed, value: kmh, atLeast: false, style: .grouped)
    }

    static func elevation(_ metres: Double, atLeast: Bool = false) -> BadgeFigure {
        BadgeFigure(kind: .elevation, value: metres, atLeast: atLeast, style: .grouped)
    }

    /// Что подставить в шаблон описания — число вместе с подписью.
    func shown(unit: DistanceUnit, lang: LanguageManager.Language) -> String {
        let parts: Measure.Parts
        switch kind {
        case .distance:
            parts = Measure.distanceParts(km: value, unit: unit, lang: lang, style: style)
        case .speed:
            parts = Measure.speedParts(
                ms: DistanceUnit.km.metresPerSecond(fromSpeed: value), unit: unit, lang: lang)
        case .elevation:
            parts = Measure.elevationParts(metres: value, unit: unit, lang: lang)
        }
        return atLeast ? "\(parts.value)+ \(parts.unit)" : "\(parts.value) \(parts.unit)"
    }
}
