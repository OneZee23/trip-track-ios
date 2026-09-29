import Foundation

/// Чем машина едет: топливом, электричеством или и тем и другим.
///
/// Появился в 0.8.3 по письму пользователя из Германии: «Aktuell gibt die App ja
/// l für Kraftstoffverbrauch an. Ich fahre Plug-in-Hybrid» — приложение считало
/// расход только в литрах, а у него плагин-гибрид.
///
/// **Обычный гибрид (Prius) — это `fuel`.** Он жжёт только бензин, заряжается от
/// собственного двигателя, и литры описывают его полностью. Отдельный случай для
/// него был бы четвёртым вариантом, который ничего не меняет в арифметике, зато
/// заставляет человека выбирать между двумя словами, означающими одно.
///
/// **`rawValue` менять нельзя никогда** — это колонка `VehicleEntity.powertrain`,
/// поле `VehicleSyncPayload.powertrain` и колонка `vehicle.powertrain` на
/// сервере, то есть контракт со вторым телефоном.
///
/// **Умолчание — `fuel`, и оно единственно возможное.** Это ответ ВСЕХ машин,
/// заведённых до 0.8.3: у них нет ни киловатт-часов, ни запаса хода, и другое
/// умолчание молча переписало бы показания половине гаражей — та же логика, по
/// которой `DashboardUnits` умалчивает в `.app`.
enum Powertrain: String, Codable, CaseIterable {
    /// Двигатель внутреннего сгорания. Сюда же обычный гибрид.
    case fuel
    /// Только батарея.
    case electric
    /// Батарея и двигатель: первые километры дня с ночного заряда, дальше топливо.
    case pluginHybrid

    /// Разбор того, что приехало с сервера или со второго телефона.
    ///
    /// `nil` — «не сказано», а НЕ «топливо»: старый сервер поля не пришлёт
    /// вовсе, а будущая версия может прислать четвёртое слово, и подставить
    /// вместо него `fuel` значило бы стереть человеку электромобиль входящим
    /// пулом. Тот же приём, что у `DashboardUnits.parse`.
    static func parse(_ raw: String?) -> Powertrain? {
        guard let raw else { return nil }
        return Powertrain(rawValue: raw)
    }

    /// Есть ли у машины топливный блок: расход в городе и на трассе, цена литра.
    var usesFuel: Bool {
        switch self {
        case .fuel, .pluginHybrid: return true
        case .electric: return false
        }
    }

    /// Есть ли у машины электрический блок: кВт·ч на сотню и цена киловатт-часа.
    var usesElectricity: Bool {
        switch self {
        case .electric, .pluginHybrid: return true
        case .fuel: return false
        }
    }

    /// Имя варианта живёт У ТИПА, а не у экрана: его читают и строка формы, и
    /// лист выбора, и разъехаться этим двум написаниям нельзя (то же правило,
    /// что у `DashboardUnits.label`).
    func label(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .fuel:         return AppStrings.powertrainFuel(lang)
        case .electric:     return AppStrings.powertrainElectric(lang)
        case .pluginHybrid: return AppStrings.powertrainHybrid(lang)
        }
    }

    /// Пояснение под названием — «а это про меня?».
    ///
    /// Живёт у типа по той же причине, что и `label`: его читает лист выбора,
    /// а завтра прочтёт ещё кто-нибудь, и разъехаться двум написаниям нельзя.
    func hint(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .fuel:         return AppStrings.powertrainFuelHint(lang)
        case .electric:     return AppStrings.powertrainElectricHint(lang)
        case .pluginHybrid: return AppStrings.powertrainHybridHint(lang)
        }
    }

    /// Жетон в листе выбора — SF Symbol, а не две буквы: «То» и «Эл» на
    /// тринадцати языках это тринадцать пар сокращений, половина из которых
    /// совпадёт между собой.
    var symbol: String {
        switch self {
        case .fuel:         return "fuelpump.fill"
        case .electric:     return "bolt.fill"
        case .pluginHybrid: return "bolt.car.fill"
        }
    }

    /// Запас хода на батарее спрашивается только у гибрида.
    ///
    /// У электромобиля он не нужен для раскладки — там всё расстояние
    /// электрическое по определению, — а лишнее поле в форме это лишний вопрос.
    var needsElectricRange: Bool { self == .pluginHybrid }
}
