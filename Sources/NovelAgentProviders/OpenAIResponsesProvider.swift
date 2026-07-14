import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NovelAgentCore

public final class OpenAIResponsesProvider: LLMProvider, @unchecked Sendable {
    public let providerID = "openai-responses"
    public let capabilities = ProviderCapabilities(
        supportsStreaming: true,
        supportsTools: true,
        supportsStrictJSONSchema: true,
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
                    let body = try buildBody(request)
                    let urlRequest = try ProviderUtilities.request(
                        url: ProviderUtilities.endpoint(baseURL: baseURL, path: "responses"),
                        apiKey: apiKey,
                        headers: ["Authorization": "Bearer \(apiKey)"],
                        body: body
                    )
                    for try await message in transport.stream(urlRequest) {
                        try Task.checkCancellation()
                        if message.data == "[DONE]" { continue }
                        try emit(message: message, continuation: continuation)
                    }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch let error as ProviderError {
                    continuation.finish(throwing: error)
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
            "input": .array(texts.map(JSONValue.string)),
            "encoding_format": .string("float")
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
            "instructions": .string(request.systemPrompt),
            "input": .array(inputItems(request.messages)),
            "stream": .bool(true),
            "max_output_tokens": .number(Double(request.maxOutputTokens))
        ]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { tool in
                .object([
                    "type": .string("function"),
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": tool.inputSchema,
                    "strict": .bool(true)
                ])
            })
        }
        if let schema = request.responseSchema {
            body["text"] = .object([
                "format": .object([
                    "type": .string("json_schema"),
                    "name": .string(schema.name),
                    "description": .string(schema.description),
                    "schema": schema.schema,
                    "strict": .bool(schema.strict)
                ])
            ])
        }
        if !request.metadata.isEmpty {
            body["metadata"] = .object(request.metadata.mapValues(JSONValue.string))
        }
        return .object(body)
    }

    private func inputItems(_ messages: [LLMMessage]) -> [JSONValue] {
        var items: [JSONValue] = []
        for message in messages {
            switch message.role {
            case .system:
                items.append(messageItem(role: "developer", type: "input_text", text: message.content))
            case .user:
                items.append(messageItem(role: "user", type: "input_text", text: message.content))
            case .assistant:
                if !message.content.isEmpty {
                    items.append(messageItem(role: "assistant", type: "output_text", text: message.content))
                }
                for call in message.toolCalls {
                    items.append(
                        .object([
                            "type": .string("function_call"),
                            "call_id": .string(call.id),
                            "name": .string(call.name),
                            "arguments": .string(call.arguments)
                        ])
                    )
                }
            case .tool:
                items.append(
                    .object([
                        "type": .string("function_call_output"),
                        "call_id": .string(message.toolCallID ?? ""),
                        "output": .string(message.content)
                    ])
                )
            }
        }
        return items
    }

    private func messageItem(role: String, type: String, text: String) -> JSONValue {
        .object([
            "role": .string(role),
            "content": .array([
                .object([
                    "type": .string(type),
                    "text": .string(text)
                ])
            ])
        ])
    }

    private func emit(
        message: SSEMessage,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) throws {
        let object = try ProviderUtilities.decodeObject(message.data)
        let type = object["type"]?.stringValue ?? message.event ?? ""
        switch type {
        case "response.output_text.delta":
            if let delta = object["delta"]?.stringValue {
                continuation.yield(.textDelta(delta))
            }
        case "response.reasoning_text.delta":
            if let delta = object["delta"]?.stringValue {
                continuation.yield(.reasoningDelta(delta))
            }
        case "response.output_item.added":
            guard let item = object["item"]?.objectValue,
                  item["type"]?.stringValue == "function_call"
            else { return }
            continuation.yield(
                .toolCallDelta(
                    id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? UUID().uuidString,
                    name: item["name"]?.stringValue,
                    argumentsDelta: ""
                )
            )
        case "response.function_call_arguments.delta":
            continuation.yield(
                .toolCallDelta(
                    id: object["call_id"]?.stringValue ?? object["item_id"]?.stringValue ?? "",
                    name: object["name"]?.stringValue,
                    argumentsDelta: object["delta"]?.stringValue ?? ""
                )
            )
        case "response.output_item.done":
            guard let item = object["item"]?.objectValue,
                  item["type"]?.stringValue == "function_call",
                  let name = item["name"]?.stringValue
            else { return }
            continuation.yield(
                .toolCallCompleted(
                    LLMToolCall(
                        id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "",
                        name: name,
                        arguments: item["arguments"]?.stringValue ?? "{}"
                    )
                )
            )
        case "response.completed":
            if let usage = object["response"]?.objectValue?["usage"]?.objectValue {
                let details = usage["input_tokens_details"]?.objectValue
                continuation.yield(
                    .usage(
                        LLMUsage(
                            inputTokens: ProviderUtilities.int(usage["input_tokens"]),
                            outputTokens: ProviderUtilities.int(usage["output_tokens"]),
                            cachedInputTokens: ProviderUtilities.int(details?["cached_tokens"])
                        )
                    )
                )
            }
        case "response.failed", "error":
            let error = object["response"]?.objectValue?["error"]?.objectValue ??
                object["error"]?.objectValue
            continuation.yield(
                .failed(
                    ProviderFailure(
                        code: error?["code"]?.stringValue ?? "response_failed",
                        message: error?["message"]?.stringValue ?? "模型请求失败",
                        retryable: true
                    )
                )
            )
        default:
            break
        }
    }
}

