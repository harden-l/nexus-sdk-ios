import Foundation
import XCTest
import NexusCoreUser
@testable import NexusPayment

final class NexusPaymentTests: XCTestCase {
    func testExactAmountsScaleOnce() {
        XCTAssertEqual(CoinAmountFormatter.displayText(Decimal(string: "0.123456789123456789")!), "12.3456789123456789")
        XCTAssertEqual(CoinAmountFormatter.displayUnitText(Decimal(string: "2025.5")!), "2025.5")
    }

    func testTemplatesAndRelatedAppCopy() throws {
        let config = try SubscriptionPageConfig()
        XCTAssertEqual(Set(SubscriptionPageTemplateId.allCases.map(\.rawValue)), ["aurora", "midnight", "minimal"])
        XCTAssertEqual(config.sharedApps.title, "Related apps")
        XCTAssertFalse(config.benefitDescription.contains("all other products"))
        XCTAssertTrue(config.sharedApps.description.contains("specific to each app"))
        XCTAssertThrowsError(try SubscriptionPageConfig(showTerms: true, termsUrl: ""))
        XCTAssertThrowsError(try SubscriptionPageConfig(showPrivacy: true, privacyUrl: ""))
    }

    func testPaymentConfigValidatesChannels() throws {
        XCTAssertThrowsError(try PaymentConfig(productId: "test", enabledChannels: [.appStore, .appStore]))
        XCTAssertThrowsError(try PaymentConfig(productId: "test", fallbackChannels: [.stripe]))
    }

    func testPaymentRuleMatchesVersionAndCase() throws {
        let sdk = NexusPayment.shared
        let rule = try PaymentRule(country: "us", platform: "IOS", minVersion: "2.1.0",
                                   enabledChannels: [.mock], defaultChannel: .mock)
        sdk.initialize(config: try PaymentConfig(productId: "test", rules: [rule]))
        XCTAssertEqual(try sdk.resolvePaymentChannel(context: PaymentContext(country: "US", appVersion: "2.0.9")).defaultChannel, .appStore)
        XCTAssertEqual(try sdk.resolvePaymentChannel(context: PaymentContext(country: "US", appVersion: "2.1")).defaultChannel, .mock)
    }

