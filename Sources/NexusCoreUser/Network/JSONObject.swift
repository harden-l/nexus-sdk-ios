import Foundation

enum JSONObject {
    static func encode(_ values: [String: Any?]) throws -> Data {
        try JSONSerialization.data(withJSONObject: clean(values), options: [])
    }

    static func decodeObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    static func decodeObject(_ string: String) throws -> [String: Any] {
        try decodeObject(Data(string.utf8))
    }

    static func clean(_ values: [String: Any?]) -> [String: Any] {
        values.reduce(into: [String: Any]()) { result, item in
            guard let value = item.value else { return }
            if let nested = value as? [String: Any?] {
                result[item.key] = clean(nested)
            } else if let array = value as? [Any?] {
                result[item.key] = array.compactMap { $0 }
            } else {
                result[item.key] = value
            }
        }
    }

    static func string(_ object: [String: Any], keys: String...) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
            if let value = object[key], !(value is NSNull) {
                let text = "\(value)"
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    static func int(_ object: [String: Any], key: String) -> Int? {
        if let value = object[key] as? Int { return value }
        if let value = object[key] as? NSNumber { return value.intValue }
        if let value = object[key] as? String { return Int(value) }
        return nil
    }

    static func double(_ object: [String: Any], key: String) -> Double? {
        if let value = object[key] as? Double { return value }
        if let value = object[key] as? NSNumber { return value.doubleValue }
        if let value = object[key] as? String { return Double(value) }
        return nil
    }

    static func bool(_ object: [String: Any], key: String, default defaultValue: Bool = false) -> Bool {
        if let value = object[key] as? Bool { return value }
        if let value = object[key] as? NSNumber { return value.boolValue }
        if let value = object[key] as? String { return value == "1" || value.lowercased() == "true" }
        return defaultValue
    }
}
