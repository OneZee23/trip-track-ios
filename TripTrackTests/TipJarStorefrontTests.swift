import XCTest
import StoreKit
import StoreKitTest
@testable import TripTrack

/// Живые Product берём из каталога приложения; задержки ответов задаём
/// явно, чтобы проверить смену витрины в середине запроса и покупки.
@MainActor
final class TipJarStorefrontTests: XCTestCase {
    private func catalog() async throws -> (SKTestSession, [Product]) {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TripTrack", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        session.resetToDefaultState()
        let products = try await Product.products(for: TipJarService.tipIDs)
        XCTAssertEqual(products.count, 3)
        let ordered = try TipJarService.tipIDs.map { id in
            try XCTUnwrap(products.first { $0.id == id }, "в тестовом каталоге нет \(id)")
        }
        return (session, ordered)
    }

    func testCountryChangeImmediatelyRemovesOldCatalogAndReloads() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        var response = [tips[0]]
        var requests = 0
        let jar = TipJarService(observeUpdates: false, fetchProducts: {
            requests += 1
            return response
        }, fetchStorefront: { "RUS" })
        await jar.load()
        XCTAssertEqual(jar.products.map(\.id), [tips[0].id])

        response = [tips[1]]
        let reload = jar.storefrontDidChange("DEU")
        XCTAssertTrue(jar.products.isEmpty, "старая цена исчезает до асинхронной загрузки")
        await reload?.value
        XCTAssertEqual(jar.products.map(\.id), [tips[1].id])
        XCTAssertEqual(jar.phase, .ready)
        XCTAssertEqual(jar.storefront, "DEU")
        XCTAssertNil(jar.storefrontDidChange("DEU"))
        XCTAssertNil(jar.storefrontDidChange(nil))
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(jar.storefront, "DEU", "молчание Apple сохраняет известную страну")
    }

    func testReopeningSheetRefreshesProductsEvenWhenCountryIsUnchanged() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        var requests = 0
        let jar = TipJarService(observeUpdates: false, fetchProducts: {
            requests += 1
            return [tips[requests == 1 ? 0 : 1]]
        }, fetchStorefront: { "DEU" })
        await jar.load()
        await jar.load()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(jar.products.map(\.id), [tips[1].id])
    }

    func testLateProductResponseCannotRestorePreviousCountryCatalog() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        let started = expectation(description: "old products pending")
        var oldResponse: CheckedContinuation<[Product], Error>?
        var requests = 0
        let jar = TipJarService(observeUpdates: false, fetchProducts: {
            requests += 1
            if requests == 1 {
                return try await withCheckedThrowingContinuation {
                    oldResponse = $0
                    started.fulfill()
                }
            }
            return [tips[1]]
        }, fetchStorefront: { "RUS" })
        let oldLoad = Task { await jar.load() }
        await fulfillment(of: [started], timeout: 2)
        await jar.storefrontDidChange("DEU")?.value
        XCTAssertFalse(oldLoad.isCancelled, "проверяем номер запроса, а не отмену")
        oldResponse?.resume(returning: [tips[0]])
        await oldLoad.value
        XCTAssertEqual(jar.products.map(\.id), [tips[1].id])
        XCTAssertEqual(jar.phase, .ready)
        XCTAssertEqual(jar.storefront, "DEU")
    }

    func testLateStorefrontLookupCannotUndoNewerStorefrontEvent() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        let started = expectation(description: "old storefront pending")
        var oldCountry: CheckedContinuation<String?, Never>?
        var requests = 0
        let jar = TipJarService(observeUpdates: false, fetchProducts: {
            requests += 1
            return tips
        }, fetchStorefront: {
            await withCheckedContinuation {
                oldCountry = $0
                started.fulfill()
            }
        })
        let oldLoad = Task { await jar.load() }
        await fulfillment(of: [started], timeout: 2)
        await jar.storefrontDidChange("DEU")?.value
        oldCountry?.resume(returning: "RUS")
        await oldLoad.value
        XCTAssertEqual(jar.storefront, "DEU")
        XCTAssertEqual(jar.products.count, 3)
        XCTAssertEqual(requests, 1, "устаревший Storefront.current не начинает ещё один запрос")
    }

    func testLateFailureDoesNotEraseNewCatalogOrItsReadyState() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        let started = expectation(description: "old products pending")
        var oldResponse: CheckedContinuation<[Product], Error>?
        var requests = 0
        let jar = TipJarService(observeUpdates: false, fetchProducts: {
            requests += 1
            if requests == 1 {
                return try await withCheckedThrowingContinuation {
                    oldResponse = $0
                    started.fulfill()
                }
            }
            return tips
        }, fetchStorefront: { "RUS" })
        let oldLoad = Task { await jar.load() }
        await fulfillment(of: [started], timeout: 2)
        await jar.storefrontDidChange("DEU")?.value
        oldResponse?.resume(throwing: URLError(.notConnectedToInternet))
        await oldLoad.value
        XCTAssertEqual(jar.products.count, 3)
        XCTAssertEqual(jar.phase, .ready)
    }

    func testUnavailableNewCatalogNeverKeepsPreviousCountryPrices() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        for throwsError in [false, true] {
            var requests = 0
            let jar = TipJarService(observeUpdates: false, fetchProducts: {
                requests += 1
                if requests == 1 { return tips }
                if throwsError { throw URLError(.notConnectedToInternet) }
                return []
            }, fetchStorefront: { "RUS" })
            await jar.load()
            XCTAssertEqual(jar.products.count, 3)
            await jar.storefrontDidChange("DEU")?.value
            XCTAssertTrue(jar.products.isEmpty)
            guard case .failed = jar.phase else {
                XCTFail("пустой каталог или ошибка должны оставить недоступную покупку")
                continue
            }
        }
    }

    func testCatalogRefreshKeepsPurchaseBusyAndPreservesItsResult() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        let purchaseStarted = expectation(description: "purchase pending")
        var purchaseResult: CheckedContinuation<Product.PurchaseResult, Error>?
        var purchases = 0
        let jar = TipJarService(observeUpdates: false, fetchProducts: { tips }, fetchStorefront: { "DEU" }, purchase: { _, _ in
            purchases += 1
            if purchases > 1 { return .userCancelled }
            return try await withCheckedThrowingContinuation {
                purchaseResult = $0
                purchaseStarted.fulfill()
            }
        })
        await jar.load()
        let buying = Task { await jar.buy(tips[0]) }
        await fulfillment(of: [purchaseStarted], timeout: 2)
        await jar.storefrontDidChange("USA")?.value
        XCTAssertEqual(jar.phase, .purchasing, "загрузка цены не разрешает вторую покупку")
        await jar.buy(tips[1])
        XCTAssertEqual(purchases, 1)
        XCTAssertEqual(jar.phase, .purchasing)
        purchaseResult?.resume(returning: .pending)
        await buying.value
        await jar.storefrontDidChange("DEU")?.value
        XCTAssertEqual(jar.phase, .deferred, "ожидающая подтверждения покупка не становится ready")
    }

    func testPurchaseResultSurvivesCatalogThatStartedBeforePurchase() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        let started = expectation(description: "products pending")
        var response: CheckedContinuation<[Product], Error>?
        let jar = TipJarService(observeUpdates: false, fetchProducts: {
            try await withCheckedThrowingContinuation {
                response = $0
                started.fulfill()
            }
        }, fetchStorefront: { "DEU" }, purchase: { _, _ in .userCancelled })
        let loading = Task { await jar.load() }
        await fulfillment(of: [started], timeout: 2)
        await jar.buy(tips[0])
        XCTAssertEqual(jar.phase, .cancelled)
        response?.resume(returning: tips)
        await loading.value
        XCTAssertEqual(jar.products.count, 3)
        XCTAssertEqual(jar.phase, .cancelled, "поздняя цена не перезаписывает результат покупки")
    }

    func testPurchaseResultSurvivesEarlierStorefrontLookup() async throws {
        let (session, tips) = try await catalog()
        defer { session.clearTransactions() }
        let started = expectation(description: "storefront pending")
        var country: CheckedContinuation<String?, Never>?
        let jar = TipJarService(observeUpdates: false, fetchProducts: { tips }, fetchStorefront: {
            await withCheckedContinuation {
                country = $0
                started.fulfill()
            }
        }, purchase: { _, _ in .userCancelled })
        let loading = Task { await jar.load() }
        await fulfillment(of: [started], timeout: 2)
        await jar.buy(tips[0])
        country?.resume(returning: "DEU")
        await loading.value
        XCTAssertEqual(jar.products.count, 3)
        XCTAssertEqual(jar.phase, .cancelled)
    }
}