    func testProductParserKeepsExactDecimalsStableSortAndReferenceCents() throws {
        let products = try ProductParser.parse(#"{"list":[{"market_product_id":"last","product_type":1,"sort":3,"coins_granted":0},{"market_product_id":"first","product_type":2,"sort":1,"coins_granted":1.123456789123456789,"weekly_points_enabled":1,"weekly_points":0.125,"price_usd":199,"price":"99","localized_price":"legacy"},{"market_product_id":"tie","product_type":1,"sort":1,"coins_granted":0.01}]}"#)
        XCTAssertEqual(products.map(\.marketProductId), ["first", "tie", "last"])
        XCTAssertEqual(products[0].coinsGrantedDecimal, Decimal(string: "1.123456789123456789"))
        XCTAssertEqual(products[0].weeklyPointsDecimal, Decimal(string: "0.125"))
        XCTAssertEqual(products[0].weeklyPoints, 0)
        XCTAssertEqual(products[0].priceUsd, 199)
        XCTAssertNil(products[0].price)
        XCTAssertNil(products[0].localizedPrice)
        XCTAssertFalse(products[0].storeDetailsAvailable)
        XCTAssertEqual(products[1].productType, .consumable)
        XCTAssertEqual(products[2].productType, .iap)
    }

    func testProductParserRejectsLegacyEnvelopeAndMalformedData() {
        XCTAssertThrowsError(try ProductParser.parse(#"{"code":1,"data":{"list":[]}}"#))
        XCTAssertThrowsError(try ProductParser.parse(#"{"list":[{"market_product_id":"bad","weekly_points":"not a number"}]}"#))
        XCTAssertThrowsError(try ProductParser.parse("{}"))
    }

    func testProductCodableMigratesLegacyCacheAndPreservesExactAmounts() throws {
        let legacy = Data(#"{"marketProductId":"sub","name":"Sub","productType":"subscription","coinsGranted":0.125,"weeklyPoints":30}"#.utf8)
        let product = try JSONDecoder().decode(Product.self, from: legacy)
        XCTAssertEqual(product.coinsGrantedDecimal, Decimal(string: "0.125"))
        XCTAssertEqual(product.weeklyPointsDecimal, 30)
        XCTAssertFalse(product.storeDetailsAvailable)
        let exact = Product(marketProductId: "sub", name: "Sub", productType: .subscription,
                            coinsGrantedDecimal: Decimal(string: "1.123456789123456789"),
                            weeklyPointsDecimal: Decimal(string: "0.123456789123456789"))
        XCTAssertEqual(try JSONDecoder().decode(Product.self, from: JSONEncoder().encode(exact)), exact)
    }

    func testProductsUseAuthenticatedV1TransportWithEmptyObject() async throws {
        let api = ProductAPI { path, data in
            XCTAssertEqual(path, "/api/v1/iap/products")
            XCTAssertEqual(String(data: data, encoding: .utf8), "{}")
            return Data(#"{"list":[{"market_product_id":"coins","coins_granted":1.25,"product_type":1}]}"#.utf8)
        }
        let products = try await api.getProducts()
        XCTAssertEqual(products.first?.coinsGrantedDecimal, Decimal(string: "1.25"))
    }

    func testMergeKeepsServerBenefitsAndStorePriceReadiness() {
        let api = Product(marketProductId: "monthly", name: "API", productType: .subscription,
                          weeklyPointsEnabled: true, coinsGrantedDecimal: Decimal(string: "1.123456789123456789"),
                          weeklyPointsDecimal: Decimal(string: "0.125"), priceUsd: 199, sort: 4)
        let store = Product(marketProductId: "monthly", name: "Store", productType: .subscription,
                            price: "2.99", currency: "EUR", localizedPrice: "EUR 2.99", storeDetailsAvailable: true)
        let merged = ProductDetailsMerger.merge(apiProducts: [api], storeProducts: [store])[0]
        XCTAssertEqual(merged.coinsGrantedDecimal, api.coinsGrantedDecimal)
        XCTAssertEqual(merged.weeklyPointsDecimal, api.weeklyPointsDecimal)
        XCTAssertEqual(merged.priceUsd, 199)
        XCTAssertEqual(merged.sort, 4)
        XCTAssertTrue(merged.storeDetailsAvailable)
        XCTAssertEqual(ProductPresentation.price(merged), "EUR 2.99")
        XCTAssertEqual(ProductPresentation.price(api), "Reference USD 1.99")
        XCTAssertEqual(ProductDetailsMerger.merge(apiProducts: [api], storeProducts: []), [api])
    }

    func testEnabledSubscriptionsShowBothUpfrontAndAdditionalWeeklyBenefits() {
        let product = Product(marketProductId: "sub", name: "Sub", productType: .subscription,
                              weeklyPointsEnabled: true, coinsGrantedDecimal: Decimal(string: "1.25"),
                              weeklyPointsDecimal: Decimal(string: "0.125"))
        XCTAssertEqual(ProductPresentation.creditBenefits(product),
                       ["Get 125 credits after purchase", "Plus 12.5 points every week"])
        var disabled = product
        disabled.weeklyPointsEnabled = false
        XCTAssertEqual(ProductPresentation.creditBenefits(disabled), ["Get 125 credits after purchase"])
        var oneTime = product
        oneTime.productType = .consumable
        XCTAssertEqual(ProductPresentation.creditBenefits(oneTime), ["Get 125 credits after purchase"])
    }

    func testClaimUsesEligibilityAmountAndReasons() {
        var info = WeeklyPointsInfo(isVip: true, marketProductId: "server-selected", weeklyPoints: 0,
                                    canClaim: true, cannotClaimReason: "", weeklyPointsDecimal: Decimal(string: "0.125"))
        XCTAssertEqual(ProductPresentation.claimDetail(info), "12.5 points ready to claim")
        info.canClaim = false
        info.cannotClaimReason = "already_claimed"
        XCTAssertEqual(ProductPresentation.claimDetail(info), "Claimed for this week")
        info.cannotClaimReason = "product_not_configured"
        XCTAssertEqual(ProductPresentation.claimDetail(info), "Weekly points are unavailable for this subscription")
        info.cannotClaimReason = "no_valid_subscription"
        XCTAssertEqual(ProductPresentation.claimDetail(info), "An eligible subscription is required")
    }

    func testReferencePriceCannotEnableCheckoutAndPendingBlocksRepurchase() {
        var product = Product(marketProductId: "sub", name: "Sub", productType: .subscription, priceUsd: 199)
        XCTAssertFalse(ProductPresentation.canPurchase(product, channel: .appStore, pendingProductIds: []))
        product.localizedPrice = "$1.99"
        XCTAssertFalse(ProductPresentation.canPurchase(product, channel: .appStore, pendingProductIds: []))
        product.storeDetailsAvailable = true
        XCTAssertTrue(ProductPresentation.canPurchase(product, channel: .appStore, pendingProductIds: []))
        XCTAssertFalse(ProductPresentation.canPurchase(product, channel: .appStore, pendingProductIds: ["sub"]))
        XCTAssertFalse(ProductPresentation.canPurchase(product, channel: .stripe, pendingProductIds: []))
        XCTAssertTrue(ProductPresentation.canPurchase(product, channel: .mock, pendingProductIds: []))
    }

    func testOrderStatusCodes() {
        let codes: [(Int?, OrderVerificationResult.Status)] = [
            (10, .pending), (50, .success), (60, .refunded), (70, .cancelled), (80, .expired),
            (20, .unknown), (999, .unknown), (nil, .unknown)
        ]
        for (code, expected) in codes { XCTAssertEqual(OrderVerificationResult.Status.fromCode(code), expected) }
    }

    func testSubscriptionOrderFieldWhitelists() async throws {
        for channel in [PaymentChannel.googlePlay, .appStore] {
            let api = OrderVerificationAPI { path, data in
                XCTAssertEqual(path, channel == .appStore ? "/api/v1/order/apple/status" : "/api/v1/order/google/status")
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(Set(body.keys), channel == .appStore ? ["original_transaction_id", "issub"] : ["token", "issub"])
                XCTAssertEqual(body["issub"] as? Bool, true)
                if channel == .appStore { XCTAssertEqual(body["original_transaction_id"] as? String, "original") }
                return Data(#"{"trade_order_id":"","status":10,"issub":true,"platform_product_id":"","amount":"0","currency":"","success_count":0}"#.utf8)
            }
            let result = try await api.verify(channel: channel, token: "store-token", platformProductId: "must-omit",
                                              isSubscription: true, tradeOrderId: "must-omit", originalTransactionId: "original")
            XCTAssertEqual(result.status, .pending)
            XCTAssertEqual(result.tradeOrderId, "")
            XCTAssertEqual(result.platformProductId, "")
            XCTAssertNil(result.token)
            XCTAssertNil(result.endsTime)
        }
    }

    func testOneTimeOrderWhitelistAmountCurrencyAndUnixSeconds() async throws {
        for channel in [PaymentChannel.googlePlay, .appStore] {
            let api = OrderVerificationAPI { _, data in
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(Set(body.keys), ["token", "trade_order_id", "platform_product_id", "issub"])
                XCTAssertEqual(body["trade_order_id"] as? String, "current")
                XCTAssertEqual(body["issub"] as? Bool, false)
                return Data(#"{"trade_order_id":"current","status":50,"issub":false,"platform_product_id":"sku","amount":"1.9900","currency":"USD","started_at":1789084800,"expires_at":1791676800}"#.utf8)
            }
            let result = try await api.verify(channel: channel, token: "jws", platformProductId: "sku",
                                              isSubscription: false, tradeOrderId: "current", originalTransactionId: "omit")
            XCTAssertTrue(result.isSuccessful)
            XCTAssertEqual(result.amount, "1.9900")
            XCTAssertEqual(result.currency, "USD")
            XCTAssertEqual(result.startedTime, 1_789_084_800)
            XCTAssertEqual(result.endsTime, 1_791_676_800)
            XCTAssertNil(result.token)
        }
    }

    func testAppleOneTimeAllowsTransactionIdWithoutJWS() async throws {
        let api = OrderVerificationAPI { _, data in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(body.keys), ["trade_order_id", "platform_product_id", "issub"])
            return Data(#"{"trade_order_id":"current","status":50,"issub":false,"platform_product_id":"sku","amount":"1","currency":"USD"}"#.utf8)
        }
        _ = try await api.verify(channel: .appStore, token: "", platformProductId: "sku", isSubscription: false, tradeOrderId: "current")
    }

    func testAppleSubscriptionRequiresOriginalIdWithoutFallback() async {
        let api = OrderVerificationAPI { _, _ in XCTFail("Invalid request must not be sent"); return Data() }
        do {
            _ = try await api.verify(channel: .appStore, token: "jws", platformProductId: "sku",
                                     isSubscription: true, tradeOrderId: "current")
            XCTFail("Missing original id should fail")
        } catch {}
    }

    func testStoreIdentityPreservesCompactUIDAndRejectsUnrelatedValues() {
        XCTAssertEqual(AppStorePaymentProvider.accountToken(uid: "7d924efe21a846f6b64d7c048e21cb51"),
                       UUID(uuidString: "7d924efe-21a8-46f6-b64d-7c048e21cb51"))
        XCTAssertNil(AppStorePaymentProvider.accountToken(uid: "not-a-uuid"))
        XCTAssertNil(AppStorePaymentProvider.accountToken(uid: String(repeating: "z", count: 32)))
    }

    func testRenewalDeliveryUsesCurrentTransactionId() {
        let product = Product(marketProductId: "sub", name: "Sub", productType: .subscription)
        func result(_ id: UInt64) -> ProviderPurchaseResult {
            ProviderPurchaseResult(channel: .appStore, product: product, success: true, orderId: "original",
                                   purchaseToken: nil, platformProductId: "sub", isSubscription: true, message: nil,
                                   rawData: ["transaction_id": AnySendableValue(id)])
        }
        XCTAssertEqual(NexusPayment.shared.deliveryId(for: result(101)), "101")
        XCTAssertEqual(NexusPayment.shared.deliveryId(for: result(102)), "102")
    }

    func testClaimRefreshesBalanceAndEligibilityWithoutSKU() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let result = try await NexusPayment.shared.claimWeeklyPoints()
        XCTAssertEqual(result.pointsDecimal, Decimal(string: "0.125"))
        XCTAssertEqual(try NexusCoreUser.shared.getCurrentUser()?.balanceDecimal, Decimal(string: "1012.5"))
        XCTAssertEqual(fixture.claimBodies, ["{}"])
        XCTAssertGreaterThanOrEqual(fixture.infoCalls, 1)
        XCTAssertGreaterThanOrEqual(fixture.weeklyCalls, 1)
    }

    func testFailedClaimIsNotReplayedAndStillRefreshes() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        fixture.claimCode = 2130
        do { _ = try await NexusPayment.shared.claimWeeklyPoints(); XCTFail("Expected already claimed") } catch {}
        XCTAssertEqual(fixture.claimBodies.count, 1)
        XCTAssertGreaterThanOrEqual(fixture.infoCalls, 1)
        XCTAssertGreaterThanOrEqual(fixture.weeklyCalls, 1)
    }

    func testLegacyClaimRejectsSKUWithoutSendingClaim() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        do {
            _ = try await NexusPayment.shared.claimWeeklyPoints(marketProductId: "must-not-select")
            XCTFail("Selecting a SKU must fail locally")
        } catch {
            XCTAssertEqual(error as? PaymentError, .invalidConfig("Weekly claim does not accept a product id"))
        }
        XCTAssertTrue(fixture.claimBodies.isEmpty)
    }

    func testOrderStatesNeverCreditBalanceAndOnlyPaidCompletes() async throws {
        for status in [10, 50, 60, 70, 80, 999] {
            let fixture = try PaymentFixture()
            defer { fixture.close() }
            fixture.orderStatus = status
            let provider = RecordingProvider()
            NexusPayment.shared.registerProvider(provider)
            let result = try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay)
            XCTAssertEqual(result.success, status == 50)
            XCTAssertEqual(provider.completed, status == 50 ? 1 : 0)
            XCTAssertEqual(try NexusCoreUser.shared.getCurrentUser()?.balanceDecimal, Decimal(1000))
            if status == 50 { XCTAssertEqual(result.entitlement?.active, false, "Order status cannot establish VIP") }
        }
    }

    func testVerificationFailureLeavesTransactionUnfinishedWithoutReplay() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        fixture.orderCode = 500
        let provider = RecordingProvider()
        NexusPayment.shared.registerProvider(provider)
        let first = try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertFalse(first.success)
        let second = try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertFalse(second.success)
        XCTAssertEqual(provider.purchaseCalls, 1, "Uncertain paid orders must not open checkout again")
        XCTAssertEqual(provider.completed, 0)
        XCTAssertEqual(fixture.orderCalls, 1)
    }

    func testLaterAccountRefreshUpdatesSubscriptionEntitlementAndExpiry() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let provider = RecordingProvider()
        NexusPayment.shared.registerProvider(provider)
        _ = try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertEqual(NexusPayment.shared.getEntitlements().first?.active, false)
        XCTAssertEqual(NexusPayment.shared.getEntitlements().first?.reconciliationPending, true)
        XCTAssertEqual(NexusPayment.shared.getPendingProductIds(), ["sub"])
        fixture.isVip = true
        fixture.vipExpiry = 4_102_444_800
        _ = try await NexusCoreUser.shared.fetchUserInfo()
        XCTAssertEqual(NexusPayment.shared.getEntitlements().first?.active, true)
        XCTAssertTrue(NexusPayment.shared.getPendingProductIds().isEmpty)
        XCTAssertEqual(NexusPayment.shared.getEntitlements().first?.reconciliationPending, false)
        fixture.vipExpiry = 1
        _ = try await NexusCoreUser.shared.fetchUserInfo()
        XCTAssertEqual(NexusPayment.shared.getEntitlements().first?.active, false)
        XCTAssertEqual(provider.purchaseCalls, 1)
    }

    func testRestoreDoesNotReportPendingStoreTransactionAsSuccessful() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        fixture.orderStatus = 10
        let provider = RecordingProvider()
        NexusPayment.shared.registerProvider(provider)
        let result = try await NexusPayment.shared.restore(channel: .googlePlay)
        XCTAssertEqual(result.purchases.count, 1)
        XCTAssertFalse(result.purchases[0].success)
        XCTAssertEqual(provider.completed, 0)
    }

    func testTimeoutPersistsPendingAcrossReinitializationAndRestoreResolves() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let sdk = NexusPayment.shared
        fixture.orderError = URLError(.timedOut)
        let provider = RecordingProvider()
        sdk.registerProvider(provider)
        let first = try await sdk.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertTrue(first.pending)
        XCTAssertEqual(sdk.getPendingProductIds(), ["sub"])
        sdk.initialize(config: try sdk.getConfig())
        sdk.registerProvider(provider)
        let again = try await sdk.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertTrue(again.pending)
        XCTAssertEqual(provider.purchaseCalls, 1)
        fixture.orderError = nil
        fixture.isVip = true
        fixture.vipExpiry = 4_102_444_800
        let restored = try await sdk.restore(channel: .googlePlay)
        XCTAssertTrue(restored.purchases[0].success)
        XCTAssertTrue(sdk.getPendingProductIds().isEmpty)
        XCTAssertEqual(provider.completed, 1)
    }

    func testReadOnlyReconciliationResolvesPendingWithoutAnotherCheckout() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        fixture.orderStatus = 10
        let provider = RecordingProvider()
        NexusPayment.shared.registerProvider(provider)
        let pending = try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertTrue(pending.pending)
        fixture.orderStatus = 50
        fixture.isVip = true
        fixture.vipExpiry = 4_102_444_800
        try await NexusPayment.shared.reconcilePendingPurchases()
        XCTAssertTrue(NexusPayment.shared.getPendingProductIds().isEmpty)
        XCTAssertEqual(provider.purchaseCalls, 1)
        XCTAssertEqual(provider.completed, 1)
    }

