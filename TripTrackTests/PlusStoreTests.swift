import XCTest
import StoreKit
import StoreKitTest
import UIKit
import Combine
@testable import TripTrack

/// «Плюс» на телефоне: что считается подпиской, что показывает витрина и что
/// происходит с покупкой.
///
/// Делится надвое нарочно. Половина — ЧИСТЫЕ правила (`resolve`, `summarize`,
/// `hidesPlus`, подпись строки в профиле): их можно перечислить таблицей, и
/// они не зависят ни от сети, ни от Apple. Вторая половина ходит в StoreKit
/// Testing и покупает по-настоящему — там проверяется не правило, а то, что
/// правило подключено к живым транзакциям.
@MainActor
final class PlusStoreTests: XCTestCase {

    // MARK: - Правила (без StoreKit)

    /// Таблица состояний. Читается как список решений, а не как тест:
    /// грейс побеждает всё, право без триала — активная подписка, отсутствие
    /// права при известном статусе — истечение, и только полная тишина —
    /// «никогда не покупал».
    func testStateTable() {
        typealias S = PlusStore.State
        XCTAssertEqual(PlusStore.resolve(entitled: true, isTrial: true, renewal: .subscribed), S.trial)
        XCTAssertEqual(PlusStore.resolve(entitled: true, isTrial: false, renewal: .subscribed), S.active)
        XCTAssertEqual(PlusStore.resolve(entitled: false, isTrial: false, renewal: .expired), S.expired)
        XCTAssertEqual(PlusStore.resolve(entitled: false, isTrial: false, renewal: .revoked), S.expired)
        XCTAssertEqual(PlusStore.resolve(entitled: false, isTrial: false, renewal: nil), S.none)
    }

    /// Платёж не прошёл — «Плюс» РАБОТАЕТ. Человек ничего не нарушил, у него
    /// протухла карта, и отбирать купленное на те дни, пока Apple пробует её
    /// ещё раз, нельзя. Поэтому грейс проверяется первым — даже когда
    /// `currentEntitlements` права уже не отдаёт.
    func testGracePeriodKeepsPlusAliveWithoutAnEntitlement() {
        XCTAssertEqual(
            PlusStore.resolve(entitled: false, isTrial: false, renewal: .inGracePeriod),
            PlusStore.State.grace)
        XCTAssertEqual(
            PlusStore.resolve(entitled: false, isTrial: false, renewal: .inBillingRetryPeriod),
            PlusStore.State.grace)
        XCTAssertTrue(PlusStore.grants(.grace))
        XCTAssertTrue(PlusStore.grants(.trial))
        XCTAssertTrue(PlusStore.grants(.active))
        XCTAssertFalse(PlusStore.grants(.expired))
        XCTAssertFalse(PlusStore.grants(.none))
    }

    /// Из нескольких строк группы (переехал с месячного на годовой) побеждает
    /// самая живая.
    func testTheLivestStatusOfTheGroupWins() {
        XCTAssertEqual(PlusStore.summarize([.expired, .inGracePeriod]), .inGracePeriod)
        XCTAssertEqual(PlusStore.summarize([.expired, .subscribed]), .subscribed)
        XCTAssertEqual(PlusStore.summarize([.expired, .revoked]), .revoked)
        XCTAssertEqual(PlusStore.summarize([.expired]), .expired)
        XCTAssertNil(PlusStore.summarize([]))
    }

