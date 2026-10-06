import XCTest
@testable import TripTrack

/// Правила витрин оформления — состояния 21…27 матрицы 0.8.4.
///
/// Витрин четыре, правил пять, и пока каждое правило жило бы у своего экрана,
/// одна из четырёх однажды показала бы платное бесплатно — так расходились
/// единицы измерения до `Measure`. Поэтому таблица здесь, а не четыре открытых
/// экрана на телефоне.
final class ProShowcaseTests: XCTestCase {

    private func state(
        isPlus: Bool = false,
        hidden: Bool = false,
        tryingOn: Bool = false,
        ended: Bool = false,
        freeWeek: Bool = true
    ) -> ProShowcase.State {
        ProShowcase.State(isPlus: isPlus,
                          storefrontHidesPlus: hidden,
                          tryingOnPremium: tryingOn,
                          proHasEnded: ended,
                          freeWeekAvailable: freeWeek)
    }

    // MARK: - Кнопка внизу

    /// 21 — без подписки и ничего не примеряли: кнопка просто закрывает лист.
    /// Витрина НЕ выбрасывает на пейвол сама (принцип §1.4).
    func testNothingTriedOnMeansJustDone() {
        XCTAssertEqual(ProShowcase.action(state()), .done)
        XCTAssertFalse(ProShowcaseAction.done.opensPro)
    }

    /// 23 — примерил платное: кнопка предлагает купить, и только она ведёт
    /// на витрину PRO.
    func testTryingOnPremiumTurnsTheButtonIntoTheOffer() {
        XCTAssertEqual(ProShowcase.action(state(tryingOn: true)), .tryFreeWeek)
        XCTAssertTrue(ProShowcaseAction.tryFreeWeek.opensPro)
    }

    /// Недели не положено — обещать её нельзя, и кнопка называется иначе.
    /// Тот же рычаг, что на пейволе: Review 3.1.2.
    func testWithoutTheFreeWeekTheButtonDoesNotPromiseIt() {
        XCTAssertEqual(
            ProShowcase.action(state(tryingOn: true, freeWeek: false)), .getPro)
    }

    /// 22 — с подпиской кнопка всегда «Готово», что бы ни было выбрано.
    func testWithProTheButtonIsAlwaysDone() {
        XCTAssertEqual(ProShowcase.action(state(isPlus: true, tryingOn: true)), .done)
        XCTAssertEqual(
            ProShowcase.action(state(isPlus: true, tryingOn: true, ended: true)), .done)
    }

    /// 24 — подписка была и кончилась: предлагают ПРОДЛИТЬ, а не
    /// «попробовать неделю», которой такому человеку всё равно не дадут.
    func testAnEndedSubscriptionIsOfferedARenewalNotATrial() {
        XCTAssertEqual(ProShowcase.action(state(ended: true)), .done,
                       "бесплатный выбор можно завершить без покупки")
        XCTAssertEqual(
            ProShowcase.action(state(tryingOn: true, ended: true)), .renew,
            "примерка не отменяет того, что подписка была")
    }

    func testExpiredFreeSelectionCanFinishAfterPremiumTryOn() {
        XCTAssertEqual(ProShowcase.action(state(tryingOn: true, ended: true)), .renew)
        XCTAssertEqual(ProShowcase.action(state(tryingOn: false, ended: true)), .done)
    }

    func testRetainedChoiceNamesTheActualObjectAndVariantInEveryLanguage() {
        for language in LanguageManager.Language.allCases {
            for kind in ProShowcaseKind.allCases {
                let text = AppStrings.cosmeticRetainedChoice(language, kind: kind, name: "SavedVariant")
                XCTAssertTrue(text.contains(kind.title(language)), "\(language) \(kind)")
                XCTAssertTrue(text.contains("SavedVariant"))
                XCTAssertFalse(text.contains("{"))
            }
        }
    }

    /// Витрина не продаёт платное — кнопка закрывает лист и никуда не ведёт.
    func testAHiddenStorefrontLeavesOnlyDone() {
        XCTAssertEqual(ProShowcase.action(state(hidden: true, tryingOn: true)), .done)
        XCTAssertEqual(ProShowcase.action(state(hidden: true, ended: true)), .done)
    }

    // MARK: - Группа «PRO»

    /// Витрина, которая не продаёт платное, не показывает его НЕ «запертым», а
    /// не показывает ВОВСЕ — вместе с заголовком группы (принцип §1.5).
    func testAHiddenStorefrontDropsThePremiumGroupEntirely() {
        for kind in ProShowcaseKind.allCases {
            XCTAssertFalse(ProShowcase.showsPremiumGroup(kind, state(hidden: true)),
                           "\(kind)")
            XCTAssertTrue(ProShowcase.showsPremiumGroup(kind, state()), "\(kind)")
        }
    }

