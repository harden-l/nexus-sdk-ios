import Foundation

final class CrossPromoAttributionStorage: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "nexus.crosspromo.pending_attribution"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ result: CrossPromoLinkResult) {
        defaults.set(try? encoder.encode(result), forKey: key)
    }

    func get() -> CrossPromoLinkResult? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(CrossPromoLinkResult.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
