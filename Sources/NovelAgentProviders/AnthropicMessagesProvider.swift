import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NovelAgentCore

public final class AnthropicMessagesProvider: LLMProvider, @unchecked Sendable {
    public let providerID = "anthropic-messages"
    public let capabilities = ProviderCapabilities(
        supportsStreaming: true,
        supportsTools: true,
        supportsStrictJSONSchema: true,
        supportsEmbeddings: false
    )

    private let baseURL: URL
    private let apiKey: String
    private let transport: SSETransport

    public init(baseURL: URL, apiKey: String, session: URLSession = .novelAgent) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.transport = SSETransport(session: session)
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try ProviderUtilities.request(
                        url: ProviderUtilities.endpoint(baseURL: baseURL, path: "messages"),
                        apiKey: apiKey,
                        headers: [
                            "x-api-key": apiKey,
                            "anthropic-version": "2023-06-01"
                        ],
                        body: try buildBody(request)
                    )
                    var toolBlocks: [Int: (id: String, name: String)] = [:]
                    for try await message in transport.stream(urlRequest) {
                        try Task.checkCancellation()
                        let object = try ProviderUtilities.decodeObject(message.data)
                        let type = object["type"]?.stringValue ?? message.event ?? ""
                        switch type {
                        case "message_start":
                            if let usage = object["message"]?.objectValue?["usage"]?.objectValue {
                                continuation.yield(
                                    .usage(
                                        LLMUsage(
                                            inputTokens: ProviderUtilities.int(usage["input_tokens"]),
                                            cachedInputTokens:
                                                ProviderUtilities.int(usage["cache_read_input_tokens"]) +
                                                ProviderUtilities.int(usage["cache_creation_input_tokens"])
                                        )
                                    )
                                )
                            }
                        case "content_block_start":
                            let index = ProviderUtilities.int(object["index"])
                            guard let block = object["content_block"]?.objectValue,
                                  block["type"]?.stringValue == "tool_use"
                            else { continue }
                            let id = block["id"]?.stringValue ?? "tool-\(index)"
                            let name = block["name"]?.stringValue ?? ""
                            toolBlocks[index] = (id, name)
                            continuation.yield(
                                .toolCallDelta(id: id, name: name, argumentsDelta: "")
                            )
                        case "content_block_delta":
                            let index = ProviderUtilities.int(object["index"])
                            guard let delta = object["delta"]?.objectValue else { continue }
                            switch delta["type"]?.stringValue {
                            case "text_delta":
                                continuation.yield(.textDelta(delta["text"]?.stringValue ?? ""))
                            case "thinking_delta":
                                continuation.yield(.reasoningDelta(delta["thinking"]?.stringValue ?? ""))
                            case "input_json_delta":
                                if let tool = toolBlocks[index] {
                                    continuation.yield(
                                        .toolCallDelta(
                                            id: tool.id,
                                            name: tool.name,
                                            argumentsDelta: delta["partial_json"]?.stringValue ?? ""
                                        )
                                    )
                                }
                            default:
                                break
                            }
                        case "message_delta":
                            if let usage = object["usage"]?.objectValue {
                                continuation.yield(
                                    .usage(
                                        LLMUsage(
                                            outputTokens: ProviderUtilities.int(usage["output_tokens"])
                                        )
                                    )
                                )
                            }
                        case "error":
                            let error = object["error"]?.objectValue
                            continuation.yield(
                                .failed(
                                    ProviderFailure(
                                        code: error?["type"]?.stringValue ?? "anthropic_error",
                                        message: error?["message"]?.stringValue ?? "模型请求失败",
                                        retryable: true
                                    )
                                )
                            )
                        default:
                            break
                        }
                    }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func probe(model: String) async throws -> ProviderProbeResult {
        try await ProviderUtilities.probe(provider: self, model: model)
    }

    public func embed(texts: [String], model: String) async throws -> [[Float]] {
        throw ProviderError.unsupported("Anthropic Messages API 不提供 embedding")
    }

    private func buildBody(_ request: LLMRequest) throws -> JSONValue {
        var tools = request.tools.map { tool in
            JSONValue.object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "input_schema": tool.inputSchema
            ])
        }
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "system": .string(request.systemPrompt),
            "messages": .array(messages(request.messages)),
            "max_tokens": .number(Double(request.maxOutputTokens)),
            "stream": .bool(true)
        ]
        if let temperature = request.temperature {
            body["temperature"] = .number(temperature)
        }
        if let schema = request.responseSchema {
            tools.append(
                .object([
                    "name": .string(schema.name),
                    "description": .string(schema.description),
                    "input_schema": schema.schema,
                    "strict": .bool(schema.strict)
                ])
            )
            body["tool_choice"] = .object([
                "type": .string("tool"),
                "name": .string(schema.name)
            ])
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools)
        }
        return .object(body)
    }

    private func messages(_ messages: [LLMMessage]) -> [JSONValue] {
        var result: [JSONValue] = []
        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                result.append(
                    .object([
                        "role": .string("user"),
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string(message.content)
                            ])
                        ])
                    ])
                )
            case .assistant:
                var content: [JSONValue] = []
                if !message.content.isEmpty {
                    content.append(
                        .object([
                            "type": .string("text"),
                            "text": .string(message.content)
                        ])
                    )
                }
                content.append(contentsOf: message.toolCalls.map { call in
                    let input: JSONValue
                    if let data = call.arguments.data(using: .utf8),
                       let decoded = try? JSONDecoder.novelAgent.decode(JSONValue.self, from: data) {
                        input = decoded
                    } else {
                        input = .object([:])
                    }
                    return .object([
                        "type": .string("tool_use"),
                        "id": .string(call.id),
                        "name": .string(call.name),
                        "input": input
                    ])
                })
                result.append(.object(["role": .string("assistant"), "content": .array(content)]))
            case .tool:
                result.append(
                    .object([
                        "role": .string("user"),
                        "content": .array([
                            .object([
                                "type": .string("tool_result"),
                                "tool_use_id": .string(message.toolCallID ?? ""),
                                "content": .string(message.content)
                            ])
                        ])
                    ])
                )
            case .system:
                break
            }
        }
        return result
    }
}

