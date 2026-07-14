import Foundation

public enum StructuredOutputGenerator {
    public static func generate<T: Decodable & Sendable>(
        provider: any LLMProvider,
        request: LLMRequest,
        as type: T.Type,
        allowRepair: Bool = true
    ) async throws -> T {
        let response = try await LLMStreamCollector.collect(provider: provider, request: request)
        let raw = structuredCandidate(from: response, schemaName: request.responseSchema?.name)

        do {
            return try decode(T.self, from: raw)
        } catch {
            guard allowRepair, let schema = request.responseSchema else {
                throw CoreError.invalidStructuredOutput(error.localizedDescription)
            }
            let repairRequest = LLMRequest(
                model: request.model,
                systemPrompt: """
                你是 JSON 修复器。只输出满足给定 JSON Schema 的 JSON。
                不解释、不使用 Markdown 代码块、不补充 schema 外字段。
                """,
                messages: [
                    LLMMessage(
                        role: .user,
                        content: """
                        原始输出：
                        \(raw)

                        请修复为 schema \(schema.name) 所要求的合法 JSON。
                        """
                    )
                ],
                responseSchema: schema,
                maxOutputTokens: request.maxOutputTokens,
                temperature: 0
            )
            let repaired = try await LLMStreamCollector.collect(
                provider: provider,
                request: repairRequest
            )
            let repairedRaw = structuredCandidate(
                from: repaired,
                schemaName: schema.name
            )
            do {
                return try decode(T.self, from: repairedRaw)
            } catch {
                throw CoreError.invalidStructuredOutput(error.localizedDescription)
            }
        }
    }

    private static func structuredCandidate(
        from response: CollectedLLMResponse,
        schemaName: String?
    ) -> String {
        if let schemaName,
           let call = response.toolCalls.first(where: {
               $0.name == schemaName || $0.name == "emit_structured_output"
           }) {
            return call.arguments
        }
        if let call = response.toolCalls.first, response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return call.arguments
        }
        return response.text
    }

    private static func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let cleaned = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw CoreError.invalidUTF8
        }
        return try JSONDecoder.novelAgent.decode(type, from: data)
    }

    private static func stripCodeFence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