    /// Уже купленное платное работает и на витрине, которая больше не продаёт:
    /// человек мог купить на другой витрине или до смены региона. Это правило
    /// `PlusGate`, и витрина обязана ему подчиняться, а не решать сама.
    func testBoughtProSurvivesAStorefrontThatStoppedSelling() {
        for kind in ProShowcaseKind.allCases {
            XCTAssertTrue(
                ProShowcase.showsPremiumGroup(kind, state(isPlus: true, hidden: true)),
                "\(kind)")
        }
    }

    // MARK: - Замок

    func testOnlyPremiumTilesLockAndOnlyWithoutPro() {
        XCTAssertTrue(ProShowcase.isLocked(isPremium: true, state: state()))
        XCTAssertFalse(ProShowcase.isLocked(isPremium: false, state: state()))
        XCTAssertFalse(ProShowcase.isLocked(isPremium: true, state: state(isPlus: true)))
    }

    // MARK: - Карточка «PRO закончился»

    func testTheExpiredCardShowsOnlyWhenThereIsSomethingToRenew() {
        XCTAssertTrue(ProShowcase.showsExpiredCard(state(ended: true)))
        XCTAssertFalse(ProShowcase.showsExpiredCard(state()),
                       "подписки не было — карточке нечего сообщать")
        XCTAssertFalse(ProShowcase.showsExpiredCard(state(isPlus: true, ended: true)),
                       "подписка снова активна")
        XCTAssertFalse(ProShowcase.showsExpiredCard(state(hidden: true, ended: true)),
                       "продлевать негде — кнопка была бы мёртвой")
    }

    // MARK: - Сохранённый выбор и примерка

    private var previewCases: [(kind: ProShowcaseKind, premium: String,
                                anotherPremium: String, free: String)] {
        [
            (.profileBackground, ProfileBackground.plusNebula.rawValue,
             ProfileBackground.plusLava.rawValue, ProfileBackground.sunset.rawValue),
            (.avatarFrame, AvatarFrame.flame.rawValue,
             AvatarFrame.gold.rawValue, AvatarFrame.none.rawValue),
            (.vehicleCard, VehicleCardStyle.carbon.rawValue,
             VehicleCardStyle.racing.rawValue, VehicleCardStyle.none.rawValue),
            (.routeLine, RouteLineStyle.amber.rawValue,
             RouteLineStyle.violet.rawValue, RouteLineStyle.speed.rawValue)
        ]
    }

    /// Открытие витрины не является примеркой сохранённого платного выбора.
    /// Без подписки превью и выделение должны указывать на бесплатную плитку,
    /// даже если платные варианты доступны для отдельной примерки ниже.
    func testSavedPremiumWithoutEntitlementStartsAtVisibleFreeDefault() {
        for item in previewCases {
            for hidden in [false, true] {
                let shown = ProShowcase.previewID(
                    for: item.kind, current: item.premium, tried: nil,
                    isPlus: false, storefrontHidesPlus: hidden)
                XCTAssertEqual(shown, "", "\(item.kind), hidden=\(hidden)")
                XCTAssertTrue(ProShowcase.groups(for: item.kind).free.contains {
                    $0.id == shown
                }, "\(item.kind): выделение должно остаться в видимой сетке")
            }
        }
    }

    /// Один и тот же сохранённый ID снова виден после продления, в том числе
    /// в регионе, где новые подписки не продаются.
    func testSavedPremiumReturnsAfterEntitlementResumesInHiddenStorefront() {
        for item in previewCases {
            let before = ProShowcase.previewID(
                for: item.kind, current: item.premium, tried: nil,
                isPlus: true, storefrontHidesPlus: false)
            let during = ProShowcase.previewID(
                for: item.kind, current: item.premium, tried: nil,
                isPlus: false, storefrontHidesPlus: true)
            let renewed = ProShowcase.previewID(
                for: item.kind, current: item.premium, tried: nil,
                isPlus: true, storefrontHidesPlus: true)

            XCTAssertEqual(before, item.premium, "\(item.kind)")
            XCTAssertEqual(during, "", "\(item.kind)")
            XCTAssertEqual(renewed, item.premium, "\(item.kind)")
        }
    }

