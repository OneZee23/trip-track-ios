import Foundation

/// Что нарисовать в превью страницы демонстрации.
///
/// Перечислением, а не булевыми полями: замена одного превью другим — это
/// РАЗВИЛКА («машины нет», «поездок нет»), и проверять её надо значением, а
/// не набором флагов, из которых половина сочетаний не существует.
enum ProDemoPreview: Equatable {
    /// Полоса профиля с его именем и аватаром на премиальном фоне.
    case profileStrip
    /// Аватар 80 в премиальной рамке на его фоне.
    case avatarRing
    /// Его карточка машины на премиальном фоне.
    case vehicleCard
    /// Машины в гараже нет — силуэт с подписью «появится здесь» (состояние 3).
    case vehicleSilhouette
    /// Его последний маршрут сплошным цветом.
    case route
    /// Поездок нет — НАРИСОВАННЫЙ пример (состояние 3).
    case exampleRoute
    /// Две точки и линия между ними — вписанная поездка.
    case manualPins
}

/// Одна страница демонстрации.
struct ProDemoPage: Equatable {
    let feature: PlusFeature
    /// Заголовок 20/600 — «8 фонов, которые видят все».
    let title: String
    /// Объяснение одним абзацем: что это, где видно, кому видно.
    let text: String
    let preview: ProDemoPreview

    /// Подписан ли пример примером. Обязательное свойство, а не косметика:
    /// показать нарисованный маршрут без подписи значит соврать человеку, что
    /// это его дорога.
    var previewIsLabelledAsExample: Bool {
        preview == .exampleRoute || preview == .vehicleSilhouette
    }
}

/// Копия и развилки страниц демонстрации — чистой функцией.
///
/// Копия взята из HTML-макетов владельца ДОСЛОВНО (`PR-02`, `PR-02b`,
/// `PR-02c`, `PR-03`). Двух страниц из пяти в макетах нет — рамки аватара и
/// карточки машины при наличии машины; их текст дописан в том же голосе, и это
/// отмечено в отчёте задачи, а не спрятано.
enum ProDemoContent {
    /// Порядок страниц — ТОТ ЖЕ, что порядок набора на витрине: сначала то,
    /// что видно другим, потом то, что только себе. Два порядка на один список
    /// однажды разошлись бы, поэтому здесь он выведен, а не выписан.
    static let order: [PlusFeature] =
        PlusFeature.allCases.filter(\.isVisibleToOthers)
        + PlusFeature.allCases.filter { !$0.isVisibleToOthers }

    /// Какое превью у функции — ОТДЕЛЬНО от копии.
    ///
    /// Отдельно, потому что спрашивают по-разному: странице нужны обе
    /// половины, а контекстному листу — только картинка. Собирать ради неё
    /// целую страницу значило бы печатать три строки перевода, чтобы
    /// выбросить их следующей строкой.
    static func preview(
        for feature: PlusFeature, hasVehicle: Bool, hasTrips: Bool
    ) -> ProDemoPreview {
        switch feature {
        case .profileBackgrounds: return .profileStrip
        case .avatarFrame:        return .avatarRing
        case .vehicleCardStyle:   return hasVehicle ? .vehicleCard : .vehicleSilhouette
        case .routeLineStyle:     return hasTrips ? .route : .exampleRoute
        case .manualTrip:         return .manualPins
        }
    }

    static func page(
        for feature: PlusFeature,
        hasVehicle: Bool,
        hasTrips: Bool,
        lang l: LanguageManager.Language
    ) -> ProDemoPage {
        let preview = preview(for: feature, hasVehicle: hasVehicle, hasTrips: hasTrips)
        switch feature {
        case .profileBackgrounds:
            return ProDemoPage(feature: feature,
                               title: AppStrings.proDemoBgTitle(l),
                               text: AppStrings.proDemoBgText(l),
                               preview: preview)
        case .avatarFrame:
            return ProDemoPage(feature: feature,
                               title: AppStrings.proDemoFrameTitle(l),
                               text: AppStrings.proDemoFrameText(l),
                               preview: preview)
        case .vehicleCardStyle:
            return ProDemoPage(feature: feature,
                               title: AppStrings.proDemoCarTitle(l),
                               text: hasVehicle
                                   ? AppStrings.proDemoCarText(l)
                                   : AppStrings.proDemoCarTextNoVehicle(l),
                               preview: preview)
        case .routeLineStyle:
            return ProDemoPage(feature: feature,
                               title: AppStrings.proDemoLineTitle(l),
                               text: hasTrips
                                   ? AppStrings.proDemoLineText(l)
                                   : AppStrings.proDemoLineTextNoTrips(l),
                               preview: preview)
        case .manualTrip:
            return ProDemoPage(feature: feature,
                               title: AppStrings.proDemoManualTitle(l),
                               text: AppStrings.proDemoManualText(l),
                               preview: preview)
        }
    }

    static func pages(
        hasVehicle: Bool, hasTrips: Bool, lang: LanguageManager.Language
    ) -> [ProDemoPage] {
        order.map { page(for: $0, hasVehicle: hasVehicle, hasTrips: hasTrips, lang: lang) }
    }
}
