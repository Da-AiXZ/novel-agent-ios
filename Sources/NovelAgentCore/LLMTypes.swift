import Foundation

public enum LLMRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct LLMMessage: Codable, Hashable, Sendable {
    public var role: LLMRole
    public var content: String
    public var name: String?
    public var toolCallID: String?
    public var toolCalls: [LLMToolCall]

    public init(
        role: LLMRole,
        content: String,
        name: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [LLMToolCall] = []
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }
}

public struct JSONSchemaDefinition: Codable, Hashable, Sendable {
    public var name: String
    public var description: String
    public var schema: JSONValue
    public var strict: Bool

    public init(
        name: String,
        description: String,
        schema: JSONValue,
        strict: Bool = true
    ) {
        self.name = name
        self.description = description
        self.schema = schema
        self.strict = strict
    }
}

public enum ToolAccessLevel: String, Codable, Sendable {
    case read
    case stageWrite
    case destructive
}

public struct LLMToolDefinition: Codable, Hashable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue
    public var accessLevel: ToolAccessLevel

    public init(
        name: String,
        description: String,
        inputSchema: JSONValue,
        accessLevel: ToolAccessLevel
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.accessLevel = accessLevel
    }
}

public struct LLMRequest: Codable, Hashable, Sendable {
    public var model: String
    public var systemPrompt: String
    public var messages: [LLMMessage]
    public var tools: [LLMToolDefinition]
    public var responseSchema: JSONSchemaDefinition?
    public var maxOutputTokens: Int
    public var temperature: Double?
    public var metadata: [String: String]

    public init(
        model: String,
        systemPrompt: String,
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        responseSchema: JSONSchemaDefinition? = nil,
        maxOutputTokens: Int = 4_096,
        temperature: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
        self.responseSchema = responseSchema
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.metadata = metadata
    }
}

public struct LLMUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedInputTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cachedInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
    }

    public static func + (lhs: LLMUsage, rhs: LLMUsage) -> LLMUsage {
        LLMUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens
        )
    }
}

public struct LLMToolCall: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ProviderFailure: Codable, Hashable, Sendable {
    public var code: String
    public var message: String
    public var retryable: Bool
    public var retryAfterSeconds: Double?

    public init(
        code: String,
        message: String,
        retryable: Bool,
        retryAfterSeconds: Double? = nil
    ) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.retryAfterSeconds = retryAfterSeconds
    }
}

public enum LLMEvent: Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(id: String, name: String?, argumentsDelta: String)
    case toolCallCompleted(LLMToolCall)
    case usage(LLMUsage)
    case completed
    case failed(ProviderFailure)
}

public struct ProviderCapabilities: Codable, Hashable, Sendable {
    public var supportsStreaming: Bool
    public var supportsTools: Bool
    public var supportsStrictJSONSchema: Bool
    public var supportsEmbeddings: Bool
    public var maximumContextTokens: Int?
    public var maximumOutputTokens: Int?

    public init(
        supportsStreaming: Bool = true,
        supportsTools: Bool = true,
        supportsStrictJSONSchema: Bool = false,
        supportsEmbeddings: Bool = false,
        maximumContextTokens: Int? = nil,
        maximumOutputTokens: Int? = nil
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsTools = supportsTools
        self.supportsStrictJSONSchema = supportsStrictJSONSchema
        self.supportsEmbeddings = supportsEmbeddings
        self.maximumContextTokens = maximumContextTokens
        self.maximumOutputTokens = maximumOutputTokens
    }
}

public struct ProviderProbeResult: Codable, Hashable, Sendable {
    public var capabilities: ProviderCapabilities
    public var latencyMilliseconds: Int
    public var message: String

    public init(
        capabilities: ProviderCapabilities,
        latencyMilliseconds: Int,
        message: String
    ) {
        self.capabilities = capabilities
        self.latencyMilliseconds = latencyMilliseconds
        self.message = message
    }
}

public protocol LLMProvider: Sendable {
    var providerID: String { get }
    var capabilities: ProviderCapabilities { get }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error>
    func probe(model: String) async throws -> ProviderProbeResult
    func embed(texts: [String], model: String) async throws -> [[Float]]
}

public struct CollectedLLMResponse: Sendable {
    public var text: String
    public var toolCalls: [LLMToolCall]
    public var usage: LLMUsage

    public init(text: String = "", toolCalls: [LLMToolCall] = [], usage: LLMUsage = .init()) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

public enum LLMStreamCollector {
    public static func collect(
        provider: any LLMProvider,
        request: LLMRequest,
        onTextDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> CollectedLLMResponse {
        var response = CollectedLLMResponse()
        var partialToolCalls: [String: (name: String, arguments: String)] = [:]

        for try await event in provider.stream(request) {
            try Task.checkCancellation()
            switch event {
            case let .textDelta(delta):
                response.text += delta
                onTextDelta?(delta)
            case .reasoningDelta:
                break
            case let .toolCallDelta(id, name, argumentsDelta):
                var partial = partialToolCalls[id] ?? (name ?? "", "")
                if let name, !name.isEmpty {
                    partial.name = name
                }
                partial.arguments += argumentsDelta
                partialToolCalls[id] = partial
            case let .toolCallCompleted(call):
                response.toolCalls.removeAll { $0.id == call.id }
                response.toolCalls.append(call)
                partialToolCalls.removeValue(forKey: call.id)
            case let .usage(usage):
                response.usage = response.usage + usage
            case .completed:
                break
            case let .failed(failure):
                throw ProviderError.remote(failure)
            }
        }

        for (id, partial) in partialToolCalls where !partial.name.isEmpty {
            response.toolCalls.append(
                LLMToolCall(id: id, name: partial.name, arguments: partial.arguments)
            )
        }
        return response
    }
}

public enum ProviderError: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case invalidResponse(String)
    case http(statusCode: Int, message: String, retryAfterSeconds: Double?)
    case remote(ProviderFailure)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            "模型配置无效：\(message)"
        case let .invalidResponse(message):
            "模型响应无效：\(message)"
        case let .http(statusCode, message, _):
            "模型服务返回 HTTP \(statusCode)：\(message)"
        case let .remote(failure):
            failure.message
        case let .unsupported(message):
            "供应商不支持该能力：\(message)"
        }
    }
}
