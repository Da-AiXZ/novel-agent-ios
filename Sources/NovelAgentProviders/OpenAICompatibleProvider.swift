import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NovelAgentCore

public final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
    public let providerID = "openai-compatible"
    public let capabilities = ProviderCapabilities(
        supportsStreaming: true,
        supportsTools: true,
        supportsStrictJSONSchema: false,
        supportsEmbeddings: true
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
                        url: ProviderUtilities.endpoint(baseURL: baseURL, path: "chat/completions"),
                        apiKey: apiKey,
                        headers: ["Authorization": "Bearer \(apiKey)"],
                        body: try buildBody(request)
                    )
                    var toolIDsByIndex: [Int: String] = [:]
                    var toolNamesByIndex: [Int: String] = [:]
                    for try await message in transport.stream(urlRequest) {
                        try Task.checkCancellation()
                        if message.data == "[DONE]" { continue }
                        let object = try ProviderUtilities.decodeObject(message.data)
                        if let usage = object["usage"]?.objectValue {
                            continuation.yield(
                                .usage(
                                    LLMUsage(
                                        inputTokens: ProviderUtilities.int(usage["prompt_tokens"]),
                                        outputTokens: ProviderUtilities.int(usage["completion_tokens"]),
                                        cachedInputTokens: ProviderUtilities.int(
                                            usage["prompt_tokens_details"]?.objectValue?["cached_tokens"]
                                        )
                                    )
                                )
                            )
                        }
                        guard let choice = object["choices"]?.arrayValue?.first?.objectValue,
                              let delta = choice["delta"]?.objectValue
                        else { continue }
                        if let content = delta["content"]?.stringValue {
                            continuation.yield(.textDelta(content))
                        }
                        if let reasoning = delta["reasoning_content"]?.stringValue {
                            continuation.yield(.reasoningDelta(reasoning))
                        }
                        if let calls = delta["tool_calls"]?.arrayValue {
                            for call in calls {
                                guard let callObject = call.objectValue else { continue }
                                let index = ProviderUtilities.int(callObject["index"])
                                let function = callObject["function"]?.objectValue
                                if let id = callObject["id"]?.stringValue {
                                    toolIDsByIndex[index] = id
                                }
                                if let name = function?["name"]?.stringValue {
                                    toolNamesByIndex[index] = name
                                }
                                let id = toolIDsByIndex[index] ?? "tool-\(index)"
                                continuation.yield(
                                    .toolCallDelta(
                                        id: id,
                                        name: toolNamesByIndex[index],
                                        argumentsDelta: function?["arguments"]?.stringValue ?? ""
                                    )
                                )
                            }
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
        let body = JSONValue.object([
            "model": .string(model),
            "input": .array(texts.map(JSONValue.string))
        ])
        var request = try ProviderUtilities.request(
            url: ProviderUtilities.endpoint(baseURL: baseURL, path: "embeddings"),
            apiKey: apiKey,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await transport.data(request)
        let root = try JSONDecoder.novelAgent.decode(JSONValue.self, from: data)
        guard let items = root.objectValue?["data"]?.arrayValue else {
            throw ProviderError.invalidResponse("Embedding 响应缺少 data")
        }
        return try items.map { item in
            guard let values = item.objectValue?["embedding"]?.arrayValue else {
                throw ProviderError.invalidResponse("Embedding 项缺少向量")
            }
            return values.compactMap {
                guard case let .number(number) = $0 else { return nil }
                return Float(number)
            }
        }
    }

    private func buildBody(_ request: LLMRequest) throws -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "stream": .bool(true),
            "messages": .array(chatMessages(request)),
            "max_tokens": .number(Double(request.maxOutputTokens))
        ]
        if let temperature = request.temperature {
            body["temperature"] = .number(temperature)
        }
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { tool in
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "parameters": tool.inputSchema
                    ])
                ])
            })
        }
        if let schema = request.responseSchema {
            body["response_format"] = .object([
                "type": .string("json_object")
            ])
            body["messages"] = .array(
                chatMessages(request) + [
                    .object([
                        "role": .string("system"),
                        "content": .string(
                            "只输出 JSON，必须满足 schema \(schema.name)：\n" +
                            ((try? schema.schema.jsonString()) ?? "{}")
                        )
                    ])
                ]
            )
        }
        return .object(body)
    }

    private func chatMessages(_ request: LLMRequest) -> [JSONValue] {
        var messages: [JSONValue] = [
            .object([
                "role": .string("system"),
                "content": .string(request.systemPrompt)
            ])
        ]
        for message in request.messages {
            switch message.role {
            case .system, .user:
                messages.append(
                    .object([
                        "role": .string(message.role == .system ? "system" : "user"),
                        "content": .string(message.content)
                    ])
                )
            case .assistant:
                var object: [String: JSONValue] = [
                    "role": .string("assistant"),
                    "content": message.content.isEmpty ? .null : .string(message.content)
                ]
                if !message.toolCalls.isEmpty {
                    object["tool_calls"] = .array(message.toolCalls.map { call in
                        .object([
                            "id": .string(call.id),
                            "type": .string("function"),
                            "function": .object([
                                "name": .string(call.name),
                                "arguments": .string(call.arguments)
                            ])
                        ])
                    })
                }
                messages.append(.object(object))
            case .tool:
                messages.append(
                    .object([
                        "role": .string("tool"),
                        "tool_call_id": .string(message.toolCallID ?? ""),
                        "content": .string(message.content)
                    ])
                )
            }
        }
        return messages
    }
}

