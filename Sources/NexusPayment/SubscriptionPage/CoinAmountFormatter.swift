import Foundation

enum CoinAmountFormatter {
    private static let displayScale = Decimal(100)

    static func displayText(_ value: Double) -> String {
        let amount = Decimal(string: String(value)) ?? Decimal(value)
        return NSDecimalNumber(decimal: amount * displayScale).stringValue
    }

    static func displayUnitText(_ value: Double) -> String {
        let amount = Decimal(string: String(value)) ?? Decimal(value)
        return NSDecimalNumber(decimal: amount).stringValue
    }
}