    /// Платное можно примерить без покупки там, где продаётся PRO. Смена
    /// региона при открытом листе должна убрать уже начатую примерку.
    func testExplicitPremiumPreviewDisappearsWhenStorefrontBecomesHidden() {
        for item in previewCases {
            let before = ProShowcase.previewID(
                for: item.kind, current: item.free, tried: item.premium,
                isPlus: false, storefrontHidesPlus: false)
            let after = ProShowcase.previewID(
                for: item.kind, current: item.free, tried: item.premium,
                isPlus: false, storefrontHidesPlus: true)

            XCTAssertEqual(before, item.premium, "\(item.kind)")
            XCTAssertEqual(after, item.free,
                           "\(item.kind): скрытая примерка не заменяет сохранённый бесплатный выбор")
        }
    }

    func testActiveProCanPreviewAnotherPremiumVariantInHiddenStorefront() {
        for item in previewCases {
            XCTAssertEqual(ProShowcase.previewID(
                for: item.kind, current: item.premium, tried: item.anotherPremium,
                isPlus: true, storefrontHidesPlus: true), item.anotherPremium,
                "\(item.kind): действующая подписка сильнее региона")
        }
    }

    func testFreeSelectionReplacesPremiumPreviewWithOrWithoutEntitlement() {
        for item in previewCases {
            for isPlus in [false, true] {
                XCTAssertEqual(ProShowcase.previewID(
                    for: item.kind, current: item.premium, tried: item.free,
                    isPlus: isPlus, storefrontHidesPlus: true), item.free,
                    "\(item.kind), isPlus=\(isPlus)")
            }
        }
    }

    /// Неизвестный ID (например, из будущей версии) не должен оставлять
    /// превью без соответствующей плитки или сохранять чужую примерку.
    func testUnknownSavedOrTriedVariantUsesTheDefaultTile() {
        for item in previewCases {
            XCTAssertEqual(ProShowcase.previewID(
                for: item.kind, current: "future_cosmetic", tried: nil,
                isPlus: true, storefrontHidesPlus: false), "", "\(item.kind)")
            XCTAssertEqual(ProShowcase.previewID(
                for: item.kind, current: item.premium, tried: "future_cosmetic",
                isPlus: true, storefrontHidesPlus: false), "", "\(item.kind)")
        }
    }

    // MARK: - Числа в заголовках групп

    /// Числа ВЫВОДЯТСЯ из перечислений вариантов, а не выписаны рядом с ними:
    /// два списка «сколько их» разошлись бы на первом добавленном фоне.
    func testCountsComeFromTheVariantsThemselves() {
        XCTAssertEqual(ProShowcaseKind.profileBackground.premiumCount,
                       ProfileBackground.allCases.filter(\.isPlus).count)
        XCTAssertEqual(ProShowcaseKind.profileBackground.freeCount,
                       ProfileBackground.allCases.filter { !$0.isPlus }.count)
        XCTAssertEqual(ProShowcaseKind.avatarFrame.premiumCount,
                       AvatarFrame.allCases.filter(\.isPlus).count)
        XCTAssertEqual(ProShowcaseKind.vehicleCard.premiumCount,
                       VehicleCardStyle.allCases.filter(\.isPlus).count)
        XCTAssertEqual(ProShowcaseKind.routeLine.premiumCount,
                       RouteLineStyle.allCases.filter(\.isPlus).count)
    }

    /// Числа макета. Не «проверка арифметики», а сторож на состав: макет
    /// подписан «PRO · 8» у фона и «PRO · 6» у рамки и линии, и человек,
    /// добавивший девятый фон, обязан увидеть падение и поправить макет.
    func testTheCountsMatchTheDesign() {
        XCTAssertEqual(ProShowcaseKind.profileBackground.premiumCount, 8)
        XCTAssertEqual(ProShowcaseKind.profileBackground.freeCount, 11)
        XCTAssertEqual(ProShowcaseKind.avatarFrame.premiumCount, 6)
        XCTAssertEqual(ProShowcaseKind.vehicleCard.premiumCount, 8)
        XCTAssertEqual(ProShowcaseKind.routeLine.premiumCount, 6)
    }

    // MARK: - Пара «витрина → фича»

    /// У каждой витрины своя фича, и ни одна не спрашивает гейт про чужую.
    func testEachShowcaseAsksTheGateAboutItself() {
        XCTAssertEqual(ProShowcaseKind.profileBackground.feature, .profileBackgrounds)
        XCTAssertEqual(ProShowcaseKind.avatarFrame.feature, .avatarFrame)
        XCTAssertEqual(ProShowcaseKind.vehicleCard.feature, .vehicleCardStyle)
        XCTAssertEqual(ProShowcaseKind.routeLine.feature, .routeLineStyle)
        XCTAssertEqual(Set(ProShowcaseKind.allCases.map(\.feature)).count,
                       ProShowcaseKind.allCases.count, "две витрины на одну фичу")
    }

    // MARK: - Заголовки