    func testMixedOwnerRestoreContinuesInEitherOrderAndNeverFinishesForeignItems() async throws {
        for foreignFirst in [true, false] {
            let fixture = try PaymentFixture()
            defer { fixture.close() }
            let sdk = NexusPayment.shared
            var config = try sdk.getConfig()
            config.enabledChannels.append(.appStore)
            sdk.initialize(config: config)
            let provider = RecordingProvider(channel: .appStore)
            var owned = provider.result
            owned.rawData = ["owner_uid": AnySendableValue("7d924efe-21a8-46f6-b64d-7c048e21cb51"),
                             "original_transaction_id": AnySendableValue("original")]
            var foreign = owned
            foreign.orderId = "foreign"
            foreign.rawData["owner_uid"] = AnySendableValue(UUID().uuidString)
            var legacy = owned
            legacy.orderId = "legacy"
            legacy.rawData.removeValue(forKey: "owner_uid")
            provider.restored = foreignFirst ? [foreign, legacy, owned] : [owned, legacy, foreign]
            sdk.registerProvider(provider)
            let result = try await sdk.restore(channel: .appStore)
            XCTAssertEqual(result.purchases.filter(\.success).map(\.orderId), ["current"])
            XCTAssertEqual(result.purchases.filter { !$0.success }.count, 2)
            XCTAssertTrue(result.purchases.filter { !$0.success }.allSatisfy { $0.message?.contains("does not belong") == true })
            XCTAssertEqual(provider.completedIds, ["current"])
            XCTAssertEqual(fixture.orderCalls, 1)
        }
    }

