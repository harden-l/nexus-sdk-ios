import Foundation
import NexusCoreUser

enum ProductPresentation {
    static func price(_ product: Product) -> String? {
        if product.storeDetailsAvailable {
            return storePrice(product)
        }
        guard let cents = product.priceUsd else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        let amount = NSDecimalNumber(decimal: Decimal(cents) / 100)
        return "Reference USD \(formatter.string(from: amount) ?? amount.stringValue)"
    }

    // All three templates share these independent benefits.
    static func creditBenefits(_ product: Product) -> [String] {
        var lines: [String] = []
        if product.coinsGrantedDecimal > 0 {
            lines.append("Get \(CoinAmountFormatter.displayText(product.coinsGrantedDecimal)) credits after purchase")
        }
        if product.productType == .subscription, product.weeklyPointsEnabled, product.weeklyPointsDecimal > 0 {
            lines.append("Plus \(CoinAmountFormatter.displayText(product.weeklyPointsDecimal)) points every week")
        }
        return lines
    }

    static func claimDetail(_ info: WeeklyPointsInfo) -> String {
        if info.canClaim {
            return "\(CoinAmountFormatter.displayText(info.weeklyPointsDecimal)) points ready to claim"
        }
        switch info.cannotClaimReason {
        case "already_claimed": return "Claimed for this week"
        case "no_valid_subscription": return "An eligible subscription is required"
        case "product_not_configured": return "Weekly points are unavailable for this subscription"
        default: return "Weekly points are currently unavailable"
        }
    }

    static func canPurchase(_ product: Product?, channel: PaymentChannel?, pendingProductIds: Set<String>) -> Bool {
        guard let product, !pendingProductIds.contains(product.marketProductId) else { return false }
        if channel == .mock { return true }
        return channel == .appStore && product.storeDetailsAvailable &&
            storePrice(product) != nil
    }

    private static func storePrice(_ product: Product) -> String? {
        [product.localizedPrice, product.price].compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
