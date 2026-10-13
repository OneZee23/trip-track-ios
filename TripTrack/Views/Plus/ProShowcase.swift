import Foundation

/// Какая из четырёх витрин оформления открыта — состояния 21…27 матрицы 0.8.4.
enum ProShowcaseKind: String, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    case profileBackground
    case avatarFrame
    case vehicleCard
    case routeLine

    /// Какую фичу спрашивает у гейта. Пара «витрина → фича» живёт здесь, а не
    /// у каждого экрана: пятая витрина иначе спросила бы гейт не про себя.
    var feature: PlusFeature {
        switch self {
        case .profileBackground: return .profileBackgrounds
        case .avatarFrame:        return .avatarFrame
        case .vehicleCard:        return .vehicleCardStyle
        case .routeLine:          return .routeLineStyle
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .profileBackground: return AppStrings.showcaseBg(lang)
        case .avatarFrame:        return AppStrings.showcaseFrame(lang)
        case .vehicleCard:        return AppStrings.showcaseCar(lang)
        case .routeLine:          return AppStrings.showcaseLine(lang)
        }
    }

    /// Сколько бесплатных вариантов и сколько платных. Числа стоят в
    /// заголовках групп («Бесплатные · 11», «PRO · 8»), и ВЫВОДЯТСЯ из самих
    /// перечислений: выписанные рядом, они разошлись бы на первом добавленном
    /// фоне — ровно как разошлись бы два списка «что платное».
    var freeCount: Int { variants.free }
    var premiumCount: Int { variants.premium }

    private var variants: (free: Int, premium: Int) {
        switch self {
        case .profileBackground:
            return split(ProfileBackground.allCases.map(\.isPlus))
        case .avatarFrame:
            return split(AvatarFrame.allCases.map(\.isPlus))
        case .vehicleCard:
            return split(VehicleCardStyle.allCases.map(\.isPlus))
        case .routeLine:
            return split(RouteLineStyle.allCases.map(\.isPlus))
        }
    }

    private func split(_ flags: [Bool]) -> (free: Int, premium: Int) {
        (free: flags.filter { !$0 }.count, premium: flags.filter { $0 }.count)
    }
}

/// Что написано на кнопке внизу витрины.
///
/// Кнопка ОДНА, и она же — единственная дорога к покупке с этого экрана:
/// «Витрины не выбрасывают на пейвол» (принцип §1.4). Премиальный вариант
/// сначала ПРИМЕРЯЕТСЯ в превью, и только потом кнопка предлагает купить.
enum ProShowcaseAction: Equatable {
    /// «Готово» — закрыть лист.
    case done
    /// «Попробовать неделю бесплатно» — примерил платное, и неделя положена.
    case tryFreeWeek
    /// «Оформить PRO» — примерил платное, но недели не положено.
    case getPro
    /// «Продлить» — подписка была и кончилась.
    case renew

    func title(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .done:        return AppStrings.showcaseDone(lang)
        case .tryFreeWeek: return AppStrings.proCtaTrial(lang)
        case .getPro:      return AppStrings.showcaseGetPro(lang)
        case .renew:       return AppStrings.proCtxRenew(lang)
        }
    }

    /// Ведёт ли кнопка на витрину PRO. `false` — просто закрывает лист.
    var opensPro: Bool { self != .done }
}

/// Правила витрины оформления — чистыми функциями.
///
/// Чистыми, потому что правил здесь пять, а экранов четыре: пока каждое жило
/// бы у своего экрана, одна из четырёх витрин однажды показала бы платное
/// бесплатно — так расходились единицы измерения до `Measure`.
enum ProShowcase {

    /// Всё, от чего зависят ответы.
    struct State: Equatable {
        var isPlus: Bool
        /// Витрина устройства не продаёт платное (РФ).
        var storefrontHidesPlus: Bool
        /// Человек выбрал платный вариант, не имея подписки, — примерка
        /// (состояние 23).
        var tryingOnPremium: Bool
        /// Подписка БЫЛА и кончилась (состояние 24).
        var proHasEnded: Bool
        /// Даст ли Apple бесплатную неделю ЭТОМУ Apple ID.
        var freeWeekAvailable: Bool
    }

    /// Показывать ли группу «PRO» вовсе.
    ///
    /// Витрина, которая не продаёт платное, не показывает его НЕ «запертым», а
    /// не показывает вовсе — вместе с заголовком группы (принцип §1.5). Гейт
    /// спрашивается общий: свой `if` здесь был бы шестым местом, где живёт
    /// решение «РФ не видит платное».
    static func showsPremiumGroup(_ kind: ProShowcaseKind, _ state: State) -> Bool {
        PlusGate.allows(kind.feature,
                        isPlus: state.isPlus,
                        storefrontHidesPlus: state.storefrontHidesPlus) != .hidden
    }

