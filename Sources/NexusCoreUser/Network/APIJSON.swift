import Foundation

// Decode numbers directly as Decimal so envelope extraction never round-trips through Double.
indirect enum APIJSON: Codable, Sendable {
    case object([String: APIJSON]), array([APIJSON]), string(String), number(Decimal), bool(Bool), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Decimal.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: APIJSON].self) { self = .object(value) }
        else { self = .array(try container.decode([APIJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    subscript(_ key: String) -> APIJSON {
        if case .object(let value) = self { return value[key] ?? .null }
        return .null
    }
    var string: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return NSDecimalNumber(decimal: value).stringValue
        default: return ""
        }
    }
    var decimal: Decimal {
        switch self {
        case .number(let value): return value
        case .string(let value): return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        default: return 0
        }
    }
    var int: Int { NSDecimalNumber(decimal: decimal).intValue }
    var int64: Int64 { NSDecimalNumber(decimal: decimal).int64Value }
    var bool: Bool {
        if case .bool(let value) = self { return value }
        return int == 1
    }
    var array: [APIJSON] {
        if case .array(let value) = self { return value }
        return []
    }
    func data() throws -> Data { try JSONEncoder().encode(self) }
    static func decode(_ data: Data) throws -> APIJSON { try JSONDecoder().decode(APIJSON.self, from: data) }

    func requireNumber(_ key: String) throws -> Decimal {
        guard case .number(let value) = self[key], !value.isNaN else {
            throw CoreUserError.invalidResponse("Missing or invalid number: \(key)")
        }
        return value
    }
    func requireString(_ key: String, nonempty: Bool = true) throws -> String {
        guard case .string(let value) = self[key], !nonempty || !value.isEmpty else {
            throw CoreUserError.invalidResponse("Missing or invalid string: \(key)")
        }
        return value
    }
    func requireSeconds(_ key: String) throws -> Int64 {
        let value = try requireNumber(key)
        guard value >= 0, value <= Decimal(Int64.max), value == Decimal(self[key].int64) else {
            throw CoreUserError.invalidResponse("Invalid Unix seconds: \(key)")
        }
        return self[key].int64
    }
    func requireBool(_ key: String) throws -> Bool {
        guard case .bool(let value) = self[key] else { throw CoreUserError.invalidResponse("Missing or invalid boolean: \(key)") }
        return value
    }
}
