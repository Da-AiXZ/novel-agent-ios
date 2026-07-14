import Foundation

public enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public static func encoded<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder.novelAgent.encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func decoded<T: Decodable>(as type: T.Type) throws -> T {
        let data = try JSONEncoder.novelAgent.encode(self)
        return try JSONDecoder.novelAgent.decode(type, from: data)
    }

    public func jsonString(prettyPrinted: Bool = false) throws -> String {
        let data = try JSONEncoder.novelAgent(prettyPrinted: prettyPrinted).encode(self)
        guard let value = String(data: data, encoding: .utf8) else {
            throw CoreError.invalidUTF8
        }
        return value
    }
}

public extension JSONEncoder {
    static var novelAgent: JSONEncoder {
        novelAgent(prettyPrinted: false)
    }

    static func novelAgent(prettyPrinted: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {
    static var novelAgent: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum CoreError: LocalizedError, Sendable {
    case invalidUTF8
    case invalidStructuredOutput(String)
    case missingTool(String)
    case permissionDenied(String)
    case maximumTurnsExceeded
    case budgetExceeded
    case staleRevision(expected: Int, actual: Int)
    case validationFailed([String])
    case missingData(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "文本不是有效的 UTF-8。"
        case let .invalidStructuredOutput(reason):
            "模型没有返回有效的结构化结果：\(reason)"
        case let .missingTool(name):
            "模型请求了未注册工具：\(name)"
        case let .permissionDenied(reason):
            "操作未获授权：\(reason)"
        case .maximumTurnsExceeded:
            "Agent 已达到最大回合数。"
        case .budgetExceeded:
            "Agent 已达到本次运行预算。"
        case let .staleRevision(expected, actual):
            "项目版本已变化，预期 \(expected)，实际 \(actual)。"
        case let .validationFailed(errors):
            "状态校验失败：\(errors.joined(separator: "；"))"
        case let .missingData(name):
            "缺少必要数据：\(name)"
        case let .unsupported(reason):
            "当前配置不支持该操作：\(reason)"
        }
    }
}

