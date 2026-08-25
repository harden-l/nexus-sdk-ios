import Foundation

public enum SubscriptionPageTemplateId: String, CaseIterable, Sendable {
    case aurora
    case midnight
    case minimal
}

#if canImport(UIKit)
import UIKit

struct SubscriptionPageTheme {
    let id: SubscriptionPageTemplateId
    let pageBackground: UIColor
    let surface: UIColor
    let elevatedSurface: UIColor
    let primary: UIColor
    let accent: UIColor
    let title: UIColor
    let body: UIColor
    let muted: UIColor
    let border: UIColor
    let selectedSurface: UIColor
    let tagSurface: UIColor
    let dark: Bool

    static func resolve(_ templateId: String) -> SubscriptionPageTheme {
        switch SubscriptionPageTemplateId(rawValue: templateId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
        case .midnight: midnight
        case .minimal: minimal
        default: aurora
        }
    }

    private static let aurora = SubscriptionPageTheme(
        id: .aurora,
        pageBackground: UIColor(red: 247/255, green: 248/255, blue: 252/255, alpha: 1),
        surface: .white,
        elevatedSurface: UIColor(red: 242/255, green: 247/255, blue: 1, alpha: 1),
        primary: UIColor(red: 18/255, green: 100/255, blue: 232/255, alpha: 1),
        accent: UIColor(red: 8/255, green: 166/255, blue: 181/255, alpha: 1),
        title: UIColor(red: 20/255, green: 24/255, blue: 39/255, alpha: 1),
        body: UIColor(red: 50/255, green: 56/255, blue: 73/255, alpha: 1),
        muted: UIColor(red: 102/255, green: 110/255, blue: 128/255, alpha: 1),
        border: UIColor(red: 220/255, green: 224/255, blue: 234/255, alpha: 1),
        selectedSurface: UIColor(red: 239/255, green: 238/255, blue: 1, alpha: 1),
        tagSurface: UIColor(red: 230/255, green: 250/255, blue: 247/255, alpha: 1),
        dark: false
    )

    private static let midnight = SubscriptionPageTheme(
        id: .midnight,
        pageBackground: UIColor(red: 19/255, green: 22/255, blue: 28/255, alpha: 1),
        surface: UIColor(red: 35/255, green: 39/255, blue: 47/255, alpha: 1),
        elevatedSurface: UIColor(red: 43/255, green: 47/255, blue: 58/255, alpha: 1),
        primary: UIColor(red: 88/255, green: 191/255, blue: 1, alpha: 1),
        accent: UIColor(red: 99/255, green: 230/255, blue: 191/255, alpha: 1),
        title: .white,
        body: UIColor(red: 226/255, green: 230/255, blue: 238/255, alpha: 1),
        muted: UIColor(red: 166/255, green: 174/255, blue: 190/255, alpha: 1),
        border: UIColor(red: 72/255, green: 78/255, blue: 91/255, alpha: 1),
        selectedSurface: UIColor(red: 39/255, green: 57/255, blue: 83/255, alpha: 1),
        tagSurface: UIColor(red: 35/255, green: 71/255, blue: 65/255, alpha: 1),
        dark: true
    )

    private static let minimal = SubscriptionPageTheme(
        id: .minimal,
        pageBackground: .white,
        surface: .white,
        elevatedSurface: UIColor(red: 246/255, green: 248/255, blue: 251/255, alpha: 1),
        primary: UIColor(red: 23/255, green: 107/255, blue: 77/255, alpha: 1),
        accent: UIColor(red: 194/255, green: 138/255, blue: 44/255, alpha: 1),
        title: UIColor(red: 22/255, green: 27/255, blue: 34/255, alpha: 1),
        body: UIColor(red: 55/255, green: 65/255, blue: 81/255, alpha: 1),
        muted: UIColor(red: 107/255, green: 114/255, blue: 128/255, alpha: 1),
        border: UIColor(red: 209/255, green: 213/255, blue: 219/255, alpha: 1),
        selectedSurface: UIColor(red: 241/255, green: 248/255, blue: 243/255, alpha: 1),
        tagSurface: UIColor(red: 248/255, green: 243/255, blue: 229/255, alpha: 1),
        dark: false
    )
}
#endif