    func testBoundedAutomaticRetryCompletesPaidTransactionWithoutCheckout() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        fixture.orderCode = 429
        let provider = RecordingProvider()
        let completed = expectation(description: "Paid transaction reconciled automatically")
        let observation = NotificationCenter.default.addObserver(forName: NexusPayment.stateDidChange, object: nil, queue: nil) { _ in
            if provider.completed == 1 && NexusPayment.shared.getPendingProductIds().isEmpty { completed.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observation) }
        NexusPayment.shared.registerProvider(provider)
        let result = try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertTrue(result.pending)
        fixture.orderCode = 1
        fixture.isVip = true
        fixture.vipExpiry = 4_102_444_800
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertTrue(NexusPayment.shared.getPendingProductIds().isEmpty)
        XCTAssertEqual(provider.purchaseCalls, 1)
        XCTAssertEqual(provider.completed, 1)
    }

    func testTransactionUpdateClearsPendingAndRejectsObsoleteObserver() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let sdk = NexusPayment.shared
        var config = try sdk.getConfig()
        config.enabledChannels.append(.appStore)
        sdk.initialize(config: config)
        let provider = RecordingProvider(channel: .appStore)
        sdk.registerProvider(provider)
        let operation = try await sdk.captureOperation()
        var transaction = provider.result
        transaction.rawData = ["owner_uid": AnySendableValue("7d924efe-21a8-46f6-b64d-7c048e21cb51"),
                               "original_transaction_id": AnySendableValue("original")]
        fixture.orderStatus = 10
        let pending = try await sdk.handleTransactionUpdate(transaction, provider: provider, observedGeneration: operation.generation)
        XCTAssertTrue(pending.pending)
        XCTAssertEqual(sdk.getPendingProductIds(), ["sub"])
        fixture.orderStatus = 50
        fixture.isVip = true
        fixture.vipExpiry = 4_102_444_800
        let resolved = try await sdk.handleTransactionUpdate(transaction, provider: provider, observedGeneration: operation.generation)
        XCTAssertTrue(resolved.success)
        XCTAssertTrue(sdk.getPendingProductIds().isEmpty)
        XCTAssertEqual(provider.completed, 1)
        sdk.initialize(config: config)
        do {
            _ = try await sdk.handleTransactionUpdate(transaction, provider: provider, observedGeneration: operation.generation)
            XCTFail("Obsolete observer must not publish or finish")
        } catch {}
        XCTAssertEqual(provider.completed, 1)
    }

    func testDelayedCatalogResponseCannotReplaceNewConfiguration() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let gate = PaymentGate()
        PaymentURLProtocol.beforeResponse = { request in
            if request.url?.path == "/api/v1/iap/products" { await gate.pause() }
        }
        let task = Task { try await NexusPayment.shared.getProducts(forceRefresh: true) }
        await gate.waitUntilPaused()
        NexusPayment.shared.initialize(config: try PaymentConfig(productId: "replacement", defaultChannel: .mock, enabledChannels: [.mock]))
        let replacement = Product(marketProductId: "new", name: "New", productType: .iap)
        NexusPayment.shared.setProductsForTesting([replacement])
        await gate.release()
        do { _ = try await task.value; XCTFail("Stale catalog must fail") } catch {}
        let products = try await NexusPayment.shared.getProducts()
        XCTAssertEqual(products, [replacement])
    }

    func testDelayedStoreEnrichmentCannotReplaceNewConfiguration() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let sdk = NexusPayment.shared
        var config = try sdk.getConfig()
        config.enabledChannels.append(.appStore)
        sdk.initialize(config: config)
        let provider = RecordingProvider(channel: .appStore)
        let gate = PaymentGate()
        provider.catalogGate = gate
        sdk.registerProvider(provider)
        let operation = try await sdk.captureOperation()
        let task = Task { try await sdk.enrichProductsWithAppStore([provider.product], operation: operation) }
        await gate.waitUntilPaused()
        sdk.initialize(config: try PaymentConfig(productId: "replacement", defaultChannel: .mock, enabledChannels: [.mock]))
        let replacement = Product(marketProductId: "new", name: "New", productType: .iap)
        sdk.setProductsForTesting([replacement])
        await gate.release()
        do { _ = try await task.value; XCTFail("Stale enrichment must fail") } catch {}
        let products = try await sdk.getProducts()
        XCTAssertEqual(products, [replacement])
    }

    func testReinitializationDiscardsDelayedPurchaseRestoreAndEntitlementRefresh() async throws {
        for stage in ["purchase", "restore", "refresh"] {
            let fixture = try PaymentFixture()
            defer { fixture.close() }
            _ = try await NexusCoreUser.shared.silentLogin()
            let sdk = NexusPayment.shared
            let provider = RecordingProvider()
            let gate = PaymentGate()
            if stage == "purchase" { provider.purchaseGate = gate }
            if stage == "restore" { provider.restoreGate = gate }
            if stage == "refresh" {
                PaymentURLProtocol.beforeResponse = { request in
                    if request.url?.path == "/api/v1/account/info" { await gate.pause() }
                }
            }
            sdk.registerProvider(provider)
            let task = Task {
                if stage == "restore" { _ = try await sdk.restore(channel: .googlePlay) }
                else { _ = try await sdk.purchase(product: provider.product, channel: .googlePlay) }
            }
            await gate.waitUntilPaused()
            sdk.initialize(config: try PaymentConfig(productId: "replacement-\(UUID())", defaultChannel: .mock, enabledChannels: [.mock]))
            await gate.release()
            do { try await task.value; XCTFail("Stale \(stage) must fail") } catch {}
            XCTAssertTrue(sdk.getEntitlements().isEmpty)
            XCTAssertTrue(sdk.getPendingProductIds().isEmpty)
            XCTAssertEqual(provider.completed, 0)
            if stage == "refresh" { XCTAssertEqual(fixture.orderCalls, 1) }
        }
    }

    func testClaimDiscardsSuccessWhenAccountChangesDuringEitherRefresh() async throws {
        for path in ["/api/v1/account/info", "/api/v1/weekly-points/info"] {
            let fixture = try PaymentFixture()
            defer { fixture.close() }
            _ = try await NexusCoreUser.shared.silentLogin()
            let gate = PaymentGate()
            PaymentURLProtocol.beforeResponse = { request in
                if request.url?.path == path { await gate.pause() }
            }
            let task = Task { try await NexusPayment.shared.claimWeeklyPoints() }
            await gate.waitUntilPaused()
            try NexusCoreUser.shared.clearLocalSession()
            fixture.uid = "8d924efe21a846f6b64d7c048e21cb52"
            fixture.token = "replacement-token"
            _ = try await NexusCoreUser.shared.silentLogin()
            await gate.release()
            do { _ = try await task.value; XCTFail("A's claim must not be delivered to B") } catch {}
            XCTAssertEqual(fixture.claimBodies.count, 1)
            XCTAssertEqual(try NexusCoreUser.shared.getCurrentUser()?.uid, fixture.uid)
            if path == "/api/v1/account/info" { XCTAssertEqual(fixture.weeklyCalls, 0) }
        }
    }

    func testStateIsIsolatedByServiceAndPaymentProduct() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let sdk = NexusPayment.shared
        let provider = RecordingProvider()
        sdk.registerProvider(provider)
        fixture.orderStatus = 10
        _ = try await sdk.purchase(product: provider.product, channel: .googlePlay)
        let originalConfig = try sdk.getConfig()
        sdk.initialize(config: try PaymentConfig(productId: "different", defaultChannel: .mock, enabledChannels: [.mock]))
        XCTAssertTrue(sdk.getPendingProductIds().isEmpty)
        sdk.initialize(config: originalConfig)
        XCTAssertEqual(sdk.getPendingProductIds(), ["sub"])
        try fixture.initializeCore(baseURL: "https://other.payment.unit.test")
        _ = try await NexusCoreUser.shared.silentLogin()
        XCTAssertTrue(sdk.getPendingProductIds().isEmpty)
        XCTAssertTrue(sdk.getEntitlements().isEmpty)
    }

    func testConcurrentCheckoutIsBlockedBeforeTheStoreReturns() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let provider = RecordingProvider()
        let gate = PaymentGate()
        provider.purchaseGate = gate
        NexusPayment.shared.registerProvider(provider)
        let first = Task { try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay) }
        await gate.waitUntilPaused()
        let duplicate = try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertTrue(duplicate.pending)
        XCTAssertEqual(provider.purchaseCalls, 1)
        await gate.release()
        _ = try await first.value
    }

    func testClaimCompletionRejectsChangedTokenEvenForSameUID() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        _ = try await NexusCoreUser.shared.silentLogin()
        let gate = PaymentGate()
        PaymentURLProtocol.beforeResponse = { request in
            if request.url?.path == "/api/v1/weekly-points/info" { await gate.pause() }
        }
        let completion = expectation(description: "Stale claim reports failure")
        NexusPayment.shared.claimWeeklyPoints { result in
            if case .success = result { XCTFail("Must reject a new token for the same UID") }
            completion.fulfill()
        }
        await gate.waitUntilPaused()
        try NexusCoreUser.shared.clearLocalSession()
        fixture.token = "same-user-new-token"
        _ = try await NexusCoreUser.shared.silentLogin()
        await gate.release()
        await fulfillment(of: [completion], timeout: 5)
        XCTAssertEqual(fixture.claimBodies.count, 1)
    }

    func testCatalogCacheDoesNotCrossServiceOrSession() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let first = try await NexusPayment.shared.getProducts()
        XCTAssertEqual(first.first?.marketProductId, "sub")
        fixture.catalogSKU = "other-service"
        try fixture.initializeCore(baseURL: "https://other.payment.unit.test")
        let otherService = try await NexusPayment.shared.getProducts()
        XCTAssertEqual(otherService.first?.marketProductId, "other-service")
        fixture.catalogSKU = "other-session"
        try NexusCoreUser.shared.clearLocalSession()
        fixture.token = "new-catalog-session"
        _ = try await NexusCoreUser.shared.silentLogin()
        let otherSession = try await NexusPayment.shared.getProducts()
        XCTAssertEqual(otherSession.first?.marketProductId, "other-session")
    }

    func testAccountRefreshFailureRemainsReconcilableAfterVerifiedPayment() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        _ = try await NexusCoreUser.shared.silentLogin()
        let provider = RecordingProvider()
        NexusPayment.shared.registerProvider(provider)
        fixture.infoError = URLError(.timedOut)
        let result = try await NexusPayment.shared.purchase(product: provider.product, channel: .googlePlay)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.entitlement?.reconciliationPending, true)
        XCTAssertEqual(provider.completed, 1)
        fixture.infoError = nil
        fixture.isVip = true
        fixture.vipExpiry = 4_102_444_800
        _ = try await NexusCoreUser.shared.fetchUserInfo()
        XCTAssertEqual(NexusPayment.shared.getEntitlements().first?.active, true)
        XCTAssertTrue(NexusPayment.shared.getPendingProductIds().isEmpty)
    }

    func testEntitlementDecodesWithoutNewReconciliationField() throws {
        let data = Data(#"{"entitlementId":"sub","productId":"sub","orderId":"1","channel":"app_store","active":false}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Entitlement.self, from: data).reconciliationPending)
    }

    func testStaleCancelledReservationDoesNotPersistAcrossConfigurationOrTokenReplacement() async throws {
        for replacement in ["configuration", "token"] {
            for throwsError in [false, true] {
                let fixture = try PaymentFixture()
                defer { fixture.close() }
                _ = try await NexusCoreUser.shared.silentLogin()
                let sdk = NexusPayment.shared
                let provider = RecordingProvider()
                var cancelled = provider.result
                cancelled.success = false
                cancelled.orderId = nil
                cancelled.message = "User cancelled"
                provider.purchaseOverride = cancelled
                provider.purchaseError = throwsError ? URLError(.cancelled) : nil
                provider.restored = []
                let gate = PaymentGate()
                provider.purchaseGate = gate
                sdk.registerProvider(provider)
                let checkout = Task { try await sdk.purchase(product: provider.product, channel: .googlePlay) }
                await gate.waitUntilPaused()
                if replacement == "configuration" {
                    sdk.initialize(config: try sdk.getConfig())
                    sdk.registerProvider(provider)
                } else {
                    try NexusCoreUser.shared.clearLocalSession()
                    fixture.token = "replacement-checkout-token"
                    _ = try await NexusCoreUser.shared.silentLogin()
                }
                await gate.release()
                do { _ = try await checkout.value; XCTFail("Obsolete checkout must be rejected") } catch {}
                _ = try await sdk.restore(channel: .googlePlay)
                try await sdk.reconcilePendingPurchases()
                XCTAssertTrue(sdk.getPendingProductIds().isEmpty, replacement)
                provider.purchaseError = nil
                let retry = try await sdk.purchase(product: provider.product, channel: .googlePlay)
                XCTAssertFalse(retry.pending)
                XCTAssertEqual(provider.purchaseCalls, 2, "Definite cancellation must allow a new checkout")
            }
        }
    }

    func testStaleCancellationCannotReleaseReplacementCheckoutReservation() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        let sdk = NexusPayment.shared
        let old = RecordingProvider()
        var cancelled = old.result
        cancelled.success = false
        cancelled.orderId = nil
        old.purchaseOverride = cancelled
        let oldGate = PaymentGate()
        old.purchaseGate = oldGate
        sdk.registerProvider(old)
        let oldCheckout = Task { try await sdk.purchase(product: old.product, channel: .googlePlay) }
        await oldGate.waitUntilPaused()
        sdk.initialize(config: try sdk.getConfig())
        let current = RecordingProvider()
        current.purchaseOverride = cancelled
        let currentGate = PaymentGate()
        current.purchaseGate = currentGate
        sdk.registerProvider(current)
        let started = expectation(description: "Replacement checkout reaches provider")
        current.onPurchase = { started.fulfill() }
        let currentCheckout = Task { try await sdk.purchase(product: current.product, channel: .googlePlay) }
        await fulfillment(of: [started], timeout: 2)
        await oldGate.release()
        _ = try? await oldCheckout.value
        let duplicate = try await sdk.purchase(product: current.product, channel: .googlePlay)
        XCTAssertTrue(duplicate.pending)
        XCTAssertEqual(current.purchaseCalls, 1)
        await currentGate.release()
        _ = try await currentCheckout.value
        XCTAssertTrue(sdk.getPendingProductIds().isEmpty)
    }

    func testOldTerminalSubscriptionChainCannotOverrideCurrentChainInEitherRestoreOrder() async throws {
        for terminalStatus in [60, 70, 80] {
            for terminalFirst in [true, false] {
                let fixture = try PaymentFixture()
                defer { fixture.close() }
                fixture.isVip = true
                fixture.vipExpiry = 4_102_444_800
                fixture.orderDataByChain = [
                    "current-chain": subscriptionData(order: "current-order", status: 50, start: 1_790_000_000, end: 4_102_444_800),
                    "old-chain": subscriptionData(order: "old-order", status: terminalStatus, start: 1_600_000_000, end: 1_700_000_000)
                ]
                let sdk = NexusPayment.shared
                var config = try sdk.getConfig()
                config.enabledChannels.append(.appStore)
                sdk.initialize(config: config)
                let provider = RecordingProvider(channel: .appStore)
                let current = appleTransaction(provider, order: "current-order", chain: "current-chain")
                let old = appleTransaction(provider, order: "old-order", chain: "old-chain")
                provider.restored = terminalFirst ? [old, current] : [current, old]
                sdk.registerProvider(provider)
                _ = try await sdk.restore(channel: .appStore)
                XCTAssertEqual(sdk.getEntitlements().first?.active, true)
                XCTAssertEqual(sdk.getEntitlements().first?.orderId, "current-order")
                XCTAssertEqual(sdk.getEntitlements().first?.endsTime, 4_102_444_800)
                XCTAssertEqual(provider.completedIds, ["current-order"])
                // An old unfinished chain replayed after restart must not revoke the current chain.
                sdk.initialize(config: config)
                sdk.registerProvider(provider)
                let operation = try await sdk.captureOperation()
                _ = try await sdk.handleTransactionUpdate(old, provider: provider, observedGeneration: operation.generation)
                _ = try await NexusCoreUser.shared.fetchUserInfo()
                XCTAssertEqual(sdk.getEntitlements().first?.active, true)
                XCTAssertEqual(sdk.getEntitlements().first?.orderId, "current-order")
                XCTAssertEqual(sdk.getEntitlements().first?.endsTime, 4_102_444_800)
                fixture.isVip = false
                fixture.vipExpiry = 0
                _ = try await NexusCoreUser.shared.fetchUserInfo()
                XCTAssertEqual(sdk.getEntitlements().first?.active, false, "The current account remains authoritative")
            }
        }
    }

    private func subscriptionData(order: String, status: Int, start: Int64, end: Int64) -> [String: Any] {
        ["trade_order_id": order, "status": status, "issub": true, "platform_product_id": "sub",
         "amount": "1.99", "currency": "USD", "started_at": start, "expires_at": end]
    }

    func testStaleStorePendingOrPaidResultRemainsDurableAfterReservationCleanup() async throws {
        for paid in [false, true] {
            let fixture = try PaymentFixture()
            defer { fixture.close() }
            let sdk = NexusPayment.shared
            let provider = RecordingProvider()
            var unresolved = provider.result
            unresolved.success = paid
            unresolved.pending = !paid
            provider.purchaseOverride = unresolved
            provider.restored = []
            let gate = PaymentGate()
            provider.purchaseGate = gate
            sdk.registerProvider(provider)
            let task = Task { try await sdk.purchase(product: provider.product, channel: .googlePlay) }
            await gate.waitUntilPaused()
            sdk.initialize(config: try sdk.getConfig())
            sdk.registerProvider(provider)
            await gate.release()
            do { _ = try await task.value; XCTFail("Stale operation must fail") } catch {}
            _ = try await sdk.restore(channel: .googlePlay)
            try await sdk.reconcilePendingPurchases()
            XCTAssertEqual(sdk.getPendingProductIds(), ["sub"])
            let duplicate = try await sdk.purchase(product: provider.product, channel: .googlePlay)
            XCTAssertTrue(duplicate.pending)
            XCTAssertEqual(provider.purchaseCalls, 1)
            XCTAssertEqual(provider.completed, 0)
        }
    }

    func testCurrentTerminalChainDeactivatesWithoutOlderPaidReplayResurrectingIt() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        fixture.isVip = true
        fixture.vipExpiry = 4_102_444_800
        let paidData = subscriptionData(order: "current-order", status: 50, start: 1_790_000_000, end: 4_102_444_800)
        fixture.orderDataByChain = ["current-chain": paidData]
        let sdk = NexusPayment.shared
        var config = try sdk.getConfig()
        config.enabledChannels.append(.appStore)
        sdk.initialize(config: config)
        let provider = RecordingProvider(channel: .appStore)
        sdk.registerProvider(provider)
        let current = appleTransaction(provider, order: "current-order", chain: "current-chain")
        let operation = try await sdk.captureOperation()
        _ = try await sdk.handleTransactionUpdate(current, provider: provider, observedGeneration: operation.generation)
        XCTAssertEqual(sdk.getEntitlements().first?.active, true)
        fixture.orderDataByChain["current-chain"] = subscriptionData(order: "current-order", status: 60, start: 1_790_000_000, end: 4_102_444_800)
        _ = try await sdk.handleTransactionUpdate(current, provider: provider, observedGeneration: operation.generation)
        XCTAssertEqual(sdk.getEntitlements().first?.active, false)
        XCTAssertEqual(provider.completed, 1, "Terminal results must remain unfinished")
        fixture.orderDataByChain["current-chain"] = paidData
        _ = try await sdk.handleTransactionUpdate(current, provider: provider, observedGeneration: operation.generation)
        XCTAssertEqual(sdk.getEntitlements().first?.active, false)
    }

    func testOlderTerminalDeliveryInSameChainDoesNotReplaceNewerRenewal() async throws {
        let fixture = try PaymentFixture()
        defer { fixture.close() }
        fixture.isVip = true
        fixture.vipExpiry = 4_102_444_800
        let sdk = NexusPayment.shared
        var config = try sdk.getConfig()
        config.enabledChannels.append(.appStore)
        sdk.initialize(config: config)
        let provider = RecordingProvider(channel: .appStore)
        sdk.registerProvider(provider)
        let operation = try await sdk.captureOperation()
        let current = appleTransaction(provider, order: "renewal", chain: "chain")
        let older = appleTransaction(provider, order: "original", chain: "chain")
        fixture.orderDataByChain["chain"] = subscriptionData(order: "renewal", status: 50, start: 1_790_000_000, end: 4_102_444_800)
        _ = try await sdk.handleTransactionUpdate(current, provider: provider, observedGeneration: operation.generation)
        fixture.orderDataByChain["chain"] = subscriptionData(order: "original", status: 80, start: 1_600_000_000, end: 1_700_000_000)
        _ = try await sdk.handleTransactionUpdate(older, provider: provider, observedGeneration: operation.generation)
        XCTAssertEqual(sdk.getEntitlements().first?.active, true)
        XCTAssertEqual(sdk.getEntitlements().first?.orderId, "renewal")
        XCTAssertEqual(sdk.getEntitlements().first?.endsTime, 4_102_444_800)
    }

    private func appleTransaction(_ provider: RecordingProvider, order: String, chain: String) -> ProviderPurchaseResult {
        var transaction = provider.result
        transaction.orderId = order
        transaction.rawData = ["owner_uid": AnySendableValue("7d924efe-21a8-46f6-b64d-7c048e21cb51"),
                               "original_transaction_id": AnySendableValue(chain),
                               "transaction_id": AnySendableValue(order)]
        return transaction
    }
}