    func testTitlesAreTranslatedEverywhere() {
        for lang in LanguageManager.Language.allCases {
            for kind in ProShowcaseKind.allCases {
                XCTAssertFalse(kind.title(lang).isEmpty, "\(lang.rawValue) \(kind)")
            }
            for action in [ProShowcaseAction.done, .tryFreeWeek, .getPro, .renew] {
                XCTAssertFalse(action.title(lang).isEmpty, "\(lang.rawValue) \(action)")
            }
            XCTAssertFalse(
                AppStrings.showcaseExpiredTitle(lang, date: "12.09").contains("{"),
                lang.rawValue)
        }
    }

    // MARK: - Числа, вписанные в САМ ТЕКСТ

    /// «8 фонов и 6 рамок в PRO» — числа зашиты в копию на тринадцати языках,
    /// и токеном их не поймать (тот же случай, что «от 200 км» в
    /// `LocalizationTests`). Поэтому сторож сверяет их с источником истины —
    /// самими перечислениями вариантов: девятый фон обязан уронить этот тест,
    /// а не молча разойтись с текстом, который человек читает.
    ///
    /// Проверяется ru/en — те, что лежат инлайн в `AppStrings`. Остальные
    /// одиннадцать держит `LocalizationTests` на полноту, а числа в них
    /// правятся тем же движением, что и здесь.
    func testTheCountsInsideTheCopyMatchTheVariants() {
        let backgrounds = ProShowcaseKind.profileBackground.premiumCount
        let frames = ProShowcaseKind.avatarFrame.premiumCount
        let lines = ProShowcaseKind.routeLine.premiumCount

        for lang in [LanguageManager.Language.ru, .en] {
            let m1 = AppStrings.proCtxM1Text(lang)
            XCTAssertTrue(m1.contains("\(backgrounds)"),
                          "\(lang.rawValue): в «\(m1)» нет числа фонов \(backgrounds)")
            XCTAssertTrue(m1.contains("\(frames)"),
                          "\(lang.rawValue): в «\(m1)» нет числа рамок \(frames)")

            let m3 = AppStrings.proCtxM3Text(lang)
            XCTAssertTrue(m3.contains("\(lines)"),
                          "\(lang.rawValue): в «\(m3)» нет числа цветов \(lines)")

            let bg = AppStrings.proFeatureBgSub(lang)
            XCTAssertTrue(bg.contains("\(backgrounds)"), "\(lang.rawValue): «\(bg)»")
            let frame = AppStrings.proFeatureFrameSub(lang)
            XCTAssertTrue(frame.contains("\(frames)"), "\(lang.rawValue): «\(frame)»")
            let line = AppStrings.proFeatureLineSub(lang)
            XCTAssertTrue(line.contains("\(lines)"), "\(lang.rawValue): «\(line)»")
        }
    }

    // MARK: - Плитки

    /// Плиток столько же, сколько вариантов, и разбиты они ровно так, как
    /// считают заголовки групп. Два способа посчитать одно и то же — верный
    /// способ разойтись.
    func testTilesMatchTheCountsInTheGroupHeaders() {
        for kind in ProShowcaseKind.allCases {
            let groups = ProShowcase.groups(for: kind)
            XCTAssertEqual(groups.free.count, kind.freeCount, "\(kind)")
            XCTAssertEqual(groups.premium.count, kind.premiumCount, "\(kind)")
            XCTAssertEqual(ProShowcase.tiles(for: kind).count,
                           kind.freeCount + kind.premiumCount, "\(kind)")
        }
    }

    /// Бесплатные ВСЕГДА раньше платных: так рисует макет, и так человек
    /// видит сначала то, что у него уже есть.
    func testFreeTilesComeFirst() {
        for kind in ProShowcaseKind.allCases {
            let tiles = ProShowcase.tiles(for: kind)
            let firstPremium = tiles.firstIndex(where: \.isPremium) ?? tiles.count
            let lastFree = tiles.lastIndex(where: { !$0.isPremium }) ?? -1
            XCTAssertLessThan(lastFree, firstPremium,
                              "\(kind): платное вклинилось между бесплатными")
        }
    }

    /// Идентификатор плитки — это `rawValue`, то есть КЛЮЧ В БАЗЕ и на
    /// проводе. Пустой у «без варианта» законен ровно один раз на витрину:
    /// два пустых означали бы две неотличимые плитки.
    func testTileIdsAreTheStoredKeysAndAreUnique() {
        for kind in ProShowcaseKind.allCases {
            let ids = ProShowcase.tiles(for: kind).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(kind): две плитки с одним ключом")
            XCTAssertEqual(ids.filter(\.isEmpty).count, 1,
                           "\(kind): «без варианта» обязан быть ровно один")
        }
    }
}
