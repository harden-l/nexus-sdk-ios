import Foundation

enum CoinAmountFormatter {
    private static let displayScale = Decimal(100)

    static func displayText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value * displayScale).stringValue
    }

    static func displayUnitText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