private final class RecordingProvider: PaymentProvider, @unchecked Sendable {
    let channel: PaymentChannel
    let requiresServerVerification = true
    let product = Product(marketProductId: "sub", name: "Sub", productType: .subscription,
                          coinsGrantedDecimal: 100, weeklyPointsDecimal: 30)
    var completed = 0
    var purchaseCalls = 0
    var completedIds: [String] = []
    var restored: [ProviderPurchaseResult]?
    var catalogGate: PaymentGate?
    var purchaseGate: PaymentGate?
    var restoreGate: PaymentGate?
    var purchaseOverride: ProviderPurchaseResult?
    var purchaseError: Error?
    var onPurchase: (@Sendable () -> Void)?
    init(channel: PaymentChannel = .googlePlay) { self.channel = channel }
    var result: ProviderPurchaseResult {
        ProviderPurchaseResult(channel: channel, product: product, success: true, orderId: "current",
                               purchaseToken: "store-token", platformProductId: "sub", isSubscription: true,
                               message: nil, rawData: [:])
    }
    func getProducts(productIds: [String]) async throws -> [Product] {
        await catalogGate?.pause()
        return [product]
    }
    func purchase(request: PurchaseRequest) async throws -> ProviderPurchaseResult {
        purchaseCalls += 1
        let outcome = purchaseOverride ?? result
        let error = purchaseError
        onPurchase?()
        await purchaseGate?.pause()
        if let error { throw error }
        return outcome
    }
    func completePurchase(_ result: ProviderPurchaseResult) async {
        completed += 1
        completedIds.append(result.orderId ?? "")
    }
    func restore() async throws -> RestoreResult {
        await restoreGate?.pause()
        return RestoreResult(channel: channel, purchases: restored ?? [result], message: nil)
    }
}

