import Foundation

enum ProductDetailsMerger {
    static func merge(apiProducts: [Product], storeProducts: [Product]) -> [Product] {
        let storeProductsById = Dictionary(
            storeProducts.map { ($0.marketProductId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return apiProducts.map { apiProduct in
            guard let storeProduct = storeProductsById[apiProduct.marketProductId] else {
                return apiProduct
            }
            return Product(
                marketProductId: apiProduct.marketProductId,
                name: storeProduct.name.isEmpty ? apiProduct.name : storeProduct.name,
                description: apiProduct.description.isEmpty ? storeProduct.description : apiProduct.description,
                productType: apiProduct.productType == .unknown ? storeProduct.productType : apiProduct.productType,
                coinsGranted: apiProduct.coinsGranted,
                price: storeProduct.price ?? apiProduct.price,
                currency: storeProduct.currency ?? apiProduct.currency,
                localizedPrice: storeProduct.localizedPrice ?? apiProduct.localizedPrice,
                subscriptionPeriod: storeProduct.subscriptionPeriod ?? apiProduct.subscriptionPeriod,
                trialPeriod: storeProduct.trialPeriod ?? apiProduct.trialPeriod,
                hasTrial: apiProduct.hasTrial || storeProduct.hasTrial,
                entitlementId: apiProduct.entitlementId,
                benefits: apiProduct.benefits,
                weeklyPointsEnabled: apiProduct.weeklyPointsEnabled,
                weeklyPoints: apiProduct.weeklyPoints
            )
        }
    }
}
