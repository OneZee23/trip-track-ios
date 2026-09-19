import XCTest
import StoreKit
import StoreKitTest
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
    /// Код трёхбуквенный: `Storefront.countryCode` отвечает по ISO 3166-1
    /// alpha-3, и «RU» здесь не сработало бы никогда.
    func testOnlyTheRussianStorefrontHidesPaidThings() {
        XCTAssertTrue(PlusStore.hidesPlus(countryCode: "RUS"))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: "RU"))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: "GEO"))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: "USA"))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: nil))
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

        try await session.buyProduct(productIdentifier: PlusStore.yearlyID)
        await PlusStore.shared.refreshAll()
        XCTAssertTrue(PlusStore.shared.isPlus)

        session.clearTransactions()
        await PlusStore.shared.refreshEntitlements()

        XCTAssertFalse(PlusStore.shared.isPlus)
        XCTAssertFalse(PlusAccess.shared.isPlus)
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
        defer {
            session.storefront = "GEO"
            session.clearTransactions()
        }

        session.storefront = "RUS"
        await PlusStore.shared.refreshAll()

        XCTAssertEqual(PlusStore.shared.storefrontCountry, "RUS")
        XCTAssertTrue(PlusAccess.shared.storefrontHidesPlus)
        for feature in PlusFeature.allCases {
            XCTAssertEqual(
                PlusGate.allows(feature,
                                isPlus: PlusAccess.shared.isPlus,
                                storefrontHidesPlus: PlusAccess.shared.storefrontHidesPlus),
                PlusAccessLevel.hidden,
                "\(feature) на витрине РФ обязана пропасть целиком")
        }
    }
}