private final class PaymentFixture: @unchecked Sendable {
    let productId = "payment-test-\(UUID().uuidString)"
    var infoCalls = 0
    var weeklyCalls = 0
    var orderCalls = 0
    var claimBodies: [String] = []
    var claimCode = 1
    var orderStatus = 50
    var orderCode = 1
    var orderError: Error?
    var orderDataByChain: [String: [String: Any]] = [:]
    var infoError: Error?
    var catalogSKU = "sub"
    var claimed = false
    var isVip = false
    var vipExpiry: Int64 = 0
    var uid = "7d924efe21a846f6b64d7c048e21cb51"
    var token = "test-session-token"
    private var session: URLSession!

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaymentURLProtocol.self]
        session = URLSession(configuration: configuration)
        PaymentURLProtocol.handler = { [unowned self] request in
            let path = request.url!.path
            let body: String
            if path != "/api/v1/account/login" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            }
            switch path {
            case "/api/v1/account/login":
                body = #"{"code":1,"data":{"uid":"\#(uid)","token":"\#(token)","expires_at":4102444800}}"#
            case "/api/v1/account/info":
                infoCalls += 1
                if let infoError { throw infoError }
                body = #"{"code":1,"data":{"uid":"\#(uid)","balance":\#(claimed ? "10.125" : "10"),"is_vip":\#(isVip),"vip_expired_at":\#(vipExpiry)}}"#
            case "/api/v1/weekly-points/info":
                weeklyCalls += 1
                body = #"{"code":1,"data":{"is_vip":false,"market_product_id":"","weekly_points":0,"can_claim":false,"cannot_claim_reason":"no_valid_subscription"}}"#
            case "/api/v1/weekly-points/claim":
                let bytes = requestBody(request)
                claimBodies.append(String(data: bytes, encoding: .utf8) ?? "")
                XCTAssertEqual(try JSONSerialization.jsonObject(with: bytes) as? [String: String], [:])
                claimed = claimCode == 1
                body = claimCode == 1
                    ? #"{"code":1,"data":{"points":0.125,"market_product_id":"server-sub","transaction_id":"9007199254740993","claim_time":1789084800,"before_coins":10,"after_coins":10.125,"balance":10.125}}"#
                    : #"{"code":\#(claimCode),"message":"already claimed"}"#
            case "/api/v1/iap/products":
                body = #"{"code":1,"data":{"list":[{"market_product_id":"\#(catalogSKU)","name":"Sub","product_type":2}]}}"#
            case "/api/v1/order/google/status", "/api/v1/order/apple/status":
                orderCalls += 1
                if let orderError { throw orderError }
                let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any])
                XCTAssertEqual(Set(fields.keys), path.contains("apple") ? ["original_transaction_id", "issub"] : ["token", "issub"])
                if let chain = fields["original_transaction_id"] as? String, let data = orderDataByChain[chain] {
                    body = String(data: try JSONSerialization.data(withJSONObject: ["code": 1, "data": data]), encoding: .utf8)!
                } else {
                    body = orderCode == 1
                    ? #"{"code":1,"data":{"trade_order_id":"current","status":\#(orderStatus),"issub":true,"platform_product_id":"sub","amount":"1.99","currency":"USD"}}"#
                    : #"{"code":\#(orderCode),"message":"verification unavailable"}"#
                }
            default:
                XCTFail("Unexpected path: \(path)")
                body = #"{"code":500,"message":"unexpected path"}"#
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        try initializeCore()
        NexusPayment.shared.initialize(config: try PaymentConfig(productId: productId, defaultChannel: .googlePlay,
                                                                 enabledChannels: [.googlePlay]))
    }

    func initializeCore(baseURL: String = "https://payment.unit.test") throws {
        let core = NexusCoreUser.shared
        core.initialize(config: try CoreUserConfig(productId: productId, productName: "test", apiBaseUrl: baseURL, encrypt: false), session: session)
        try core.clearLocalSession()
    }

    func close() {
        if let config = try? NexusPayment.shared.getConfig() { NexusPayment.shared.initialize(config: config) }
        try? NexusCoreUser.shared.clearLocalSession()
        UserDefaults.standard.removeObject(forKey: "nexus.payment.\(productId).entitlements.7d924efe21a846f6b64d7c048e21cb51")
        PaymentURLProtocol.handler = nil
        PaymentURLProtocol.beforeResponse = nil
        // Remove only this fixture's scoped state, leaving other callers' defaults untouched.
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("nexus.payment.v2.") {
            let encoded = key.dropFirst("nexus.payment.v2.".count).split(separator: ".").first.map(String.init) ?? ""
            if let data = Data(base64Encoded: encoded),
               let scope = try? JSONDecoder().decode([String].self, from: data), scope.contains(productId) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        session.invalidateAndCancel()
    }

    private func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }
}

private final class PaymentURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var beforeResponse: (@Sendable (URLRequest) async -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            let beforeResponse = Self.beforeResponse
            Task {
                await beforeResponse?(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private actor PaymentGate {
    private var paused = false
    private var released = false
    private var entry: CheckedContinuation<Void, Never>?
    private var exit: CheckedContinuation<Void, Never>?

    func pause() async {
        guard !released, !paused else { return }
        paused = true
        entry?.resume()
        entry = nil
        await withCheckedContinuation { exit = $0 }
    }

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { entry = $0 }
    }

    func release() {
        released = true
        exit?.resume()
        exit = nil
    }
}