    /// Витрина РФ платного не показывает вовсе — решение владельца 19 сентября.
    ///
    /// Кодов ДВА, и оба законны. `Storefront.countryCode` отвечает по
    /// ISO 3166-1 alpha-3 (`RUS`), а `Locale.region.identifier`, которым
    /// засевается ПЕРВЫЙ запуск (витрина ещё не ответила), — alpha-2 (`RU`).
    /// Пока сравнение шло только с трёхбуквенным, засев молчал, и первый
    /// холодный старт в РФ открывался со «платное видно».
    /// `available: true` — правило витрины само по себе; глобальный выключатель
    /// (`PlusAvailability`) держит отдельный `PlusAvailabilityTests`.
    func testBothSpellingsOfTheRussianStorefrontHidePaidThings() {
        XCTAssertTrue(PlusStore.hidesPlus(countryCode: "RUS", available: true))
        XCTAssertTrue(PlusStore.hidesPlus(countryCode: "RU", available: true), "так отвечает Locale.region")
        XCTAssertTrue(PlusStore.hidesPlus(countryCode: "ru", available: true))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: "GEO", available: true))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: "USA", available: true))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: nil, available: true))
    }

    /// Самая поздняя дата, а не последняя в перечислении: порядок
    /// `currentEntitlements` Apple не обещает, а строк в группе у человека,
    /// переехавшего с месячного на годовой, две.
    func testTheLatestExpiryWins() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(PlusStore.later(early, late), late)
        XCTAssertEqual(PlusStore.later(late, early), late)
        XCTAssertEqual(PlusStore.later(nil, late), late)
        XCTAssertEqual(PlusStore.later(early, nil), early)
        XCTAssertNil(PlusStore.later(nil, nil))
    }

    /// Уже купленный «Плюс» честно работает и на витрине, которая его больше
    /// не продаёт: человек мог купить на другой витрине или до переезда.
    func testABoughtPlusSurvivesAStorefrontThatStoppedSellingIt() {
        XCTAssertEqual(
            PlusGate.allows(.manualTrip, isPlus: true, storefrontHidesPlus: true),
            PlusAccessLevel.open)
        XCTAssertEqual(
            PlusGate.allows(.manualTrip, isPlus: false, storefrontHidesPlus: true),
            PlusAccessLevel.hidden)
    }

    // MARK: - Что экран говорит про покупку

    /// Три разных ответа StoreKit — три разных экрана, и молчит он ровно на
    /// одном. До ревью все три сводились к `false`, и пейвол не говорил
    /// ничего даже тому, у кого не прошла карта.
    func testEachPurchaseOutcomeGetsItsOwnLine() {
        XCTAssertEqual(PlusStore.message(for: .success), .none)
        XCTAssertEqual(PlusStore.message(for: .cancelled), .none,
                       "человек закрыл лист сам — комментировать нечего")
        XCTAssertEqual(PlusStore.message(for: .pending), .pending)
        XCTAssertEqual(
            PlusStore.message(for: .failed(URLError(.notConnectedToInternet))), .failed)
        XCTAssertEqual(
            PlusStore.message(for: .failed(PlusStore.PurchaseError.entitlementDidNotArrive)),
            .failed)
    }

    /// Текст ошибки StoreKit на экран не попадает ни на одном языке: он
    /// английский, системный и человеку не объясняет ничего.
    func testFailureCopyIsOursAndTranslatedEverywhere() {
        for lang in LanguageManager.Language.allCases {
            let failed = AppStrings.proFailed(lang)
            let pending = AppStrings.proDeferredText(lang)
            XCTAssertFalse(failed.isEmpty, lang.rawValue)
            XCTAssertFalse(pending.isEmpty, lang.rawValue)
            XCTAssertNotEqual(failed, pending, "\(lang.rawValue): два разных случая, один текст")
        }
    }

    // MARK: - Живой StoreKit

    /// Сессия поднимается на НАСТОЯЩЕМ `Config/TripTrack.storekit` — том же
    /// файле, по которому покупает схема. Разойдись они, тест проверял бы
    /// выдуманный каталог.
    private func makeSession() throws -> SKTestSession {
        let bundle = Bundle(for: PlusStoreTests.self)
        guard let url = bundle.url(forResource: "TripTrack", withExtension: "storekit") else {
            throw XCTSkip("Config/TripTrack.storekit не попал в тестовый бандл")
        }
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        session.resetToDefaultState()
        return session
    }

    /// Изолированный store не запускает глобальные слушатели, но витрина
    /// всё равно пишет общий гейт и память страны: возвращаем их после теста.
    private func savedStorefront() -> () -> Void {
        let remembered = UserDefaults.standard.string(forKey: PlusAccess.storefrontKey)
        let hidden = PlusAccess.shared.storefrontHidesPlus
        return {
            if let remembered {
                UserDefaults.standard.set(remembered, forKey: PlusAccess.storefrontKey)
            } else {
                UserDefaults.standard.removeObject(forKey: PlusAccess.storefrontKey)
            }
            PlusAccess.shared.storefrontHidesPlus = hidden
        }
    }

    /// Регрессия TestFlight: новая страна уже открыла PRO, а непустой
    /// каталог продолжал показывать цены от предыдущей витрины.
    func testStorefrontChangeInvalidatesPricesAndReloadsTheCatalog() async throws {
        let restore = savedStorefront()
        let session = try makeSession()
        defer { session.clearTransactions(); restore() }
        let plans = try await Product.products(for: PlusStore.productIDs)
        let yearly = try XCTUnwrap(plans.first { $0.id == PlusStore.yearlyID })
        let monthly = try XCTUnwrap(plans.first { $0.id == PlusStore.monthlyID })
        var result = [yearly]
        var requests = 0
        let store = PlusStore(fetchProducts: {
            requests += 1
            return result
        }, fetchIntroEligibility: { products in
            products.contains { $0.id == PlusStore.yearlyID }
        })

        await store.storefrontDidChange("RUS")?.value
        XCTAssertEqual(store.products.map(\.id), [PlusStore.yearlyID])
        XCTAssertTrue(store.introEligible)

        result = [monthly]
        let reload = store.storefrontDidChange("DEU")
        XCTAssertTrue(store.products.isEmpty, "цена прежней страны убирается сразу")
        XCTAssertFalse(store.introEligible, "право на триал тоже надо перечитать")
        XCTAssertFalse(PlusAccess.shared.storefrontHidesPlus)
        await reload?.value
        XCTAssertEqual(store.products.map(\.id), [PlusStore.monthlyID])
        XCTAssertFalse(store.introEligible)
        XCTAssertEqual(requests, 2)

        XCTAssertNil(store.storefrontDidChange("DEU"), "повтор события не перезагружает каталог")
        XCTAssertNil(store.storefrontDidChange(nil), "молчание Apple сохраняет известную страну")
        XCTAssertEqual(store.storefrontCountry, "DEU")
        XCTAssertEqual(store.products.map(\.id), [PlusStore.monthlyID])
        XCTAssertEqual(requests, 2)
    }

    /// Запрос, начатый пейволом/холодным стартом, не принадлежит задаче
    /// события витрины и не отменяется вместе с ней. Его поздний ответ всё
    /// равно не должен перезаписать новый каталог.
    func testLateProductResponseCannotReplaceTheNewStorefrontCatalog() async throws {
        let restore = savedStorefront()
        let session = try makeSession()
        defer { session.clearTransactions(); restore() }
        let plans = try await Product.products(for: PlusStore.productIDs)
        let yearly = try XCTUnwrap(plans.first { $0.id == PlusStore.yearlyID })
        let monthly = try XCTUnwrap(plans.first { $0.id == PlusStore.monthlyID })
        let started = expectation(description: "old catalog request started")
        var oldResponse: CheckedContinuation<[Product], Error>?
        var requests = 0
        let store = PlusStore(fetchProducts: {
            requests += 1
            if requests == 1 {
                return try await withCheckedThrowingContinuation {
                    oldResponse = $0
                    started.fulfill()
                }
            }
            return [monthly]
        }, fetchIntroEligibility: { _ in false })
        let oldLoad = Task { await store.loadProducts() }
        await fulfillment(of: [started], timeout: 2)

        await store.storefrontDidChange("DEU")?.value
        XCTAssertEqual(store.products.map(\.id), [PlusStore.monthlyID])
        XCTAssertFalse(oldLoad.isCancelled, "проверяем защиту номера запроса, а не отмену")
        oldResponse?.resume(returning: [yearly])
        await oldLoad.value
        XCTAssertEqual(store.products.map(\.id), [PlusStore.monthlyID])
    }

    /// Второе await внутри загрузки — проверка бесплатной недели. Ответ
    /// предыдущего аккаунта не может вернуть его продукты и обещание триала.
    func testLateIntroEligibilityCannotRestoreThePreviousCatalogOrTrial() async throws {
        let restore = savedStorefront()
        let session = try makeSession()
        defer { session.clearTransactions(); restore() }
        let plans = try await Product.products(for: PlusStore.productIDs)
        let yearly = try XCTUnwrap(plans.first { $0.id == PlusStore.yearlyID })
        let monthly = try XCTUnwrap(plans.first { $0.id == PlusStore.monthlyID })
        let started = expectation(description: "old eligibility request started")
        var oldEligibility: CheckedContinuation<Bool, Never>?
        var requests = 0
        let store = PlusStore(fetchProducts: {
            requests += 1
            return requests == 1 ? [yearly] : [monthly]
        }, fetchIntroEligibility: { products in
            guard products.contains(where: { $0.id == PlusStore.yearlyID }) else { return false }
            return await withCheckedContinuation {
                oldEligibility = $0
                started.fulfill()
            }
        })
        let oldLoad = Task { await store.loadProducts() }
        await fulfillment(of: [started], timeout: 2)

        await store.storefrontDidChange("DEU")?.value
        XCTAssertEqual(store.products.map(\.id), [PlusStore.monthlyID])
        XCTAssertFalse(store.introEligible)
        oldEligibility?.resume(returning: true)
        await oldLoad.value
        XCTAssertEqual(store.products.map(\.id), [PlusStore.monthlyID])
        XCTAssertFalse(store.introEligible)
    }

    func testFailedNewStorefrontRequestDoesNotBringBackOldPrices() async throws {
        let restore = savedStorefront()
        let session = try makeSession()
        defer { session.clearTransactions(); restore() }
        let plans = try await Product.products(for: PlusStore.productIDs)
        XCTAssertFalse(plans.isEmpty)
        var requests = 0
        let store = PlusStore(fetchProducts: {
            requests += 1
            if requests > 1 { throw URLError(.notConnectedToInternet) }
            return plans
        }, fetchIntroEligibility: { _ in true })
        await store.storefrontDidChange("RUS")?.value
        XCTAssertFalse(store.products.isEmpty)

        await store.storefrontDidChange("DEU")?.value
        XCTAssertTrue(store.products.isEmpty, "ошибка не возвращает цену старой страны")
        XCTAssertFalse(store.introEligible)
    }

    /// Каталог виден — иначе всё, что ниже, проверяло бы пустой список.
    func testTheStoreKitFileSellsExactlyTheTwoPlansAndThreeTips() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let plans = try await Product.products(for: PlusStore.productIDs)
        XCTAssertEqual(Set(plans.map(\.id)), Set(PlusStore.productIDs))
        // Триал есть у годового и только у него (спека §1).
        let yearly = try XCTUnwrap(plans.first { $0.id == PlusStore.yearlyID })
        let offer = try XCTUnwrap(yearly.subscription?.introductoryOffer)
        XCTAssertEqual(offer.paymentMode, .freeTrial)
        XCTAssertEqual(offer.period.unit, .week)
        XCTAssertEqual(offer.period.value, 1, "семь дней — одна неделя")
        let monthly = try XCTUnwrap(plans.first { $0.id == PlusStore.monthlyID })
        XCTAssertNil(monthly.subscription?.introductoryOffer)

        let tips = try await Product.products(for: TipJarService.tipIDs)
        XCTAssertEqual(Set(tips.map(\.id)), Set(TipJarService.tipIDs))
        XCTAssertTrue(tips.allSatisfy { $0.type == .consumable })
    }

    /// Покупка годового с первого раза — это ТРИАЛ, а не оплаченный период:
    /// вводное предложение применяется само, и «Плюс до» в профиле обязан
    /// считать его началом.
    func testBuyingTheYearlyStartsTheTrialAndOpensPlus() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        try await session.buyProduct(productIdentifier: PlusStore.yearlyID)
        await PlusStore.shared.refreshAll()

        XCTAssertEqual(PlusStore.shared.state, .trial)
        XCTAssertTrue(PlusStore.shared.isPlus)
        XCTAssertTrue(PlusAccess.shared.isPlus, "гейт обязан увидеть покупку")
        XCTAssertNotNil(PlusStore.shared.expiresAt)
    }

    /// Права на транзакцию больше нет — «Плюс» закрылся, и `PlusAccess`
    /// узнаёт об этом тем же обновлением.
    ///
    /// Истечение здесь НЕ разыгрывается `expireSubscription`: на iOS 18.6
    /// StoreKit Testing после него продолжает отдавать право в
    /// `currentEntitlements` того же процесса, то есть разыгрывает не то, что
    /// названо. Само правило «было и кончилось → `.expired`, а не `.none`»
    /// держит таблица `testStateTable` выше — она про решение, а не про
    /// поведение симулятора.
    func testLosingTheTransactionClosesPlus() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        // Сброс до покупки: ключ живёт в `UserDefaults`, а контейнер
        // симулятора переживает прогоны — без этого «дата запомнилась»
        // подтверждалось бы значением от соседнего теста.
        PlusStore.forgetLastKnownExpiryForTesting()

        try await session.buyProduct(productIdentifier: PlusStore.yearlyID)
        await PlusStore.shared.refreshAll()
        XCTAssertTrue(PlusStore.shared.isPlus)
        XCTAssertNotNil(PlusStore.shared.expiresAt, "Apple назвала дату, пока право живо")

        session.clearTransactions()
        await PlusStore.shared.refreshEntitlements()

        XCTAssertFalse(PlusStore.shared.isPlus)
        XCTAssertFalse(PlusAccess.shared.isPlus)

        // **Находка повторного ревью задачи 2.** Дата окончания обязана
        // ПЕРЕЖИТЬ потерю права: `currentEntitlements` при `.expired` её уже
        // не отдаёт, а строка «PRO закончился {date}» должна её показать.
        // Запоминается она, пока подписка работала, — этот переход и есть
        // ровно тот случай, и натурального истечения для него не нужно.
        XCTAssertNotNil(PlusStore.shared.lastKnownExpiry,
                        "дата не запомнилась, пока Apple её называла")
        XCTAssertEqual(PlusStore.shared.displayExpiry, PlusStore.shared.lastKnownExpiry,
                       "живой даты больше нет — показываем запомненную")
    }

    /// «Восстановить покупки» — то, что ревью Apple жмёт первой кнопкой.
    ///
    /// Сам `AppStore.sync()` подменён: в прогоне он ждёт диалога аккаунта и
    /// убивает процесс по таймауту (см. `PlusStore.syncWithAppStore`).
    /// Проверяется вторая половина — что восстановление перечитывает права,
    /// ничего не отнимает и отпускает кнопки.
    func testRestoreRereadsEntitlementsAndReleasesTheButtons() async throws {
        let session = try makeSession()
        let realSync = PlusStore.shared.syncWithAppStore
        defer {
            PlusStore.shared.syncWithAppStore = realSync
            session.clearTransactions()
        }
        PlusStore.shared.syncWithAppStore = {}

        try await session.buyProduct(productIdentifier: PlusStore.yearlyID)
        await PlusStore.shared.refreshAll()
        XCTAssertTrue(PlusStore.shared.isPlus)

        await PlusStore.shared.restore()

        XCTAssertTrue(PlusStore.shared.isPlus, "восстановление не имеет права ничего отнять")
        XCTAssertFalse(PlusStore.shared.isBusy)
    }

    /// Витрина РФ: платного на экране нет. Купленное при этом продолжает
    /// работать — здесь оно не куплено, поэтому гейт закрывает всё.
    func testTheRussianStorefrontHidesPaidThingsEndToEnd() async throws {
        let session = try makeSession()
        let remembered = UserDefaults.standard.string(forKey: PlusAccess.storefrontKey)
        defer {
            session.storefront = "GEO"
            session.clearTransactions()
            // Витрина теперь ЗАПОМИНАЕТСЯ (иначе каждый холодный старт в РФ
            // начинался бы со «платное видно»), и оставить «RUS» за собой
            // значило бы отдать её следующему прогону.
            if let remembered {
                UserDefaults.standard.set(remembered, forKey: PlusAccess.storefrontKey)
            } else {
                UserDefaults.standard.removeObject(forKey: PlusAccess.storefrontKey)
            }
            PlusAccess.shared.storefrontHidesPlus = PlusStore.hidesPlus(countryCode: remembered)
        }

        session.storefront = "RUS"
        await PlusStore.shared.refreshAll()

        XCTAssertEqual(PlusStore.shared.storefrontCountry, "RUS")
        XCTAssertTrue(PlusAccess.shared.storefrontHidesPlus)
        XCTAssertEqual(UserDefaults.standard.string(forKey: PlusAccess.storefrontKey), "RUS",
                       "витрина обязана пережить холодный старт")
        for feature in PlusFeature.allCases {
            XCTAssertEqual(
                PlusGate.allows(feature,
                                isPlus: PlusAccess.shared.isPlus,
                                storefrontHidesPlus: PlusAccess.shared.storefrontHidesPlus),
                PlusAccessLevel.hidden,
                "\(feature) на витрине РФ обязана пропасть целиком")
        }
    }

    // MARK: - Истечение замечается, пока приложение живо

    /// **Находка аудита H1.** Истечение подписки не создаёт транзакции: Apple
    /// молчит, `Transaction.updates` молчит, и пересчитать состояние физически
    /// некому. А процесс TripTrack живёт сутками на фоновой геолокации —
    /// то есть «Плюс» оставался открытым сколь угодно долго после конца
    /// оплаченного периода.
    ///
    /// Разыгрывается ровно та дверь, которую чинили: уведомление системы о
    /// возвращении в приложение. Симметрия важна и в обратную сторону —
    /// подписка, купленная на втором телефоне, подхватывается тем же путём.
    func testComingBackToTheAppRereadsTheEntitlements() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        PlusStore.shared.start()

        try await session.buyProduct(productIdentifier: PlusStore.yearlyID)
        await PlusStore.shared.refreshAll()
        XCTAssertTrue(PlusAccess.shared.isPlus)

        let lostAccess = expectation(description: "foreground refresh closes expired access")
        let observation = PlusAccess.shared.$isPlus
            .filter { !$0 }
            .prefix(1)
            .sink { _ in lostAccess.fulfill() }
        defer { observation.cancel() }

        session.clearTransactions()                  // подписка кончилась
        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification, object: nil)

        // Кроме двух секунд debounce, живой StoreKit Testing на iOS 18.6
        // иногда тратит 5–10 секунд на currentEntitlements/status. Ждём сам
        // переход, чтобы незавершённое чтение не утекало в следующий тест.
        await fulfillment(of: [lostAccess], timeout: 15)
        XCTAssertFalse(PlusAccess.shared.isPlus,
                       "возвращение в приложение обязано пересчитать права")
    }

    /// Одно возвращение в приложение — ОДНО обновление прав.
    ///
    /// `didBecomeActive` приходит не только после фона: его шлёт и снятый
    /// системный лист (Апл-ай-ди, шторка, звонок). Пока слушались ОБА
    /// уведомления перехода, на каждый возврат уходило по два запроса к
    /// StoreKit; теперь слушается одно, а подряд идущие схлопывает
    /// `foregroundDebounce`.
    func testTwoForegroundNotificationsInARowCauseOneRefresh() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        PlusStore.shared.start()

        let before = PlusStore.shared.entitlementRefreshes
        PlusStore.shared.scheduleForegroundRefresh()
        PlusStore.shared.scheduleForegroundRefresh()
        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification, object: nil)

        try? await Task.sleep(
            nanoseconds: UInt64((PlusStore.foregroundDebounce + 1.5) * 1_000_000_000))
        XCTAssertEqual(PlusStore.shared.entitlementRefreshes - before, 1,
                       "три повода подряд — одно обновление")
    }

    /// Право на вводное предложение спрашивается у Apple. Здесь оно ещё не
    /// израсходовано, поэтому ответ положительный; отрицательную половину
    /// правила держит `PlusPaywallModelTests` чистой функцией (разыграть
    /// «триал уже съеден» в том же процессе StoreKit Testing нечем —
    /// `isEligibleForIntroOffer` кэшируется на группу).
    func testIntroEligibilityIsAskedOfStoreKitNotGuessedFromTheProduct() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        await PlusStore.shared.loadProducts()
        XCTAssertTrue(PlusStore.shared.introEligible)
    }
}