    /// Сохранённый выбор показывается с текущими правами, как в профиле.
    /// Только явная примерка может показать платное без подписки, и только
    /// там, где витрина его предлагает. Исходный ID остаётся в настройках:
    /// открытие или закрытие листа не стирает выбор до продления PRO.
    static func previewID(
        for kind: ProShowcaseKind,
        current: String,
        tried: String?,
        isPlus: Bool,
        storefrontHidesPlus: Bool
    ) -> String {
        let offersPremium = PlusGate.allows(
            kind.feature, isPlus: isPlus,
            storefrontHidesPlus: storefrontHidesPlus) != .hidden
        let visibleTry = tried.flatMap { id -> String? in
            let premium = tiles(for: kind).first { $0.id == id }?.isPremium ?? false
            return premium && !offersPremium ? nil : id
        }
        let raw = visibleTry ?? current
        let showPremium = isPlus || (visibleTry != nil && offersPremium)
        switch kind {
        case .profileBackground:
            return ProfileBackground.effective(id: raw, isPlus: showPremium).rawValue
        case .avatarFrame:
            return AvatarFrame.effective(id: raw, isPlus: showPremium).rawValue
        case .vehicleCard:
            return VehicleCardStyle.effective(id: raw, isPlus: showPremium).rawValue
        case .routeLine:
            return RouteLineStyle.from(raw).effective(isPlus: showPremium).rawValue
        }
    }

    /// Замок на плитке. Только у платного варианта и только без подписки.
    static func isLocked(isPremium: Bool, state: State) -> Bool {
        isPremium && !state.isPlus
    }

    /// Карточка «PRO закончился …» над сеткой (состояние 24).
    ///
    /// На витрине, которая не продаёт платное, её нет: кнопка «Продлить» вела
    /// бы туда, где ничего не продаётся. Про откат оформления такой человек
    /// узнаёт извещением M4 (`ProContextOffer`), а не карточкой с мёртвой
    /// кнопкой.
    static func showsExpiredCard(_ state: State) -> Bool {
        state.proHasEnded && !state.isPlus && !state.storefrontHidesPlus
    }

    /// Что на кнопке внизу.
    ///
    /// Бесплатный выбор всегда можно завершить. Продление относится только
    /// к явной примерке платного, а не к самому факту истёкшей подписки.
    static func action(_ state: State) -> ProShowcaseAction {
        if state.isPlus { return .done }
        if state.storefrontHidesPlus { return .done }
        guard state.tryingOnPremium else { return .done }
        if state.proHasEnded { return .renew }
        return state.freeWeekAvailable ? .tryFreeWeek : .getPro
    }
}

// MARK: - Плитки

extension ProShowcase {
    /// Один вариант в сетке витрины.
    ///
    /// Значением, а не самим перечислением: четыре косметики — четыре РАЗНЫХ
    /// типа без общего протокола (`ProfileBackground`, `AvatarFrame`,
    /// `VehicleCardStyle`, `RouteLineStyle`), и заводить им протокол ради
    /// одной сетки значило бы тронуть четыре файла, которые работают. Сетка
    /// же спрашивает у варианта ровно три вещи: чем он назван в базе, платный
    /// ли он и как зовётся у человека.
    struct Tile: Identifiable, Equatable {
        /// `rawValue` — он же ключ в базе и на проводе.
        let id: String
        let isPremium: Bool
        /// Имя собственное («Nebula», «Gold»). Пусто у «без варианта» — у него
        /// нет имени, есть только отсутствие.
        let name: String
    }

    /// Все варианты витрины по порядку: сначала бесплатные, потом платные.
    ///
    /// Порядок ВЫВОДИТСЯ из `allCases`, а не выписывается: второй список
    /// разошёлся бы с первым на первом добавленном фоне — ровно так, как
    /// разошлись бы числа в заголовках групп.
    static func tiles(for kind: ProShowcaseKind) -> [Tile] {
        let all: [Tile]
        switch kind {
        case .profileBackground:
            all = ProfileBackground.allCases.map {
                Tile(id: $0.rawValue, isPremium: $0.isPlus, name: $0.displayName)
            }
        case .avatarFrame:
            all = AvatarFrame.allCases.map {
                Tile(id: $0.rawValue, isPremium: $0.isPlus, name: $0.displayName)
            }
        case .vehicleCard:
            all = VehicleCardStyle.allCases.map {
                Tile(id: $0.rawValue, isPremium: $0.isPlus, name: $0.displayName)
            }
        case .routeLine:
            all = RouteLineStyle.allCases.map {
                Tile(id: $0.rawValue, isPremium: $0.isPlus, name: $0.displayName)
            }
        }
        return all.filter { !$0.isPremium } + all.filter(\.isPremium)
    }

    /// Бесплатные и платные врозь — так их и рисует макет, двумя группами со
    /// своими заголовками и своими числами.
    static func groups(
        for kind: ProShowcaseKind
    ) -> (free: [Tile], premium: [Tile]) {
        let all = tiles(for: kind)
        return (free: all.filter { !$0.isPremium }, premium: all.filter(\.isPremium))
    }
}
