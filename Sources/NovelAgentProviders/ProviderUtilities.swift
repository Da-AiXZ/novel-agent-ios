import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NovelAgentCore

enum ProviderUtilities {
    static func endpoint(baseURL: URL, path: String) -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(normalizedPath)
    }

    static func request(
        url: URL,
        apiKey: String,
        headers: [String: String],
        body: JSONValue
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONEncoder.novelAgent.encode(body)
        return request
    }

    static func decodeObject(_ data: String) throws -> [String: JSONValue] {
        guard let bytes = data.data(using: .utf8) else {
            throw CoreError.invalidUTF8
        }
        let value = try JSONDecoder.novelAgent.decode(JSONValue.self, from: bytes)
        guard let object = value.objectValue else {
            throw ProviderError.invalidResponse("SSE 数据不是 JSON 对象")
        }
        return object
    }

    static func int(_ value: JSONValue?) -> Int {
        guard case let .number(number) = value else { return 0 }
        return Int(number)
    }

    static func double(_ value: JSONValue?) -> Double? {
        guard case let .number(number) = value else { return nil }
        return number
    }

    static func bool(_ value: JSONValue?) -> Bool? {
        guard case let .bool(value) = value else { return nil }
        return value
    }

    static func retryable(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500
    }

    static func probe(
        provider: any LLMProvider,
        model: String
    ) async throws -> ProviderProbeResult {
        let clock = ContinuousClock()
        let start = clock.now
        let request = LLMRequest(
            model: model,
            systemPrompt: "只回复 OK。",
            messages: [LLMMessage(role: .user, content: "连接测试")],
            maxOutputTokens: 16,
            temperature: 0
        )
        let response = try await LLMStreamCollector.collect(provider: provider, request: request)
        let elapsed = start.duration(to: clock.now)
        let milliseconds = Int(elapsed.components.seconds * 1_000) +
            Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return ProviderProbeResult(
            capabilities: provider.capabilities,
            latencyMilliseconds: milliseconds,
            message: response.text.isEmpty ? "连接成功" : response.text
        )
    }
}

